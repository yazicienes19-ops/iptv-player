import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/channel_name.dart';
import '../ui/theme.dart';
import 'fullscreen_player_page.dart';
import 'player_controller.dart';

/// Fester Mini-Player über der Tab-Leiste (iPhone hochkant).
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  static const height = 64.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final channel = state.channel;
    if (channel == null) return const SizedBox.shrink();

    final status = state.hasError
        ? (state.retryCountdown != null ? 'Neuer Versuch in ${state.retryCountdown} s' : 'Stream nicht verfügbar')
        : state.isLoading
        ? 'Wird geladen …'
        : channel.type.label;

    return Material(
      color: AppColors.surfaceHigh,
      child: InkWell(
        onTap: () => Navigator.of(context).push(FullscreenPlayerPage.route()),
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 85,
                  height: 48,
                  child: Video(controller: controller.videoController, controls: NoVideoControls),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.display.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      status,
                      maxLines: 1,
                      style: TextStyle(fontSize: 12, color: state.hasError ? AppColors.live : AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (state.hasError)
                IconButton(icon: const Icon(Icons.refresh), onPressed: controller.retry)
              else
                StreamBuilder<bool>(
                  stream: controller.player.stream.playing,
                  initialData: controller.player.state.playing,
                  builder: (context, snapshot) => IconButton(
                    icon: Icon(snapshot.data == true ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    onPressed: controller.player.playOrPause,
                  ),
                ),
              IconButton(icon: const Icon(Icons.close), onPressed: controller.stop),
            ],
          ),
        ),
      ),
    );
  }
}
