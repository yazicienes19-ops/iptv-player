import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';

import 'compact_layout.dart';
import 'wide_layout.dart';

/// Ab 900 pt Breite (macOS, iPad quer) drei Spalten, sonst Tab-Leiste.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  static const wideBreakpoint = 900.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTv = ref.watch(isTelevisionProvider);
    final layout = LayoutBuilder(
      builder: (context, constraints) =>
          isTv || constraints.maxWidth >= wideBreakpoint ? const WideLayout() : const CompactLayout(),
    );
    if (!isTv) return layout;
    // Manche Fernseher schneiden den Bildrand ab (Overscan): sicheren Abstand halten.
    return const ColoredBox(
      color: Color(0xFF0A0C10),
      child: Padding(padding: EdgeInsets.symmetric(horizontal: 32, vertical: 18), child: _TvLayout()),
    );
  }
}

class _TvLayout extends StatelessWidget {
  const _TvLayout();

  @override
  Widget build(BuildContext context) => const WideLayout();
}

const sectionIcons = <AppSection, (IconData, IconData)>{
  AppSection.home: (Icons.home_outlined, Icons.home_rounded),
  AppSection.live: (Icons.live_tv_outlined, Icons.live_tv_rounded),
  AppSection.movies: (Icons.movie_outlined, Icons.movie_rounded),
  AppSection.series: (Icons.video_library_outlined, Icons.video_library_rounded),
  AppSection.favorites: (Icons.star_outline_rounded, Icons.star_rounded),
};
