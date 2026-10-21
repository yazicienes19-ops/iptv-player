import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../browse/browse_view.dart';
import '../widgets/section_content.dart';
import '../live/live_workspace.dart';
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
      // Ohne mittlere Liste: Kategorien links, Kachel-Raster und Player rechts.
      return const Scaffold(
        body: Row(
          children: [
            GlassSidebar(),
            Expanded(child: LiveWorkspace()),
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
