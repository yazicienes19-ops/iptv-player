import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../providers/app_providers.dart';
import '../providers/imdb_providers.dart';
import '../services/http_client.dart';
import '../services/network_security.dart';
import '../services/personal_library.dart';
import '../services/recommendations.dart';
import '../services/webos.dart';
import 'hls_resolver.dart';
import 'mpv/mpv_bridge.dart';

/// Bildformat-Umschalter: Original, Zoom (beschneiden), Strecken.
enum VideoFit {
  contain('Original', BoxFit.contain),
  cover('Zoom', BoxFit.cover),
  fill('Strecken', BoxFit.fill);

  const VideoFit(this.label, this.boxFit);

  final String label;
  final BoxFit boxFit;

  VideoFit get next => VideoFit.values[(index + 1) % VideoFit.values.length];
}

class PlaybackState {
  const PlaybackState({
    this.channel,
    this.queue = const [],
    this.isLoading = false,
    this.error,
    this.retryAttempt = 0,
    this.retryCountdown,
    this.autoRetry = true,
    this.fit = VideoFit.contain,
  });

  final Channel? channel;

  /// Die Liste, aus der der Sender gestartet wurde (für Kanalwechsel).
  final List<Channel> queue;
  final bool isLoading;
  final String? error;
  final int retryAttempt;

  /// Sekunden bis zum nächsten automatischen Versuch, sonst `null`.
  final int? retryCountdown;
  final bool autoRetry;
  final VideoFit fit;

  bool get hasError => error != null;

  PlaybackState copyWith({
    Channel? channel,
    List<Channel>? queue,
    bool? isLoading,
    String? Function()? error,
    int? retryAttempt,
    int? Function()? retryCountdown,
    bool? autoRetry,
    VideoFit? fit,
  }) {
    return PlaybackState(
      channel: channel ?? this.channel,
      queue: queue ?? this.queue,
      isLoading: isLoading ?? this.isLoading,
      error: error != null ? error() : this.error,
      retryAttempt: retryAttempt ?? this.retryAttempt,
      retryCountdown: retryCountdown != null ? retryCountdown() : this.retryCountdown,
      autoRetry: autoRetry ?? this.autoRetry,
      fit: fit ?? this.fit,
    );
  }
}

/// Besitzt den einzigen libmpv-Player der App. Alle Ansichten (eingebettet,
/// Mini-Player, Vollbild) teilen sich denselben [VideoController].
class PlayerController extends Notifier<PlaybackState> {
  static const maxRetries = 3;
  static const _startTimeout = Duration(seconds: 20);

  static const _hlsResolver = HlsResolver();

  late Player player;
  late VideoController videoController;

  final _subscriptions = <StreamSubscription<Object?>>[];
  Timer? _watchdog;
  Timer? _retryTimer;
  Timer? _watchFlushTimer;
  final _watchClock = Stopwatch()..start();
  final _viewingTime = LiveWatchAccumulator();
  late PersonalLibraryNotifier _personalLibrary;
  String? _watchPlaylistId;
  Channel? _watchChannel;
  List<String> _watchKeys = const [];

  /// Erhöht sich bei jedem Öffnen; verhindert, dass Ereignisse eines alten
  /// Streams den Zustand des neuen überschreiben.
  int _session = 0;

  /// Erst nach `open()` des aktuellen Streams zählen Bild-/Positionsereignisse;
  /// vorher stammen sie noch vom vorherigen Stream.
  bool _acceptStartEvents = false;
  DateTime? _openedAt;

  @override
  PlaybackState build() {
    _personalLibrary = ref.read(personalLibraryProvider.notifier);
    player = Player(
      configuration: const PlayerConfiguration(title: 'IpFlix', bufferSize: 64 * 1024 * 1024),
    );
    videoController = VideoController(player);

    _subscriptions.addAll([
      player.stream.error.listen(_onError),
      player.stream.width.listen((w) {
        if (w != null && w > 0) _markStarted();
      }),
      player.stream.position.listen((p) {
        // Bei separat angehängten Tonspuren läuft der Ton vor dem ersten Bild an.
        // Fortschritt zählt deshalb erst nach 3 s als Start (nur für reine Radio-Streams).
        final openedFor = _openedAt == null ? Duration.zero : DateTime.now().difference(_openedAt!);
        if (p > Duration.zero && openedFor > const Duration(seconds: 3)) _markStarted();
        _viewingTime.sample(
          position: p,
          elapsed: _watchClock.elapsed,
          rate: player.state.rate,
          eligible:
              _watchChannel != null &&
              _acceptStartEvents &&
              !state.isLoading &&
              !state.hasError &&
              player.state.playing &&
              !player.state.buffering,
        );
      }),
      player.stream.playing.listen((playing) {
        if (!playing) {
          _viewingTime.resetSample();
          _flushWatch();
        }
      }),
      player.stream.buffering.listen((buffering) {
        if (buffering) {
          _viewingTime.resetSample();
          _flushWatch();
        }
      }),
      player.stream.completed.listen((done) {
        if (done && _acceptStartEvents && state.channel?.type != ContentType.live) _flushWatch(reachedEnd: true);
        // Ein Live-Stream „endet“ nur, wenn die Verbindung abreißt.
        if (done && _acceptStartEvents && state.channel?.type == ContentType.live) {
          _onError('Der Stream wurde unterbrochen.');
        }
      }),
    ]);

    // Kill-Switch: Bricht das VPN während der Wiedergabe weg, sofort stoppen.
    ref.listen(networkBlockedProvider, (_, blocked) {
      if (blocked && state.channel != null) _blockByKillSwitch();
    });
    ref.listen(activePlaylistProvider, (before, after) {
      if (before?.id != after?.id && state.channel != null) unawaited(stop());
    });
    _watchFlushTimer = Timer.periodic(const Duration(seconds: 15), (_) => _flushWatch());

    // Kein Festplatten-Cache: Stream-Inhalte und -URLs landen nie auf der Platte.
    _setMpvOption('cache-on-disk', 'no');

    ref.onDispose(() {
      _flushWatch();
      _watchFlushTimer?.cancel();
      _cancelTimers();
      for (final s in _subscriptions) {
        s.cancel();
      }
      _subscriptions.clear();
      player.dispose();
    });

    return const PlaybackState();
  }

  Future<void> play(Channel channel, {List<Channel>? queue}) async {
    if (!channel.isPlayable) return;
    _flushWatch();
    _viewingTime.resetSample();
    _watchPlaylistId = ref.read(activePlaylistProvider)?.id;
    _watchChannel = channel.seriesId == null
        ? channel
        : ref
                  .read(catalogProvider(ContentType.series))
                  .value
                  ?.channels
                  .where((series) => series.id == channel.seriesId)
                  .firstOrNull ??
              channel;
    _watchKeys = recommendationKeys(_watchChannel!, ref.read(imdbCatalogProvider).value);
    state = state.copyWith(channel: channel, queue: queue, retryAttempt: 0);
    await _open();
  }

  Future<void> retry() async {
    if (state.channel == null) return;
    state = state.copyWith(retryAttempt: 0);
    await _open();
  }

  Future<void> stop() async {
    _flushWatch();
    _viewingTime.resetSample();
    _watchChannel = null;
    _watchKeys = const [];
    _watchPlaylistId = null;
    _session++;
    _cancelTimers();
    await player.stop();
    state = PlaybackState(autoRetry: state.autoRetry, fit: state.fit);
  }

  /// Beendet Filme und Folgen; Live-Sender laufen weiter.
  Future<void> stopIfOnDemand() async {
    final channel = state.channel;
    if (channel != null && channel.type != ContentType.live) await stop();
  }

  Future<void> next() => _step(1);

  Future<void> previous() => _step(-1);

  Future<void> _step(int delta) async {
    final queue = state.queue;
    final current = state.channel;
    if (queue.isEmpty || current == null) return;
    final index = queue.indexOf(current);
    final target = queue[((index < 0 ? 0 : index) + delta) % queue.length];
    await play(target);
  }

  void toggleAutoRetry() {
    state = state.copyWith(autoRetry: !state.autoRetry);
    if (!state.autoRetry) {
      _retryTimer?.cancel();
      state = state.copyWith(retryCountdown: () => null);
    }
  }

  void cycleFit() => state = state.copyWith(fit: state.fit.next);

  Future<void> _open() async {
    _flushWatch();
    _viewingTime.resetSample();
    final channel = state.channel!;
    final session = ++_session;
    _cancelTimers();
    state = state.copyWith(isLoading: true, error: () => null, retryCountdown: () => null);

    _watchdog = Timer(_startTimeout, () {
      if (session == _session && state.isLoading) {
        _onError('Zeitüberschreitung: Der Sender liefert keine Daten.');
      }
    });

    _acceptStartEvents = false;
    try {
      await ref.read(networkGuardProvider).ensureAllowed();
      // Getarnter User-Agent auch für libmpv (gilt für Video- und angehängte Tonspuren).
      await _setMpvOption('user-agent', ref.read(userAgentProvider));
      if (session != _session) return;
      // Im Browser spielt der Fernseher HLS selbst ab, samt separater Tonspuren.
      // Auf webOS läuft der Stream über den Hilfsdienst, damit der getarnte User-Agent gilt.
      final stream = kIsWeb
          ? ResolvedStream(proxiedUrl(channel.streamUrl, userAgent: ref.read(userAgentProvider)))
          : await _hlsResolver.resolve(channel.streamUrl, ref.read(httpClientProvider));
      if (session != _session) return;
      // stop() setzt Breite und Position zurück, damit alte Werte nicht als Start zählen.
      await player.stop();
      if (session != _session) return;
      await player.open(Media(stream.url));
      if (session == _session) {
        _acceptStartEvents = true;
        _openedAt = DateTime.now();
      }
      for (final (i, audio) in stream.audio.indexed) {
        if (session != _session) return;
        await mpvCommand(player, ['audio-add', audio.url, i == 0 ? 'select' : 'auto', audio.name, ?audio.language]);
      }
    } catch (e) {
      if (session != _session) return;
      if (isKillSwitchError(e)) {
        _blockByKillSwitch();
      } else {
        _onError('$e');
      }
    }
  }

  /// Kein automatischer Neuversuch: Erst ein VPN hebt die Sperre auf.
  void _blockByKillSwitch() {
    _flushWatch();
    _viewingTime.resetSample();
    _acceptStartEvents = false;
    _session++;
    _cancelTimers();
    player.stop();
    state = state.copyWith(
      isLoading: false,
      error: () => '${const KillSwitchException()}\nVerbinde dein VPN und versuche es erneut.',
      retryCountdown: () => null,
    );
  }

  Future<void> _setMpvOption(String name, String value) => mpvSetProperty(player, name, value);

  void _markStarted() {
    if (!_acceptStartEvents || (!state.isLoading && !state.hasError)) return;
    _watchdog?.cancel();
    state = state.copyWith(isLoading: false, error: () => null, retryAttempt: 0, retryCountdown: () => null);
  }

  void _onError(String message) {
    _flushWatch();
    _viewingTime.resetSample();
    if (state.channel == null || _retryTimer?.isActive == true) return;
    _watchdog?.cancel();
    final attempt = state.retryAttempt + 1;
    final friendly = _describe(message);

    if (!state.autoRetry || attempt > maxRetries) {
      state = state.copyWith(isLoading: false, error: () => friendly, retryCountdown: () => null);
      return;
    }

    // Wartezeit wächst mit jedem Versuch: 3 s, 6 s, 9 s.
    var remaining = 3 * attempt;
    final session = _session;
    state = state.copyWith(
      isLoading: false,
      error: () => friendly,
      retryAttempt: attempt,
      retryCountdown: () => remaining,
    );
    _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (session != _session) return timer.cancel();
      remaining--;
      if (remaining > 0) {
        state = state.copyWith(retryCountdown: () => remaining);
      } else {
        timer.cancel();
        _open();
      }
    });
  }

  void _cancelTimers() {
    _watchdog?.cancel();
    _retryTimer?.cancel();
  }

  void _flushWatch({bool reachedEnd = false}) {
    final watched = _viewingTime.take();
    final playlistId = _watchPlaylistId;
    final channel = _watchChannel;
    if (playlistId == null || channel == null || watched <= Duration.zero && !reachedEnd) return;
    // The captured playlist belongs to the playing session, even during an
    // account switch. A persistence failure never interrupts the video.
    final write = channel.type == ContentType.live
        ? _personalLibrary.addWatch(playlistId, channel, watched)
        : _personalLibrary.addVodWatch(
            playlistId,
            channel,
            watched,
            duration: player.state.duration,
            capturedKeys: _watchKeys,
            reachedEnd:
                reachedEnd ||
                player.state.duration > Duration.zero &&
                    player.state.position.inMilliseconds >= player.state.duration.inMilliseconds * 0.95,
          );
    unawaited(write.catchError((Object _) {}));
  }

  static String _describe(String raw) {
    final lower = raw.toLowerCase();
    return switch (lower) {
      _ when lower.contains('403') || lower.contains('forbidden') =>
        'Zugriff verweigert (403). Zu viele Verbindungen oder Abo abgelaufen?',
      _ when lower.contains('404') || lower.contains('not found') =>
        'Sender nicht gefunden (404). Er ist vermutlich offline.',
      _ when lower.contains('failed to open') || lower.contains('loading failed') =>
        'Der Stream ist offline oder nicht erreichbar.',
      _ => raw,
    };
  }
}

final playerControllerProvider = NotifierProvider<PlayerController, PlaybackState>(PlayerController.new);
