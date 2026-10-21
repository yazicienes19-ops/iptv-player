import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/mini_player.dart';
import '../../player/player_controller.dart';
import '../../providers/app_providers.dart';
import '../playlists/playlist_sheet.dart';
import '../settings/settings_page.dart';
import '../widgets/vpn_badge.dart';
import '../browse/browse_view.dart';
import '../widgets/section_content.dart';
import 'home_shell.dart';

/// iPhone / iPad hochkant: Tab-Leiste unten, darüber der Mini-Player.
class CompactLayout extends ConsumerWidget {
  const CompactLayout({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(sectionProvider);
    final playlist = ref.watch(activePlaylistProvider);
    final hasPlayback = ref.watch(playerControllerProvider.select((s) => s.channel != null));

    return Scaffold(
      appBar: AppBar(
        title: Text(section.label, style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          TextButton.icon(
            onPressed: () => showPlaylistSheet(context),
            icon: const Icon(Icons.playlist_play_rounded),
            label: Text(playlist?.name ?? '', overflow: TextOverflow.ellipsis),
          ),
          const VpnBadge(iconOnly: true),
          IconButton(
            tooltip: 'Einstellungen',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => Navigator.of(context).push(SettingsPage.route()),
          ),
        ],
      ),
      body: switch (section) {
        AppSection.live => const LiveChannelsView(compact: true),
        AppSection.favorites => const FavoritesView(compact: true),
        _ => BrowseView(key: ValueKey(section), type: section.contentType!, compact: true),
      },
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasPlayback) const MiniPlayer(),
          NavigationBar(
            selectedIndex: section.index,
            onDestinationSelected: (i) => ref.read(sectionProvider.notifier).select(AppSection.values[i]),
            destinations: [
              for (final s in AppSection.values)
                NavigationDestination(
                  icon: Icon(sectionIcons[s]!.$1),
                  selectedIcon: Icon(sectionIcons[s]!.$2),
                  label: s.label,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
