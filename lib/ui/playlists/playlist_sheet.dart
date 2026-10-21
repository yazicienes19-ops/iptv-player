import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/playlist_credentials.dart';
import '../../player/player_controller.dart';
import '../../providers/app_providers.dart';
import '../onboarding/add_playlist_screen.dart';
import '../theme.dart';

/// Playlists wechseln, löschen oder neue hinzufügen.
Future<void> showPlaylistSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (_) => const _PlaylistSheet(),
  );
}

class _PlaylistSheet extends ConsumerWidget {
  const _PlaylistSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playlistsProvider);
    final notifier = ref.read(playlistsProvider.notifier);
    final activeId = state.active?.id;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Playlists', style: Theme.of(context).textTheme.titleLarge),
          ),
          for (final playlist in state.playlists)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: Icon(
                playlist.isXtream ? Icons.dns_outlined : Icons.list_alt,
                color: playlist.id == activeId ? AppColors.accent : null,
              ),
              title: Text(playlist.name),
              subtitle: Text(playlist.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
              selected: playlist.id == activeId,
              trailing: IconButton(
                tooltip: 'Löschen',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDelete(context, ref, playlist),
              ),
              onTap: () async {
                if (playlist.id != activeId) {
                  await ref.read(playerControllerProvider.notifier).stop();
                  await notifier.select(playlist.id);
                }
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Playlist hinzufügen'),
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddPlaylistScreen()));
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, PlaylistCredentials playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Playlist löschen?'),
        content: Text('„${playlist.name}“ und ihre Favoriten werden entfernt.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (ref.read(activePlaylistProvider)?.id == playlist.id) {
      await ref.read(playerControllerProvider.notifier).stop();
    }
    await ref.read(playlistsProvider.notifier).remove(playlist);
    if (context.mounted && ref.read(playlistsProvider).playlists.isEmpty) Navigator.of(context).pop();
  }
}
