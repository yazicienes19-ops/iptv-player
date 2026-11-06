import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/channel.dart';
import '../../models/content_type.dart';
import '../../player/fullscreen_player_page.dart';
import '../../player/player_controller.dart';
import '../../providers/app_providers.dart';
import '../../services/download_manager.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import '../widgets/media_image.dart';
import '../widgets/tv_focus.dart';

enum _Filter {
  all('Alle'),
  vod('Filme & Folgen'),
  recordings('Aufnahmen');

  const _Filter(this.label);
  final String label;
}

/// „12,3 MB“, „1,4 GB“
String formatBytes(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(0)} MB';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} GB';
}

/// Downloads und Aufnahmen: Fortschritt, Pause, Weiterladen, Abspielen, Löschen.
class DownloadsView extends ConsumerStatefulWidget {
  const DownloadsView({super.key, this.compact = false});

  final bool compact;

  @override
  ConsumerState<DownloadsView> createState() => _DownloadsViewState();
}

class _DownloadsViewState extends ConsumerState<DownloadsView> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(downloadsProvider).reversed.toList();
    final visible = [
      for (final i in items)
        if (_filter == _Filter.all || (_filter == _Filter.vod) == (i.kind == DownloadKind.vod)) i,
    ];
    final hPad = widget.compact ? 16.0 : 40.0;
    final used = items.where((i) => i.isDone || i.isActive).fold<int>(0, (sum, i) => sum + i.received);
    final dir = ref.read(downloadsProvider.notifier).directoryPath;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hPad, widget.compact ? 8 : 24, hPad, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!widget.compact)
                  Text(
                    'Downloads',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                const SizedBox(height: 4),
                Text(
                  items.isEmpty
                      ? 'Filme und Folgen lädst du über den Pfeil auf der Detailseite herunter. Live-Sender nimmst du im Player mit dem roten Punkt auf.'
                      : 'Belegt ${formatBytes(used)}. Downloads laufen nacheinander, weil die meisten Anbieter nur eine Verbindung erlauben. Währenddessen kann das Abspielen anderer Titel scheitern.',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final f in _Filter.values) ...[
                              SizedBox(
                                height: 36,
                                child: GlassPill(
                                  label: f.label,
                                  selected: f == _filter,
                                  onTap: () => setState(() => _filter = f),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (dir != null && !kIsWeb && Platform.isMacOS)
                      TextButton.icon(
                        onPressed: () => launchUrl(Uri.directory(dir)),
                        icon: const Icon(Icons.folder_open_rounded, size: 18),
                        label: const Text('Im Finder zeigen'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (visible.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _filter == _Filter.recordings ? Icons.fiber_manual_record_outlined : Icons.download_rounded,
                      size: 48,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _filter == _Filter.recordings ? 'Noch keine Aufnahmen.' : 'Noch nichts heruntergeladen.',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 40),
            sliver: SliverList.separated(
              itemCount: visible.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _DownloadTile(item: visible[i], compact: widget.compact),
            ),
          ),
      ],
    );
  }
}

class _DownloadTile extends ConsumerStatefulWidget {
  const _DownloadTile({required this.item, required this.compact});

  final DownloadItem item;
  final bool compact;

  @override
  ConsumerState<_DownloadTile> createState() => _DownloadTileState();
}

class _DownloadTileState extends ConsumerState<_DownloadTile> {
  bool _focused = false;

  void _play() {
    final item = widget.item;
    final notifier = ref.read(downloadsProvider.notifier);
    final activePlaylist = ref.read(activePlaylistProvider)?.id;
    // Downloads der aktiven Playlist laufen über den Originaltitel: dann stimmt „Fortsetzen“.
    final Channel channel;
    if (item.kind == DownloadKind.vod && item.playlistId == activePlaylist) {
      channel = item.channel;
    } else {
      final path = notifier.pathOf(item);
      if (path == null) return;
      channel = Channel(id: item.id, name: item.title, streamUrl: path, type: ContentType.movie, logo: item.poster);
    }
    ref.read(playerControllerProvider.notifier).play(channel, queue: [channel]);
    Navigator.of(context).push(FullscreenPlayerPage.route());
  }

  Future<void> _delete() async {
    final item = widget.item;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.kind == DownloadKind.recording ? 'Aufnahme löschen?' : 'Download löschen?'),
        content: Text('„${item.title}“ wird von diesem Gerät entfernt.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok == true) await ref.read(downloadsProvider.notifier).remove(item.id);
  }

  String _status(DownloadItem item) {
    final size = item.total == null
        ? formatBytes(item.received)
        : '${formatBytes(item.received)} von ${formatBytes(item.total!)}';
    final percent = item.fraction == null ? '' : ' · ${(item.fraction! * 100).round()} %';
    if (item.kind == DownloadKind.recording) {
      if (item.isActive) return 'Aufnahme läuft · ${formatBytes(item.received)}';
      final length = item.recordedFor;
      final minutes = length == null ? '' : ' · ${length.inMinutes} Min.';
      return 'Aufnahme$minutes · ${formatBytes(item.received)}${item.error == null ? '' : ' · ${item.error}'}';
    }
    return switch (item.status) {
      DownloadStatus.queued => item.received == 0 ? 'Wartet, bis der laufende Download fertig ist' : 'Wartet · $size',
      DownloadStatus.downloading =>
        'Wird geladen · $size$percent${(item.segments ?? 1) > 1 ? ' · ${item.segments} Verbindungen' : ''}',
      DownloadStatus.paused => 'Pausiert · $size$percent',
      DownloadStatus.failed => item.error ?? 'Fehlgeschlagen',
      DownloadStatus.done => 'Heruntergeladen · ${formatBytes(item.received)}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final notifier = ref.read(downloadsProvider.notifier);
    final isRecording = item.kind == DownloadKind.recording;
    final canPlay = item.isDone;
    final thumbWidth = isRecording ? (widget.compact ? 96.0 : 128.0) : (widget.compact ? 52.0 : 64.0);
    final thumb = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: thumbWidth,
        child: AspectRatio(
          aspectRatio: isRecording ? 16 / 9 : 2 / 3,
          child: ColoredBox(
            color: isRecording ? AppColors.logoSurface : AppColors.surfaceHigh,
            child: MediaImage(
              url: item.poster,
              fit: isRecording ? BoxFit.contain : BoxFit.cover,
              padding: isRecording ? const EdgeInsets.all(10) : EdgeInsets.zero,
              placeholder: Icon(
                isRecording ? Icons.live_tv_rounded : Icons.movie_outlined,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );

    final actions = <Widget>[
      if (canPlay)
        IconButton.filledTonal(tooltip: 'Abspielen', onPressed: _play, icon: const Icon(Icons.play_arrow_rounded)),
      if (!isRecording && (item.status == DownloadStatus.downloading || item.status == DownloadStatus.queued))
        IconButton(
          tooltip: 'Pausieren',
          onPressed: () => notifier.pause(item.id),
          icon: const Icon(Icons.pause_rounded),
        ),
      if (!isRecording && (item.status == DownloadStatus.paused || item.status == DownloadStatus.failed))
        IconButton(
          tooltip: item.status == DownloadStatus.failed ? 'Erneut versuchen' : 'Weiterladen',
          onPressed: () => notifier.resume(item.id),
          icon: Icon(item.status == DownloadStatus.failed ? Icons.refresh_rounded : Icons.play_for_work_rounded),
        ),
      if (!(isRecording && item.isActive))
        IconButton(tooltip: 'Löschen', onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded)),
    ];

    return TvFocus(
      onActivate: canPlay ? _play : null,
      onFocusChange: (v) => setState(() => _focused = v),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _focused ? Colors.white : Colors.white.withValues(alpha: 0.06),
            width: _focused ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: canPlay ? _play : null,
          child: Row(
            children: [
              thumb,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    if (item.subtitle != null)
                      Text(
                        item.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (isRecording && item.isActive) ...[
                          const Icon(Icons.fiber_manual_record, size: 12, color: AppColors.live),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            _status(item),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: item.status == DownloadStatus.failed ? AppColors.accent : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!isRecording && !item.isDone && item.status != DownloadStatus.failed) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: item.fraction ?? (item.isActive ? null : 0),
                          minHeight: 4,
                          backgroundColor: Colors.white12,
                          color: item.isActive ? AppColors.accent : Colors.white38,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}
