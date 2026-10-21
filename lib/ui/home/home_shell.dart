import 'package:flutter/material.dart';

import '../../providers/app_providers.dart';

import 'compact_layout.dart';
import 'wide_layout.dart';

/// Ab 900 pt Breite (macOS, iPad quer) drei Spalten, sonst Tab-Leiste.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  static const wideBreakpoint = 900.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth >= wideBreakpoint ? const WideLayout() : const CompactLayout(),
    );
  }
}

const sectionIcons = <AppSection, (IconData, IconData)>{
  AppSection.live: (Icons.live_tv_outlined, Icons.live_tv_rounded),
  AppSection.movies: (Icons.movie_outlined, Icons.movie_rounded),
  AppSection.series: (Icons.video_library_outlined, Icons.video_library_rounded),
  AppSection.favorites: (Icons.star_outline_rounded, Icons.star_rounded),
};
