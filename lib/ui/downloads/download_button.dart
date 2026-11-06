import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/channel.dart';
import '../../providers/app_providers.dart';
import '../../services/download_manager.dart';
import '../theme.dart';
import '../widgets/tv_focus.dart';

/// Runder Knopf: herunterladen, Fortschritt (antippen = Pause), weiterladen, fertig.
class DownloadButton extends ConsumerStatefulWidget {
  const DownloadButton({
    super.key,
    required this.channel,
    required this.title,
    this.subtitle,
    this.poster,
    this.size = 42,
  });

  final Channel channel;
  final String title;
  final String? subtitle;
  final String? poster;
  final double size;

  @override
  ConsumerState<DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends ConsumerState<DownloadButton> {
  bool _hovered = false;
  bool _focused = false;

  Future<void> _start() async {
    try {
      await ref
          .read(downloadsProvider.notifier)
          .download(widget.channel, title: widget.title, subtitle: widget.subtitle, poster: widget.poster);
    } catch (_) {
      if (!mounted) return;
      showDownloadListError(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !isDownloadable(widget.channel)) return const SizedBox.shrink();
    final item = ref.watch(downloadForProvider(widget.channel));
    final notifier = ref.read(downloadsProvider.notifier);
    final size = widget.size;
    final lit = _hovered || _focused;

    final (String tooltip, VoidCallback onTap, Widget icon) = switch (item?.status) {
      null => ('Herunterladen', _start, Icon(Icons.download_rounded, size: size * 0.5, color: Colors.white)),
      DownloadStatus.queued => (
        'Wartet auf den laufenden Download · antippen zum Pausieren',
        () => notifier.pause(item!.id),
        Icon(Icons.schedule_rounded, size: size * 0.46, color: Colors.white),
      ),
      DownloadStatus.downloading => (
        item!.fraction == null
            ? 'Wird geladen · antippen zum Pausieren'
            : 'Wird geladen: ${(item.fraction! * 100).round()} % · antippen zum Pausieren',
        () => notifier.pause(item.id),
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: size * 0.62,
              height: size * 0.62,
              child: CircularProgressIndicator(
                value: item.fraction,
                strokeWidth: 2.5,
                color: AppColors.accent,
                backgroundColor: Colors.white24,
              ),
            ),
            Icon(Icons.pause_rounded, size: size * 0.3, color: Colors.white),
          ],
        ),
      ),
      DownloadStatus.paused => (
        'Pausiert · antippen zum Weiterladen',
        () => notifier.resume(item!.id),
        Icon(Icons.play_for_work_rounded, size: size * 0.5, color: Colors.white),
      ),
      DownloadStatus.failed => (
        'Fehlgeschlagen: ${item!.error ?? ''}\nAntippen zum erneuten Versuch',
        () => notifier.resume(item.id),
        Icon(Icons.error_outline_rounded, size: size * 0.5, color: AppColors.accent),
      ),
      DownloadStatus.done => (
        'Heruntergeladen · läuft auch ohne Internet',
        () =>
            ScaffoldMessenger.maybeOf(context)
                ?.showSnackBar(const SnackBar(content: Text('Schon heruntergeladen. Verwalten unter „Downloads“.'))),
        Icon(Icons.download_done_rounded, size: size * 0.5, color: const Color(0xFF3DD68C)),
      ),
    };

    return Tooltip(
      message: tooltip,
      child: TvFocus(
        onActivate: onTap,
        onFocusChange: (v) => setState(() => _focused = v),
        child: Semantics(
          button: true,
          label: tooltip,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              key: const ValueKey('download-button'),
              onTap: onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: lit ? 0.18 : 0.08),
                  border: Border.all(
                    color: _focused ? Colors.white : Colors.white.withValues(alpha: 0.10),
                    width: _focused ? 2 : 1,
                  ),
                ),
                child: icon,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hinweis, wenn die Download-Liste (im Schlüsselbund) gerade nicht lesbar ist.
void showDownloadListError(BuildContext context) {
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    const SnackBar(
      content: Text(
        'Die Download-Liste konnte nicht gelesen werden. Erlaube IpFlix den Zugriff auf den Schlüsselbund und versuche es erneut.',
      ),
    ),
  );
}

/// „Staffel 2 herunterladen (10 Folgen)“: alle noch nicht geladenen Folgen einreihen.
class SeasonDownloadButton extends ConsumerWidget {
  const SeasonDownloadButton({
    super.key,
    required this.seasonNumber,
    required this.episodes,
    required this.seriesTitle,
  });

  final int seasonNumber;

  /// Folgen samt angezeigtem Untertitel („S02E05 · Name“).
  final List<({Channel channel, String subtitle})> episodes;
  final String seriesTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadable = [
      for (final e in episodes)
        if (isDownloadable(e.channel)) e,
    ];
    if (kIsWeb || downloadable.isEmpty) return const SizedBox.shrink();
    final playlistId = ref.watch(activePlaylistProvider.select((p) => p?.id));
    final known = {for (final item in ref.watch(downloadsProvider)) item.id};
    final missing = [
      for (final e in downloadable)
        if (!known.contains(downloadIdFor(playlistId, e.channel))) e,
    ];
    final all = missing.isEmpty;
    String folgen(int n) => n == 1 ? '1 Folge' : '$n Folgen';
    final label = all
        ? 'Staffel $seasonNumber ist in den Downloads'
        : missing.length == downloadable.length
        ? 'Staffel $seasonNumber herunterladen (${folgen(downloadable.length)})'
        : 'Restliche ${folgen(missing.length)} herunterladen';

    Future<void> start() async {
      final notifier = ref.read(downloadsProvider.notifier);
      try {
        for (final e in missing) {
          await notifier.download(e.channel, title: seriesTitle, subtitle: e.subtitle, poster: e.channel.logo);
        }
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text('${folgen(missing.length)} eingereiht. Fortschritt unter „Downloads“.')),
          );
        }
      } catch (_) {
        if (context.mounted) showDownloadListError(context);
      }
    }

    return OutlinedButton.icon(
      key: const ValueKey('season-download'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      onPressed: all ? null : start,
      icon: Icon(all ? Icons.download_done_rounded : Icons.download_rounded, size: 18),
      label: Text(label),
    );
  }
}
