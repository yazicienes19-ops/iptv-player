import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import 'hls_resolver.dart';

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

  final _hlsResolver = HlsResolver();

  late Player player;
  late VideoController videoController;

  final _subscriptions = <StreamSubscription<Object?>>[];
  Timer? _watchdog;
  Timer? _retryTimer;

  /// Erhöht sich bei jedem Öffnen; verhindert, dass Ereignisse eines alten
  /// Streams den Zustand des neuen überschreiben.
  int _session = 0;

  /// Erst nach `open()` des aktuellen Streams zählen Bild-/Positionsereignisse;
  /// vorher stammen sie noch vom vorherigen Stream.
  bool _acceptStartEvents = false;
  DateTime? _openedAt;

  @override
  PlaybackState build() {
    player = Player(
      configuration: const PlayerConfiguration(
        title: 'IPTV Player',
        bufferSize: 64 * 1024 * 1024,
      ),
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
      }),
      player.stream.completed.listen((done) {
        // Ein Live-Stream „endet“ nur, wenn die Verbindung abreißt.
        if (done && _acceptStartEvents && state.channel?.type == ContentType.live) {
          _onError('Der Stream wurde unterbrochen.');
        }
      }),
    ]);

    ref.onDispose(() {
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
    state = state.copyWith(
      channel: channel,
      queue: queue,
      retryAttempt: 0,
    );
    await _open();
  }

  Future<void> retry() async {
    if (state.channel == null) return;
    state = state.copyWith(retryAttempt: 0);
    await _open();
  }

  Future<void> stop() async {
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
      final stream = await _hlsResolver.resolve(channel.streamUrl);
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
        await (player.platform as NativePlayer).command([
          'audio-add',
          audio.url,
          i == 0 ? 'select' : 'auto',
          audio.name,
          ?audio.language,
        ]);
      }
    } catch (e) {
      if (session == _session) _onError('$e');
    }
  }

  void _markStarted() {
    if (!_acceptStartEvents || (!state.isLoading && !state.hasError)) return;
    _watchdog?.cancel();
    state = state.copyWith(isLoading: false, error: () => null, retryAttempt: 0, retryCountdown: () => null);
  }

  void _onError(String message) {
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

  static String _describe(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('403') || lower.contains('forbidden')) return 'Zugriff verweigert (403). Zu viele Verbindungen oder Abo abgelaufen?';
    if (lower.contains('404') || lower.contains('not found')) return 'Sender nicht gefunden (404). Er ist vermutlich offline.';
    if (lower.contains('failed to open') || lower.contains('loading failed')) return 'Der Stream ist offline oder nicht erreichbar.';
    return raw;
  }
}

final playerControllerProvider = NotifierProvider<PlayerController, PlaybackState>(PlayerController.new);
