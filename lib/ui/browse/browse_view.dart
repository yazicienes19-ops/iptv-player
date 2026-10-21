import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/category.dart';
import '../../models/channel.dart';
import '../../models/content_type.dart';
import '../../providers/app_providers.dart';
import '../detail/detail_page.dart';
import '../theme.dart';
import '../widgets/channel_views.dart';
import '../widgets/common.dart';
import '../widgets/media_image.dart';
import 'poster_card.dart';

/// Filme oder Serien im Netflix-Stil: Titelbild + Reihen pro Kategorie.
/// Mit Suchbegriff oder gewählter Kategorie wird daraus ein Poster-Raster.
class BrowseView extends ConsumerWidget {
  const BrowseView({super.key, required this.type, this.compact = false});

  final ContentType type;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = AppSection.values.firstWhere((s) => s.contentType == type);
    final query = ref.watch(searchQueryProvider(section)).trim();
    final category = ref.watch(selectedCategoryProvider(type));
    final filtering = query.isNotEmpty || category != null;
    final hPad = compact ? 16.0 : 32.0;

    final header = SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(hPad, compact ? 4 : 20, hPad, 12),
        child: Row(
          children: [
            if (compact)
              Expanded(child: SearchField(section: section))
            else ...[
              Text(type.label, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              SizedBox(width: 320, child: SearchField(section: section)),
            ],
          ],
        ),
      ),
    );

    if (filtering) {
      return _FilteredGrid(type: type, header: header, category: category, horizontalPadding: hPad);
    }

    return ref.watch(channelsByCategoryProvider(type)).when(
          loading: () => const AsyncStateView.loading(),
          error: (e, _) => AsyncStateView.error(error: e, onRetry: () => _reload(ref)),
          data: (rows) {
            if (rows.isEmpty) {
              return EmptyView(icon: Icons.movie_outlined, message: 'Keine ${type.label} in dieser Playlist.');
            }
            final featured = _pickFeatured(rows);
            return CustomScrollView(
              slivers: [
                header,
                if (featured != null)
                  SliverToBoxAdapter(
                    child: HeroBanner(channel: featured, compact: compact, horizontalPadding: hPad),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.only(top: 8, bottom: 32),
                  sliver: SliverList.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, i) => CategoryRow(
                      category: rows[i].$1,
                      channels: rows[i].$2,
                      horizontalPadding: hPad,
                      posterWidth: compact ? 112 : 150,
                    ),
                  ),
                ),
              ],
            );
          },
        );
  }

  void _reload(WidgetRef ref) {
    ref.invalidate(m3uPlaylistProvider);
    ref.invalidate(catalogProvider(type));
  }

  /// Wechselt täglich, bleibt innerhalb eines Tages aber stabil.
  static Channel? _pickFeatured(List<(Category, List<Channel>)> rows) {
    final candidates = [
      for (final row in rows.take(6)) ...row.$2.take(10).where((c) => c.logo != null),
    ];
    if (candidates.isEmpty) return rows.first.$2.first;
    final day = DateTime.now().difference(DateTime(2024)).inDays;
    return candidates[day % candidates.length];
  }
}

class HeroBanner extends ConsumerWidget {
  const HeroBanner({super.key, required this.channel, required this.compact, required this.horizontalPadding});

  final Channel channel;
  final bool compact;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(mediaDetailsProvider(channel)).value;
    final textTheme = Theme.of(context).textTheme;
    final height = compact ? 420.0 : 460.0;
    final meta = [
      ...?details?.metaParts.take(2),
      if (details?.rating != null && details!.rating! > 0) '★ ${details.rating!.toStringAsFixed(1)}',
    ];

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          BackdropImage(backdrop: details?.backdrop, poster: channel.logo),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xF00B0C10), Color(0x990B0C10), Color(0x000B0C10)],
                stops: [0, 0.45, 0.8],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x000B0C10), AppColors.background],
                stops: [0.55, 1],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(horizontalPadding, 24, horizontalPadding, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (compact) ...[
                          Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(
                                width: 150,
                                child: AspectRatio(
                                  aspectRatio: PosterCard.aspectRatio,
                                  child: MediaImage(
                                    url: channel.logo,
                                    placeholder: TitlePlaceholder(title: channel.name),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Text(
                          channel.type == ContentType.series ? 'SERIE' : 'FILM',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          channel.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: (compact ? textTheme.headlineSmall : textTheme.displaySmall)
                              ?.copyWith(fontWeight: FontWeight.w800, height: 1.05, letterSpacing: -0.5),
                        ),
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(meta.join('  ·  '), style: const TextStyle(color: AppColors.textSecondary)),
                        ],
                        if (!compact && details?.plot != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            details!.plot!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(height: 1.4, color: Color(0xFFD0D3D9)),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                                textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                              ),
                              onPressed: () => channel.isPlayable
                                  ? playFullscreen(context, ref, channel, [channel])
                                  : openChannel(context, ref, channel, [channel]),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: Text(channel.isPlayable ? 'Abspielen' : 'Ansehen'),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0x55FFFFFF),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                              ),
                              onPressed: () => Navigator.of(context).push(DetailPage.route(channel, [channel])),
                              icon: const Icon(Icons.info_outline_rounded),
                              label: const Text('Mehr Infos'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // Ohne echtes Backdrop zeigt die breite Ansicht das Poster scharf daneben.
                if (!compact && details?.backdrop == null && channel.logo != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 32),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 40, offset: Offset(0, 16))],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          height: height - 96,
                          child: AspectRatio(
                            aspectRatio: PosterCard.aspectRatio,
                            child: MediaImage(url: channel.logo),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Eine waagerechte Poster-Reihe mit Überschrift und „Alle anzeigen“.
class CategoryRow extends ConsumerWidget {
  const CategoryRow({
    super.key,
    required this.category,
    required this.channels,
    required this.horizontalPadding,
    required this.posterWidth,
  });

  static const maxItems = 30;

  final Category category;
  final List<Channel> channels;
  final double horizontalPadding;
  final double posterWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = channels.take(maxItems).toList();
    final posterHeight = posterWidth / PosterCard.aspectRatio;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding - 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                  onPressed: () => ref.read(selectedCategoryProvider(category.type).notifier).select(category),
                  child: Text('Alle ${channels.length}  ›'),
                ),
              ],
            ),
          ),
          SizedBox(
            // Platz für Titelzeile und die Vergrößerung beim Überfahren.
            height: posterHeight + 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 6),
              clipBehavior: Clip.none,
              itemCount: visible.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => PosterCard(channel: visible[i], queue: channels, width: posterWidth),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilteredGrid extends ConsumerWidget {
  const _FilteredGrid({
    required this.type,
    required this.header,
    required this.category,
    required this.horizontalPadding,
  });

  final ContentType type;
  final Widget header;
  final Category? category;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(visibleChannelsProvider(type));
    return CustomScrollView(
      slivers: [
        header,
        if (category != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(horizontalPadding - 8, 0, horizontalPadding, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Zur Übersicht',
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => ref.read(selectedCategoryProvider(type).notifier).select(null),
                  ),
                  Expanded(
                    child: Text(
                      category!.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ...channels.when(
          loading: () => [const SliverFillRemaining(child: AsyncStateView.loading())],
          error: (e, _) => [
            SliverFillRemaining(
              child: AsyncStateView.error(error: e, onRetry: () => ref.invalidate(catalogProvider(type))),
            ),
          ],
          data: (list) => [
            if (list.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyView(icon: Icons.search_off_rounded, message: 'Nichts gefunden.'),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 32),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 160,
                    // Poster 2:3 plus Titelzeile.
                    childAspectRatio: 0.58,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 14,
                  ),
                  itemCount: list.length,
                  itemBuilder: (context, i) => LayoutBuilder(
                    builder: (context, c) => PosterCard(channel: list[i], queue: list, width: c.maxWidth),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
