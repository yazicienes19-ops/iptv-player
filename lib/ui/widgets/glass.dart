import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/category.dart';
import '../../models/content_type.dart';
import '../../models/language.dart';
import '../../providers/app_providers.dart';
import '../theme.dart';
import 'tv_focus.dart';

/// Milchglas-Fläche: weichgezeichneter Hintergrund mit halbtransparenter Tönung.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 0,
    this.blur = 28,
    this.tint = const Color(0x990E1117),
    this.border = true,
    this.padding,
  });

  final Widget child;
  final double radius;
  final double blur;
  final Color tint;
  final bool border;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(radius),
            border: border ? Border.all(color: Colors.white.withValues(alpha: 0.08)) : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Kompakter Länder-/Sprachfilter mit Flagge: „🇩🇪 Deutsch ▾“.
class LanguageFilterButton extends ConsumerWidget {
  const LanguageFilterButton({super.key, this.compact = false});

  /// Nur Flagge (für die schmale Kopfzeile auf dem Handy).
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = Language.byCode(ref.watch(languageFilterProvider));
    final available = ref.watch(availableLanguagesProvider);
    final notifier = ref.read(languageFilterProvider.notifier);
    // Die Schnellwahl zeigt immer Deutsch, English, Türkçe, Shqip, dazu was die Playlist sonst enthält.
    final quick = {
      for (final code in ['de', 'en', 'tr', 'sq']) ?Language.byCode(code),
      ...available,
    }.toList();

    return PopupMenuButton<String>(
      tooltip: 'Sprache / Land',
      position: PopupMenuPosition.under,
      color: AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (code) => notifier.select(code == 'all' ? null : code),
      itemBuilder: (context) => [
        _item('all', '🌍', 'Alle Sprachen', selected == null),
        const PopupMenuDivider(),
        for (final language in quick)
          _item(
            language.code,
            language.flag,
            language.label,
            selected?.code == language.code,
            dimmed: !available.contains(language),
          ),
      ],
      child: compact
          ? Padding(
              padding: const EdgeInsets.all(10),
              child: Text(selected?.flag ?? '🌍', style: const TextStyle(fontSize: 20)),
            )
          : Glass(
              radius: 12,
              tint: const Color(0x14FFFFFF),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Text(selected?.flag ?? '🌍', style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      selected?.label ?? 'Alle Sprachen',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                  ),
                  const Icon(Icons.expand_more_rounded, size: 18, color: AppColors.textSecondary),
                ],
              ),
            ),
    );
  }

  static PopupMenuItem<String> _item(String value, String flag, String label, bool checked, {bool dimmed = false}) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Text(flag, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: checked ? FontWeight.w700 : FontWeight.w400,
                color: dimmed ? AppColors.textSecondary : null,
              ),
            ),
          ),
          if (checked) const Icon(Icons.check_rounded, size: 18, color: AppColors.accent),
        ],
      ),
    );
  }
}

/// Waagerechte Glas-Chips für Kategorien unter dem Banner (Filme, Serien).
class CategoryPills extends ConsumerWidget {
  const CategoryPills({super.key, required this.type, required this.horizontalPadding, this.leadingInset = 0});

  final ContentType type;
  final double horizontalPadding;
  final double leadingInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(filteredCategoriesProvider(type));
    final selected = ref.watch(selectedCategoryProvider(type));
    final notifier = ref.read(selectedCategoryProvider(type).notifier);
    if (categories.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: EdgeInsets.only(left: leadingInset + horizontalPadding, right: horizontalPadding),
        itemCount: categories.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final Category? category = i == 0 ? null : categories[i - 1];
          return GlassPill(
            label: category?.name ?? 'Alle',
            selected: category == selected,
            onTap: () => notifier.select(category),
          );
        },
      ),
    );
  }
}

class GlassPill extends StatefulWidget {
  const GlassPill({super.key, required this.label, required this.selected, required this.onTap, this.icon});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  State<GlassPill> createState() => _GlassPillState();
}

class _GlassPillState extends State<GlassPill> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final lit = _hovered || _focused;
    return TvFocus(
      onActivate: widget.onTap,
      onFocusChange: (v) => setState(() => _focused = v),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.selected
                  ? Colors.white
                  : lit
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: _focused ? Colors.white : Colors.white.withValues(alpha: widget.selected ? 0 : 0.10),
                width: _focused ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 16, color: widget.selected ? Colors.black : AppColors.textPrimary),
                  const SizedBox(width: 6),
                ],
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
                    color: widget.selected ? Colors.black : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Passendes Symbol zu einem Kategorienamen (Sport, Nachrichten, Kinder …).
IconData iconForCategory(String name) {
  final n = name.toLowerCase();
  bool has(List<String> words) => words.any(n.contains);
  if (has(['sport', 'fußball', 'fussball', 'football', 'bundesliga', 'dazn', 'sky sport', 'spor'])) {
    return Icons.sports_soccer_rounded;
  }
  if (has(['news', 'nachricht', 'haber', 'info'])) return Icons.newspaper_rounded;
  if (has(['kids', 'kinder', 'cocuk', 'çocuk', 'cartoon', 'anim', 'family', 'familie'])) {
    return Icons.child_care_rounded;
  }
  if (has(['music', 'musik', 'müzik', 'muzik', 'radio'])) return Icons.music_note_rounded;
  if (has(['doku', 'docu', 'belgesel', 'natur', 'nature', 'wissen', 'education'])) return Icons.public_rounded;
  if (has(['film', 'movie', 'kino', 'cinema', 'sinema'])) return Icons.movie_rounded;
  if (has(['serie', 'series', 'dizi'])) return Icons.video_library_rounded;
  if (has(['4k', 'uhd', 'hevc'])) return Icons.four_k_rounded;
  if (has(['religi', 'islam', 'dini', 'church'])) return Icons.mosque_rounded;
  if (has(['shop', 'teleshop'])) return Icons.shopping_bag_rounded;
  if (has(['adult', 'xxx', '18+'])) return Icons.lock_rounded;
  if (has(['regional', 'lokal', 'local', 'dritte'])) return Icons.location_on_rounded;
  return Icons.live_tv_rounded;
}
