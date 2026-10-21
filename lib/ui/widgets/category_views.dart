import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/category.dart';
import '../../models/content_type.dart';
import '../../providers/app_providers.dart';
import '../theme.dart';

/// Kategorien für die linke Spalte (macOS / iPad quer): Filterfeld, „Alle“
/// mit Gesamtzahl und Senderzahl je Kategorie.
class CategoryList extends ConsumerStatefulWidget {
  const CategoryList({super.key, required this.type});

  final ContentType type;

  @override
  ConsumerState<CategoryList> createState() => _CategoryListState();
}

class _CategoryListState extends ConsumerState<CategoryList> {
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.type;
    final catalog = ref.watch(catalogProvider(type));
    final selected = ref.watch(selectedCategoryProvider(type));
    final counts = ref.watch(categoryCountsProvider(type));
    final notifier = ref.read(selectedCategoryProvider(type).notifier);
    final query = _filter.text.trim().toLowerCase();
    final categories = (catalog.value?.categories ?? const <Category>[])
        .where((c) => (counts[c.id] ?? 0) > 0)
        .where((c) => query.isEmpty || c.name.toLowerCase().contains(query))
        .toList();
    final allLabel = switch (type) {
      ContentType.live => 'Alle Sender',
      ContentType.movie => 'Alle Filme',
      ContentType.series => 'Alle Serien',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: SizedBox(
            height: 34,
            child: TextField(
              controller: _filter,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Kategorie suchen …',
                hintStyle: const TextStyle(fontSize: 13),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                prefixIcon: const Icon(Icons.filter_list_rounded, size: 18),
                prefixIconConstraints: const BoxConstraints(minWidth: 34),
                suffixIcon: _filter.text.isEmpty
                    ? null
                    : IconButton(iconSize: 16, icon: const Icon(Icons.close), onPressed: () => setState(_filter.clear)),
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 4, 16, 6),
          child: Text('KATEGORIEN', style: TextStyle(fontSize: 11, letterSpacing: 0.8, color: AppColors.textSecondary)),
        ),
        if (catalog.isLoading && categories.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator())
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              itemCount: categories.length + (query.isEmpty ? 1 : 0),
              itemBuilder: (context, index) {
                final category = query.isEmpty ? (index == 0 ? null : categories[index - 1]) : categories[index];
                return _CategoryItem(
                  label: category?.name ?? allLabel,
                  count: counts[category?.id] ?? 0,
                  selected: category == selected,
                  emphasized: category == null,
                  onTap: () => notifier.select(category),
                );
              },
            ),
          ),
        if (!catalog.isLoading && categories.isEmpty && query.isNotEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Keine passende Kategorie.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ),
      ],
    );
  }
}

class _CategoryItem extends StatefulWidget {
  const _CategoryItem({
    required this.label,
    required this.count,
    required this.selected,
    required this.emphasized,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final bool emphasized;
  final VoidCallback onTap;

  @override
  State<_CategoryItem> createState() => _CategoryItemState();
}

class _CategoryItemState extends State<_CategoryItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.16)
                : _hovered
                ? AppColors.surface
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? AppColors.accent.withValues(alpha: 0.5) : Colors.transparent),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: selected || widget.emphasized ? AppColors.textPrimary : AppColors.textSecondary,
                    fontWeight: selected || widget.emphasized ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (widget.emphasized)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.accent : AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${widget.count}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                )
              else
                Text(
                  '${widget.count}',
                  style: TextStyle(
                    fontSize: 12,
                    color: selected ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.8),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Waagerechte Kategorie-Chips für das Handy-Layout.
class CategoryChips extends ConsumerWidget {
  const CategoryChips({super.key, required this.type});

  final ContentType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(catalogProvider(type)).value?.categories ?? const <Category>[];
    final selected = ref.watch(selectedCategoryProvider(type));
    final notifier = ref.read(selectedCategoryProvider(type).notifier);
    if (categories.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = index == 0 ? null : categories[index - 1];
          return ChoiceChip(
            label: Text(category?.name ?? 'Alle'),
            selected: category == selected,
            showCheckmark: false,
            onSelected: (_) => notifier.select(category),
          );
        },
      ),
    );
  }
}
