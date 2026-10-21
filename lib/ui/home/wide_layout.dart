import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/fullscreen_player_page.dart';
import '../../player/player_controller.dart';
import '../../player/player_view.dart';
import '../../providers/app_providers.dart';
import '../browse/browse_view.dart';
import '../widgets/live_dashboard.dart';
import '../widgets/now_playing_panel.dart';
import '../widgets/section_content.dart';
import 'home_view.dart';
import 'sidebar.dart';

/// macOS / iPad quer / Fernseher.
///
/// Live TV: Glas-Seitenleiste (mit Kategorien) | Senderliste | Player + Infos.
/// Startseite, Filme, Serien: Inhalte laufen randlos unter der schwebenden
/// Glas-Seitenleiste hindurch, wie bei Apple TV.
class WideLayout extends ConsumerWidget {
  const WideLayout({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(sectionProvider);
    const inset = GlassSidebar.width;

    if (section == AppSection.live) {
      return const Scaffold(
        body: Row(
          children: [
            GlassSidebar(),
            SizedBox(width: 380, child: SafeArea(left: false, child: LiveChannelsView())),
            VerticalDivider(width: 1),
            Expanded(child: SafeArea(left: false, child: _PlayerPane())),
          ],
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: switch (section) {
              AppSection.home => const HomeView(leftInset: inset),
              AppSection.favorites => const Padding(
                padding: EdgeInsets.only(left: inset),
                child: SafeArea(left: false, child: FavoritesView()),
              ),
              _ => BrowseView(key: ValueKey(section), type: section.contentType!, leftInset: inset),
            },
          ),
          const Positioned(left: 0, top: 0, bottom: 0, child: GlassSidebar()),
        ],
      ),
    );
  }
}

class _PlayerPane extends ConsumerWidget {
  const _PlayerPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channel = ref.watch(playerControllerProvider.select((s) => s.channel));
    // Noch kein Sender: Dashboard statt schwarzem Kasten.
    if (channel == null) return const LiveDashboard();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: PlayerView(onToggleFullscreen: () => Navigator.of(context).push(FullscreenPlayerPage.route())),
        ),
        Expanded(
          child: NowPlayingPanel(key: ValueKey(channel.id), channel: channel),
        ),
      ],
    );
  }
}
