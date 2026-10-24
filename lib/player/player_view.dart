import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/channel_name.dart';
import '../models/content_type.dart';
import '../providers/app_providers.dart';
import '../ui/theme.dart';
import '../ui/widgets/channel_views.dart';
import '../ui/widgets/tv_focus.dart';
import 'player_controller.dart';

/// Shared by the player and its route so Back unlocks before leaving playback.
class PlayerLockController extends ValueNotifier<bool> {
  PlayerLockController() : super(false);

  bool get isLocked => value;
  void lock() => value = true;
  void unlock() => value = false;

  void handleBack(VoidCallback? onExit) {
    if (isLocked) {
      unlock();
    } else {
      onExit?.call();
    }
  }
}

Duration playbackSeekTarget(Duration position, Duration duration, int seconds) {
  final target = position + Duration(seconds: seconds);
  if (target < Duration.zero) return Duration.zero;
  if (duration > Duration.zero && target > duration) return duration;
  return target;
}

/// Video mit eigener Overlay-Steuerung. Wird eingebettet und im Vollbild genutzt.
class PlayerView extends ConsumerStatefulWidget {
  const PlayerView({super.key, this.isFullscreen = false, this.onToggleFullscreen, this.lockController});

  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;
  final PlayerLockController? lockController;

  @override
  ConsumerState<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends ConsumerState<PlayerView> {
  bool _controlsVisible = true;
  bool _switcherOpen = false;
  Timer? _hideTimer;
  StreamSubscription<bool>? _playingSubscription;
  late bool _isPlaying;
  final _focusNode = FocusNode(debugLabel: 'PlayerView');
  final _unlockFocusNode = FocusNode(debugLabel: 'PlayerUnlock');
  late PlayerLockController _lock;
  bool _focusVisible = false;

  @override
  void initState() {
    super.initState();
    _lock = widget.lockController ?? PlayerLockController();
    _lock.addListener(_lockChanged);
    _focusNode.addListener(_updateFocusRing);
    final player = ref.read(playerControllerProvider.notifier).player;
    _isPlaying = player.state.playing;
    _playingSubscription = player.stream.playing.listen((playing) {
      if (!mounted) return;
      _isPlaying = playing;
      if (playing) {
        _scheduleHide();
      } else {
        // Pausing via media keys or an external control must reveal the
        // controls as well as cancelling an already running hide timer.
        _showControls();
      }
    });
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _playingSubscription?.cancel();
    _focusNode.removeListener(_updateFocusRing);
    _focusNode.dispose();
    _unlockFocusNode.dispose();
    _lock.removeListener(_lockChanged);
    if (widget.lockController == null) _lock.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(PlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lockController == widget.lockController) return;
    _lock.removeListener(_lockChanged);
    if (oldWidget.lockController == null) _lock.dispose();
    _lock = widget.lockController ?? PlayerLockController();
    _lock.addListener(_lockChanged);
  }

  void _lockChanged() {
    setState(() {
      _controlsVisible = true;
      _switcherOpen = false;
    });
    if (_lock.isLocked) {
      _hideTimer?.cancel();
      _unlockFocusNode.requestFocus();
    } else {
      _focusNode.requestFocus();
      _scheduleHide();
    }
  }

  /// Rahmen nur bei Fernbedienung/Tastatur, nicht nach Mausklicks.
  void _updateFocusRing() {
    final visible = _focusNode.hasFocus && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    if (visible != _focusVisible) setState(() => _focusVisible = visible);
    if (visible) _showControls();
  }

  void _showControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (_lock.isLocked || !_isPlaying) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _switcherOpen || !_isPlaying || _lock.isLocked) return;
      // Keep a remote-focused control visible; otherwise it would disappear
      // while the user is deciding which action to take.
      if (_focusNode.hasFocus &&
          !_focusNode.hasPrimaryFocus &&
          FocusManager.instance.highlightMode == FocusHighlightMode.traditional) {
        return;
      }
      setState(() => _controlsVisible = false);
    });
  }

  void _toggleSwitcher() {
    setState(() => _switcherOpen = !_switcherOpen);
    _showControls();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(playerControllerProvider.notifier);
    final state = ref.watch(playerControllerProvider);

    final isOnDemand = state.channel != null && state.channel!.type != ContentType.live;
    void interact(VoidCallback action) {
      if (_lock.isLocked) return;
      action();
      _showControls();
    }

    void seek(int seconds) {
      interact(
        () => controller.player.seek(
          playbackSeekTarget(controller.player.state.position, controller.player.state.duration, seconds),
        ),
      );
    }

    void select() {
      if (_lock.isLocked) return;
      if (!_focusNode.hasPrimaryFocus) {
        final focusedContext = FocusManager.instance.primaryFocus?.context;
        if (focusedContext != null) Actions.maybeInvoke(focusedContext, const ActivateIntent());
        _showControls();
        return;
      }
      // Eingebettet öffnet OK das Vollbild, im Vollbild pausiert es.
      if (!widget.isFullscreen && widget.onToggleFullscreen != null) {
        widget.onToggleFullscreen!();
      } else {
        controller.player.playOrPause();
        _showControls();
      }
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () {
          if (!_focusNode.hasPrimaryFocus) {
            select();
          } else {
            interact(controller.player.playOrPause);
          }
        },
        const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () => interact(controller.player.playOrPause),
        const SingleActivator(LogicalKeyboardKey.select): select,
        const SingleActivator(LogicalKeyboardKey.enter): select,
        const SingleActivator(LogicalKeyboardKey.channelUp): () => interact(controller.previous),
        const SingleActivator(LogicalKeyboardKey.channelDown): () => interact(controller.next),
        // Links/rechts spulen nur bei Filmen; bei Live führen sie aus dem Player heraus.
        if (isOnDemand) ...{
          const SingleActivator(LogicalKeyboardKey.mediaRewind): () => seek(-10),
          const SingleActivator(LogicalKeyboardKey.mediaFastForward): () => seek(10),
        },
        const SingleActivator(LogicalKeyboardKey.keyF): () => interact(() => widget.onToggleFullscreen?.call()),
        const SingleActivator(LogicalKeyboardKey.escape): () => _lock.handleBack(widget.onToggleFullscreen),
        const SingleActivator(LogicalKeyboardKey.goBack): () => _lock.handleBack(widget.onToggleFullscreen),
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: widget.isFullscreen,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (_lock.isLocked) {
            if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
              _lock.unlock();
              return KeyEventResult.handled;
            }
            if (_unlockFocusNode.hasFocus &&
                (key == LogicalKeyboardKey.enter ||
                    key == LogicalKeyboardKey.select ||
                    key == LogicalKeyboardKey.space)) {
              _lock.unlock();
              return KeyEventResult.handled;
            }
            // Remaining remote shortcuts must not reach playback or the
            // surrounding UI while the screen is locked.
            if (key != LogicalKeyboardKey.tab) return KeyEventResult.handled;
          }
          _showControls();
          if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
          if (isOnDemand && (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight)) {
            seek(key == LogicalKeyboardKey.arrowLeft ? -10 : 10);
            return KeyEventResult.handled;
          }
          // Arrow keys otherwise use Flutter's directional focus traversal.
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          key: const ValueKey('playback-surface'),
          onHover: (_) => _showControls(),
          cursor: _controlsVisible ? MouseCursor.defer : SystemMouseCursors.none,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_lock.isLocked) return;
              _focusNode.requestFocus();
              if (_controlsVisible && _isPlaying) {
                setState(() => _controlsVisible = false);
              } else {
                _showControls();
              }
            },
            onDoubleTap: () => interact(() => widget.onToggleFullscreen?.call()),
            child: FocusRing(
              visible: _focusVisible && !widget.isFullscreen,
              radius: 0,
              child: ColoredBox(
                color: Colors.black,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (state.channel != null)
                      Video(controller: controller.videoController, controls: NoVideoControls, fit: state.fit.boxFit),
                    IgnorePointer(
                      ignoring: _lock.isLocked,
                      child: ExcludeFocus(
                        excluding: _lock.isLocked,
                        child: _StatusLayer(state: state),
                      ),
                    ),
                    if (state.channel != null && !_lock.isLocked)
                      AnimatedOpacity(
                        opacity: _controlsVisible ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: IgnorePointer(
                          ignoring: !_controlsVisible,
                          child: ExcludeFocus(
                            excluding: !_controlsVisible,
                            child: _ControlsLayer(
                              state: state,
                              isFullscreen: widget.isFullscreen,
                              onToggleFullscreen: widget.onToggleFullscreen,
                              onToggleSwitcher: _toggleSwitcher,
                              onInteraction: _showControls,
                              onLock: _lock.lock,
                            ),
                          ),
                        ),
                      ),
                    if (_lock.isLocked)
                      Positioned(
                        left: 24,
                        right: 24,
                        bottom: 28,
                        child: Center(
                          child: FilledButton.icon(
                            focusNode: _unlockFocusNode,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xDD242424),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _lock.unlock,
                            icon: const Icon(Icons.lock_outline_rounded),
                            label: const Text('Bildschirm entsperren'),
                          ),
                        ),
                      ),
                    if (!_lock.isLocked)
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        top: 0,
                        bottom: 0,
                        right: _switcherOpen ? 0 : -320,
                        width: 300,
                        child: ExcludeFocus(
                          excluding: !_switcherOpen,
                          child: _ChannelSwitcher(onClose: _toggleSwitcher),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusLayer extends ConsumerWidget {
  const _StatusLayer({required this.state});

  final PlaybackState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.channel == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.live_tv_rounded, size: 48, color: AppColors.textSecondary),
            SizedBox(height: 12),
            Text('Wähle einen Sender', style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }
    if (state.hasError) {
      final controller = ref.read(playerControllerProvider.notifier);
      return Container(
        color: Colors.black87,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.signal_wifi_connected_no_internet_4_rounded, size: 40, color: AppColors.live),
            const SizedBox(height: 12),
            Text(state.error!, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            if (state.retryCountdown != null)
              Text(
                'Neuer Versuch ${state.retryAttempt}/${PlayerController.maxRetries} in ${state.retryCountdown} s',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: controller.retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Jetzt erneut versuchen'),
                ),
                FilterChip(
                  label: const Text('Automatisch wiederholen'),
                  selected: state.autoRetry,
                  onSelected: (_) => controller.toggleAutoRetry(),
                ),
              ],
            ),
          ],
        ),
      );
    }
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return StreamBuilder<bool>(
      stream: ref.read(playerControllerProvider.notifier).player.stream.buffering,
      builder: (context, snapshot) => snapshot.data == true
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : const SizedBox.shrink(),
    );
  }
}

class _ControlsLayer extends ConsumerWidget {
  const _ControlsLayer({
    required this.state,
    required this.isFullscreen,
    required this.onToggleFullscreen,
    required this.onToggleSwitcher,
    required this.onInteraction,
    required this.onLock,
  });

  final PlaybackState state;
  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;
  final VoidCallback onToggleSwitcher;
  final VoidCallback onInteraction;
  final VoidCallback onLock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playerControllerProvider.notifier);
    final player = controller.player;
    final channel = state.channel!;
    final isFavorite = ref.watch(favoritesProvider.select((f) => f.contains(channel)));
    void interact(VoidCallback action) {
      action();
      onInteraction();
    }

    return StreamBuilder<bool>(
      stream: player.stream.playing,
      initialData: player.state.playing,
      builder: (context, snapshot) => PlaybackControls(
        title: channel.display.title,
        isLive: channel.type == ContentType.live,
        isPlaying: snapshot.data == true,
        isFullscreen: isFullscreen,
        isFavorite: isFavorite,
        showTransport: !state.hasError && !state.isLoading,
        onBack: isFullscreen ? onToggleFullscreen : null,
        onPlayPause: () => interact(player.playOrPause),
        onSeek: (seconds) =>
            interact(() => player.seek(playbackSeekTarget(player.state.position, player.state.duration, seconds))),
        onLock: onLock,
        onFavorite: () => interact(() => ref.read(favoritesProvider.notifier).toggle(channel)),
        onToggleFullscreen: onToggleFullscreen,
        timeline: _SeekBar(player: player, onInteraction: onInteraction),
        volume: _VolumeControl(player: player, showSlider: true, onInteraction: onInteraction),
        tracks: _TrackMenu(player: player, onInteraction: onInteraction),
        speed: channel.type != ContentType.live ? _SpeedMenu(player: player, onInteraction: onInteraction) : null,
        fitLabel: state.fit.label,
        onCycleFit: () => interact(controller.cycleFit),
        onNext: state.queue.length > 1 ? () => interact(controller.next) : null,
        onQueue: state.queue.length > 1 ? onToggleSwitcher : null,
      ),
    );
  }
}

/// Presentation is separate from the native decoder, keeping the controls
/// keyboard-accessible and testable at both TV and compact window sizes.
class PlaybackControls extends StatelessWidget {
  const PlaybackControls({
    super.key,
    required this.title,
    required this.isLive,
    required this.isPlaying,
    required this.isFullscreen,
    required this.isFavorite,
    required this.onPlayPause,
    required this.onSeek,
    required this.onLock,
    required this.onFavorite,
    required this.timeline,
    required this.volume,
    required this.tracks,
    required this.fitLabel,
    required this.onCycleFit,
    this.onBack,
    this.onToggleFullscreen,
    this.onNext,
    this.onQueue,
    this.speed,
    this.showTransport = true,
  });

  final String title;
  final bool isLive;
  final bool isPlaying;
  final bool isFullscreen;
  final bool isFavorite;
  final VoidCallback onPlayPause;
  final ValueChanged<int> onSeek;
  final VoidCallback onLock;
  final VoidCallback onFavorite;
  final VoidCallback? onBack;
  final VoidCallback? onToggleFullscreen;
  final VoidCallback? onNext;
  final VoidCallback? onQueue;
  final Widget timeline;
  final Widget volume;
  final Widget tracks;
  final Widget? speed;
  final bool showTransport;
  final String fitLabel;
  final VoidCallback onCycleFit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final short = constraints.maxHeight < 320;
        final wide = constraints.maxWidth >= 720;
        final inset = wide ? 32.0 : 12.0;
        Widget transport({bool small = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isLive)
              IconButton(
                tooltip: '10 Sekunden zurück',
                iconSize: small ? 26 : 36,
                padding: EdgeInsets.all(small ? 8 : 16),
                onPressed: () => onSeek(-10),
                icon: const Icon(Icons.replay_10_rounded),
              ),
            IconButton.filled(
              tooltip: isPlaying ? 'Pause' : 'Abspielen',
              iconSize: small ? 32 : 52,
              padding: EdgeInsets.all(small ? 8 : 18),
              style: IconButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
              onPressed: onPlayPause,
              icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
            ),
            if (!isLive)
              IconButton(
                tooltip: '10 Sekunden vor',
                iconSize: small ? 26 : 36,
                padding: EdgeInsets.all(small ? 8 : 16),
                onPressed: () => onSeek(10),
                icon: const Icon(Icons.forward_10_rounded),
              ),
          ],
        );

        final tools = [
          volume,
          tracks,
          ?speed,
          IconButton(tooltip: 'Bildschirm sperren', icon: const Icon(Icons.lock_open_rounded), onPressed: onLock),
          IconButton(
            tooltip: 'Bildformat: $fitLabel',
            icon: const Icon(Icons.aspect_ratio_rounded),
            onPressed: onCycleFit,
          ),
          if (onQueue != null)
            IconButton(
              tooltip: isLive ? 'Senderliste' : 'Folgen / Wiedergabeliste',
              icon: const Icon(Icons.playlist_play_rounded),
              onPressed: onQueue,
            ),
          if (onNext != null)
            IconButton(
              tooltip: isLive ? 'Nächster Sender' : 'Nächster Titel',
              icon: const Icon(Icons.skip_next_rounded),
              onPressed: onNext,
            ),
          if (onToggleFullscreen != null)
            IconButton(
              tooltip: isFullscreen ? 'Vollbild beenden' : 'Vollbild',
              icon: Icon(isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded),
              onPressed: onToggleFullscreen,
            ),
        ];

        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xCC000000), Color(0x22000000), Color(0x22000000), Color(0xEE000000)],
              stops: [0, 0.28, 0.55, 1],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                Positioned(
                  left: inset,
                  right: inset,
                  top: short ? 4 : 18,
                  child: Row(
                    children: [
                      if (onBack != null) ...[
                        IconButton(tooltip: 'Zurück', icon: const Icon(Icons.arrow_back_rounded), onPressed: onBack),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!short)
                              Text(
                                isLive ? 'LIVE TV' : 'DU SCHAUST',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                  color: Colors.white60,
                                ),
                              ),
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: wide ? 22 : 16, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: isFavorite ? 'Aus meiner Liste entfernen' : 'Zu meiner Liste',
                        icon: Icon(isFavorite ? Icons.check_rounded : Icons.add_rounded),
                        onPressed: onFavorite,
                      ),
                    ],
                  ),
                ),
                if (!short && showTransport) Align(alignment: const Alignment(0, -0.12), child: transport()),
                Positioned(
                  left: inset,
                  right: inset,
                  bottom: short ? 0 : 14,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isLive) timeline,
                      if (wide)
                        Row(
                          children: [
                            if (short && showTransport) transport(small: true),
                            if (isLive)
                              const Padding(
                                padding: EdgeInsets.only(right: 16),
                                child: Text(
                                  '● LIVE',
                                  style: TextStyle(color: AppColors.live, fontWeight: FontWeight.w700),
                                ),
                              ),
                            const Spacer(),
                            ...tools,
                          ],
                        )
                      else ...[
                        if (short && showTransport) transport(small: true),
                        // A narrow embedded player must keep every control reachable.
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(mainAxisSize: MainAxisSize.min, children: tools),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Fortschrittsleiste mit Zeiten; nur für Filme und Folgen.
class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.player, required this.onInteraction});

  final Player player;
  final VoidCallback onInteraction;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  /// Während des Ziehens folgt der Regler dem Finger statt der Wiedergabe.
  double? _dragValue;

  static String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      initialData: player.state.position,
      builder: (context, snapshot) {
        final duration = player.state.duration;
        if (duration <= Duration.zero) return const SizedBox.shrink();
        final total = duration.inMilliseconds.toDouble();
        final position = (snapshot.data ?? Duration.zero).inMilliseconds.toDouble().clamp(0.0, total);
        final value = (_dragValue ?? position).clamp(0.0, total);
        const timeStyle = TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(_format(Duration(milliseconds: value.round())), style: timeStyle),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context)
                      .copyWith(activeTrackColor: AppColors.accent, thumbColor: AppColors.accent),
                  child: Slider(
                    value: value,
                    max: total,
                    onChanged: (v) {
                      setState(() => _dragValue = v);
                      widget.onInteraction();
                    },
                    onChangeEnd: (v) async {
                      await player.seek(Duration(milliseconds: v.round()));
                      if (mounted) setState(() => _dragValue = null);
                    },
                  ),
                ),
              ),
              Text('-${_format(duration - Duration(milliseconds: value.round()))}', style: timeStyle),
            ],
          ),
        );
      },
    );
  }
}

class _SpeedMenu extends StatelessWidget {
  const _SpeedMenu({required this.player, required this.onInteraction});

  final Player player;
  final VoidCallback onInteraction;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      tooltip: 'Wiedergabegeschwindigkeit',
      icon: const Icon(Icons.speed_rounded),
      onOpened: onInteraction,
      onCanceled: onInteraction,
      onSelected: (rate) {
        player.setRate(rate);
        onInteraction();
      },
      itemBuilder: (_) => [
        for (final rate in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
          CheckedPopupMenuItem(
            value: rate,
            checked: player.state.rate == rate,
            child: Text(rate == 1 ? 'Normal' : '${rate.toString().replaceAll('.', ',')}×'),
          ),
      ],
    );
  }
}

class _VolumeControl extends StatelessWidget {
  const _VolumeControl({required this.player, required this.showSlider, required this.onInteraction});

  final Player player;
  final bool showSlider;
  final VoidCallback onInteraction;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: player.stream.volume,
      initialData: player.state.volume,
      builder: (context, snapshot) {
        final volume = snapshot.data ?? 100;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: volume == 0 ? 'Ton an' : 'Stumm',
              icon: Icon(
                volume == 0
                    ? Icons.volume_off_rounded
                    : volume < 50
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded,
              ),
              onPressed: () {
                player.setVolume(volume == 0 ? 100 : 0);
                onInteraction();
              },
            ),
            if (showSlider)
              SizedBox(
                width: 100,
                child: Slider(
                  value: volume.clamp(0, 100),
                  max: 100,
                  onChanged: (v) {
                    player.setVolume(v);
                    onInteraction();
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Auswahl von Tonspur und Untertitel aus den Spuren, die libmpv meldet.
class _TrackMenu extends StatelessWidget {
  const _TrackMenu({required this.player, required this.onInteraction});

  final Player player;

  final VoidCallback onInteraction;

  static String _label(String id, String? title, String? language) {
    if (id == 'auto') return 'Automatisch';
    if (id == 'no') return 'Aus';
    final parts = [?title, if (language != null) language.toUpperCase()];
    return parts.isEmpty ? 'Spur $id' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Object>(
      tooltip: 'Ton & Untertitel',
      icon: const Icon(Icons.subtitles_outlined),
      onOpened: onInteraction,
      onCanceled: onInteraction,
      onSelected: (track) {
        onInteraction();
        if (track is AudioTrack) player.setAudioTrack(track);
        if (track is SubtitleTrack) player.setSubtitleTrack(track);
      },
      itemBuilder: (context) {
        final tracks = player.state.tracks;
        final current = player.state.track;
        final audio = tracks.audio.where((t) => t.id != 'no').toList();
        final subtitles = tracks.subtitle;
        return [
          const PopupMenuItem(enabled: false, height: 32, child: Text('TONSPUR', style: TextStyle(fontSize: 11))),
          for (final t in audio)
            CheckedPopupMenuItem(value: t, checked: t == current.audio, child: Text(_label(t.id, t.title, t.language))),
          const PopupMenuDivider(),
          const PopupMenuItem(enabled: false, height: 32, child: Text('UNTERTITEL', style: TextStyle(fontSize: 11))),
          for (final t in subtitles)
            CheckedPopupMenuItem(
              value: t,
              checked: t == current.subtitle,
              child: Text(_label(t.id, t.title, t.language)),
            ),
        ];
      },
    );
  }
}

/// Seitenleiste zum schnellen Senderwechsel, ohne den Player zu verlassen.
class _ChannelSwitcher extends ConsumerWidget {
  const _ChannelSwitcher({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(playerControllerProvider.select((s) => s.queue));
    return Material(
      color: AppColors.surface.withValues(alpha: 0.96),
      child: SafeArea(
        left: false,
        child: Column(
          children: [
            ListTile(
              title: Text(
                queue.isNotEmpty && queue.first.type != ContentType.live ? 'Wiedergabeliste' : 'Sender',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              trailing: IconButton(icon: const Icon(Icons.close), onPressed: onClose),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: queue.length,
                itemExtent: 52,
                itemBuilder: (context, i) => ChannelTile(channel: queue[i], queue: queue, dense: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
