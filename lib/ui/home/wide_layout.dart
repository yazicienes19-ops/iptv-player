import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/fullscreen_player_page.dart';
import '../../player/player_controller.dart';
import '../../player/player_view.dart';
import '../../providers/app_providers.dart';
import '../playlists/playlist_sheet.dart';
import '../settings/settings_page.dart';
import '../theme.dart';
import '../widgets/category_views.dart';
import '../browse/browse_view.dart';
import '../widgets/now_playing_panel.dart';
import '../widgets/vpn_badge.dart';
import '../widgets/section_content.dart';
import 'home_shell.dart';

/// macOS / iPad quer: Navigation + Kategorien | Senderliste | Player + EPG.
class WideLayout extends ConsumerWidget {
  const WideLayout({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(sectionProvider);
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            SizedBox(width: 240, child: _NavigationPane(section: section)),
            const VerticalDivider(width: 1),
            ...switch (section) {
              AppSection.live => [
                const SizedBox(width: 380, child: LiveChannelsView()),
                const VerticalDivider(width: 1),
                const Expanded(child: _PlayerPane()),
              ],
              AppSection.favorites => [const Expanded(child: FavoritesView())],
              _ => [
                Expanded(
                  child: BrowseView(key: ValueKey(section), type: section.contentType!),
                ),
              ],
            },
          ],
        ),
      ),
    );
  }
}

class _NavigationPane extends ConsumerWidget {
  const _NavigationPane({required this.section});

  final AppSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = ref.watch(activePlaylistProvider);
    final type = section.contentType;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(padding: EdgeInsets.fromLTRB(8, 12, 8, 0), child: VpnBadge()),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            tileColor: AppColors.surfaceHigh,
            leading: const Icon(Icons.playlist_play_rounded, color: AppColors.accent),
            title: Text(playlist?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: const Text('Playlist wechseln', style: TextStyle(fontSize: 11)),
            onTap: () => showPlaylistSheet(context),
          ),
        ),
        for (final s in AppSection.values)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            child: ListTile(
              dense: true,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              selected: s == section,
              leading: Icon(
                s == section ? sectionIcons[s]!.$2 : sectionIcons[s]!.$1,
                color: s == section ? AppColors.accent : null,
              ),
              title: Text(s.label, style: const TextStyle(fontSize: 14)),
              onTap: () => ref.read(sectionProvider.notifier).select(s),
            ),
          ),
        const Divider(height: 24),
        if (type != null) ...[
          Expanded(
            child: CategoryList(key: ValueKey(type), type: type),
          ),
        ] else
          const Spacer(),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(8),
          child: ListTile(
            dense: true,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            leading: const Icon(Icons.settings_rounded),
            title: const Text('Einstellungen', style: TextStyle(fontSize: 14)),
            onTap: () => Navigator.of(context).push(SettingsPage.route()),
          ),
        ),
      ],
    );
  }
}

class _PlayerPane extends ConsumerWidget {
  const _PlayerPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channel = ref.watch(playerControllerProvider.select((s) => s.channel));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: PlayerView(
            onToggleFullscreen: channel == null ? null : () => Navigator.of(context).push(FullscreenPlayerPage.route()),
          ),
        ),
        if (channel != null)
          Expanded(
            child: NowPlayingPanel(key: ValueKey(channel.id), channel: channel),
          )
        else
          const Expanded(
            child: Center(
              child: Text('Wähle links einen Sender aus.', style: TextStyle(color: AppColors.textSecondary)),
            ),
          ),
      ],
    );
  }
}
