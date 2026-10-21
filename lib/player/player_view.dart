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
import 'player_controller.dart';

/// Video mit eigener Overlay-Steuerung. Wird eingebettet und im Vollbild genutzt.
class PlayerView extends ConsumerStatefulWidget {
  const PlayerView({super.key, this.isFullscreen = false, this.onToggleFullscreen});

  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;

  @override
  ConsumerState<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends ConsumerState<PlayerView> {
  bool _controlsVisible = true;
  bool _switcherOpen = false;
  Timer? _hideTimer;
  final _focusNode = FocusNode(debugLabel: 'PlayerView');

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _showControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_switcherOpen) setState(() => _controlsVisible = false);
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

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): controller.player.playOrPause,
        const SingleActivator(LogicalKeyboardKey.arrowUp): controller.previous,
        const SingleActivator(LogicalKeyboardKey.arrowDown): controller.next,
        const SingleActivator(LogicalKeyboardKey.keyF): () => widget.onToggleFullscreen?.call(),
        if (widget.isFullscreen)
          const SingleActivator(LogicalKeyboardKey.escape): () => widget.onToggleFullscreen?.call(),
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: widget.isFullscreen,
        child: MouseRegion(
          onHover: (_) => _showControls(),
          cursor: _controlsVisible ? MouseCursor.defer : SystemMouseCursors.none,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _focusNode.requestFocus();
              _controlsVisible ? setState(() => _controlsVisible = false) : _showControls();
            },
            onDoubleTap: widget.onToggleFullscreen,
            child: ColoredBox(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (state.channel != null)
                    Video(controller: controller.videoController, controls: NoVideoControls, fit: state.fit.boxFit),
                  _StatusLayer(state: state),
                  if (state.channel != null)
                    AnimatedOpacity(
                      opacity: _controlsVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: !_controlsVisible,
                        child: _ControlsLayer(
                          state: state,
                          isFullscreen: widget.isFullscreen,
                          onToggleFullscreen: widget.onToggleFullscreen,
                          onToggleSwitcher: _toggleSwitcher,
                          onInteraction: _showControls,
                        ),
                      ),
                    ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    top: 0,
                    bottom: 0,
                    right: _switcherOpen ? 0 : -320,
                    width: 300,
                    child: _ChannelSwitcher(onClose: _toggleSwitcher),
                  ),
                ],
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
  });

  final PlaybackState state;
  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;
  final VoidCallback onToggleSwitcher;
  final VoidCallback onInteraction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playerControllerProvider.notifier);
    final player = controller.player;
    final channel = state.channel!;
    final isFavorite = ref.watch(favoritesProvider.select((f) => f.contains(channel)));
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 500 && !isFullscreen;

        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xAA000000), Colors.transparent, Colors.transparent, Color(0xCC000000)],
              stops: [0, 0.25, 0.6, 1],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: Row(
                    children: [
                      if (isFullscreen)
                        IconButton(tooltip: 'Schließen', icon: const Icon(Icons.close), onPressed: onToggleFullscreen),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            channel.display.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: isFavorite ? 'Aus Favoriten entfernen' : 'Zu Favoriten',
                        icon: Icon(isFavorite ? Icons.star_rounded : Icons.star_outline_rounded),
                        color: isFavorite ? Colors.amber : Colors.white,
                        onPressed: () => ref.read(favoritesProvider.notifier).toggle(channel),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (channel.type != ContentType.live) _SeekBar(player: player, onInteraction: onInteraction),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                  child: Row(
                    children: [
                      if (state.queue.length > 1 && !compact)
                        IconButton(
                          tooltip: 'Vorheriger',
                          icon: const Icon(Icons.skip_previous_rounded),
                          onPressed: controller.previous,
                        ),
                      StreamBuilder<bool>(
                        stream: player.stream.playing,
                        initialData: player.state.playing,
                        builder: (context, snapshot) => IconButton(
                          tooltip: snapshot.data == true ? 'Pause' : 'Abspielen',
                          iconSize: 32,
                          icon: Icon(snapshot.data == true ? Icons.pause_rounded : Icons.play_arrow_rounded),
                          onPressed: () {
                            player.playOrPause();
                            onInteraction();
                          },
                        ),
                      ),
                      if (state.queue.length > 1 && !compact)
                        IconButton(
                          tooltip: 'Nächster',
                          icon: const Icon(Icons.skip_next_rounded),
                          onPressed: controller.next,
                        ),
                      if (channel.type != ContentType.live) ...[
                        IconButton(
                          tooltip: '10 s zurück',
                          icon: const Icon(Icons.replay_10_rounded),
                          onPressed: () => player.seek(player.state.position - const Duration(seconds: 10)),
                        ),
                        IconButton(
                          tooltip: '10 s vor',
                          icon: const Icon(Icons.forward_10_rounded),
                          onPressed: () => player.seek(player.state.position + const Duration(seconds: 10)),
                        ),
                      ],
                      _VolumeControl(player: player, showSlider: !compact, onInteraction: onInteraction),
                      const Spacer(),
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: Colors.white),
                        onPressed: () {
                          controller.cycleFit();
                          onInteraction();
                        },
                        icon: const Icon(Icons.aspect_ratio_rounded, size: 20),
                        label: Text(state.fit.label),
                      ),
                      _TrackMenu(player: player),
                      if (state.queue.length > 1)
                        IconButton(
                          tooltip: 'Senderliste',
                          icon: const Icon(Icons.view_sidebar_rounded),
                          onPressed: onToggleSwitcher,
                        ),
                      if (onToggleFullscreen != null)
                        IconButton(
                          tooltip: isFullscreen ? 'Vollbild beenden' : 'Vollbild',
                          icon: Icon(isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded),
                          onPressed: onToggleFullscreen,
                        ),
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
        final value = _dragValue ?? position;
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
  const _TrackMenu({required this.player});

  final Player player;

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
      onSelected: (track) {
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
              title: const Text('Sender', style: TextStyle(fontWeight: FontWeight.w600)),
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
