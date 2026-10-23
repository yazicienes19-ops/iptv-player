import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/tmdb.dart';
import '../../providers/app_providers.dart';
import '../browse/poster_card.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/media_image.dart';
import 'tmdb_widgets.dart';

/// Filmreihe: großer Titel, Beschreibung und alle Teile nummeriert in
/// Erscheinungsreihenfolge; abspielbar ist, was die Playlist enthält.
class CollectionPage extends ConsumerStatefulWidget {
  const CollectionPage({super.key, required this.collectionId, required this.name});

  static Route<void> route(int id, String name) => MaterialPageRoute(
    builder: (_) => CollectionPage(collectionId: id, name: name),
  );

  final int collectionId;
  final String name;

  @override
  ConsumerState<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends ConsumerState<CollectionPage> {
  bool _onlyAvailable = false;

  @override
  Widget build(BuildContext context) {
    final collection = ref.watch(tmdbCollectionProvider(widget.collectionId));
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: Padding(
          padding: const EdgeInsets.all(6),
          child: IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: const Color(0x66000000)),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      ),
      body: collection.when(
        loading: () => const AsyncStateView.loading(),
        error: (e, _) =>
            AsyncStateView.error(error: e, onRetry: () => ref.invalidate(tmdbCollectionProvider(widget.collectionId))),
        data: (c) => LayoutBuilder(builder: (context, box) => _content(context, c, compact: box.maxWidth < 700)),
      ),
    );
  }

  Widget _content(BuildContext context, TmdbCollection collection, {required bool compact}) {
    final index = ref.watch(playlistTitleIndexProvider);
    final hPad = compact ? 16.0 : 48.0;
    final numbered = [for (final (i, part) in collection.parts.indexed) (i + 1, part)];
    final visible = _onlyAvailable ? numbered.where((e) => index.find(e.$2) != null).toList() : numbered;
    final availableCount = numbered.where((e) => index.find(e.$2) != null).length;
    final years = [for (final p in collection.parts) ?p.year];
    final span = years.isEmpty ? null : (years.first == years.last ? '${years.first}' : '${years.first}–${years.last}');
    final textTheme = Theme.of(context).textTheme;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Stack(
            children: [
              Positioned.fill(
                child: Opacity(opacity: 0.35, child: MediaImage(url: collection.backdrop)),
              ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x330A0C10), AppColors.background],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(hPad, compact ? 96 : 120, hPad, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      collection.name,
                      style: (compact ? textTheme.headlineLarge : textTheme.displayMedium)?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.2,
                        height: 1.05,
                      ),
                    ),
                    if (collection.overview != null) ...[
                      const SizedBox(height: 18),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 820),
                        child: Text(
                          collection.overview!,
                          style: const TextStyle(fontSize: 16, height: 1.55, color: Color(0xFFD7DAE0)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      ['${collection.parts.length} Titel', ?span, '$availableCount in deiner Playlist'].join('  ·  '),
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 22),
                    Glass(
                      radius: 26,
                      tint: const Color(0x14FFFFFF),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ToggleChip(
                            label: 'Alle Teile',
                            selected: !_onlyAvailable,
                            onTap: () => setState(() => _onlyAvailable = false),
                          ),
                          _ToggleChip(
                            label: 'In meiner Playlist',
                            selected: _onlyAvailable,
                            onTap: () => setState(() => _onlyAvailable = true),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (visible.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyView(
              icon: Icons.movie_filter_outlined,
              message: 'Kein Teil dieser Reihe ist in deiner Playlist.',
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 48),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: compact ? 170 : 230,
                childAspectRatio: PosterCard.aspectRatio * 0.86,
                mainAxisSpacing: 24,
                crossAxisSpacing: 20,
              ),
              itemCount: visible.length,
              itemBuilder: (context, i) => LayoutBuilder(
                builder: (context, c) => TmdbPosterTile(item: visible[i].$2, number: visible[i].$1, width: c.maxWidth),
              ),
            ),
          ),
      ],
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Text(label, style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500, fontSize: 14.5)),
      ),
    );
  }
}
