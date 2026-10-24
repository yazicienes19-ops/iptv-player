import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/category.dart';
import '../../models/channel.dart';
import '../../models/content_type.dart';
import '../../player/player_controller.dart';
import '../../providers/app_providers.dart';
import '../../providers/imdb_providers.dart';
import '../browse/browse_view.dart';
import '../widgets/channel_views.dart';
import '../widgets/common.dart';

/// Startseite: Kino-Banner aus Filmen und Serien, darunter „Meine Liste“,
/// Live TV und die aktuellsten Kategorien.
class HomeView extends ConsumerWidget {
  const HomeView({super.key, this.compact = false, this.leftInset = 0});

  final bool compact;
  final double leftInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movies = ref.watch(channelsByCategoryProvider(ContentType.movie));
    final series = ref.watch(channelsByCategoryProvider(ContentType.series));
    final live = ref.watch(visibleChannelsProvider(ContentType.live)).value ?? const <Channel>[];
    final favorites = ref.watch(favoritesProvider);
    final imdbRows = ref.watch(imdbRowsProvider);
    final imdb = ref.watch(imdbCatalogProvider).value;
    final mostWatched = ref.watch(mostWatchedChannelsProvider);
    final newMovies = ref.watch(newMoviesProvider);
    final recommendations = ref.watch(recommendationsProvider);
    final hPad = compact ? 16.0 : 40.0;
    final posterWidth = compact ? 112.0 : 158.0;

    if (movies.isLoading && series.isLoading && live.isEmpty) return const AsyncStateView.loading();

    final movieRows = _ranked(movies.value ?? const []);
    final seriesRows = _ranked(series.value ?? const []);
    final hero = _interleave(
      movieRows.isEmpty ? const <Channel>[] : pickHeroItems(movieRows, max: 3),
      seriesRows.isEmpty ? const <Channel>[] : pickHeroItems(seriesRows, max: 2),
    );
    final favoriteLive = favorites.where((c) => c.type == ContentType.live).toList();
    final favoriteVod = favorites.where((c) => c.type != ContentType.live).toList();
    final liveRow = favoriteLive.isNotEmpty ? favoriteLive : live.take(20).toList();

    // Ladefehler (z. B. Server abgelehnt) nicht als „keine Inhalte“ ausgeben.
    final liveState = ref.watch(catalogProvider(ContentType.live));
    final error = liveState.error ?? movies.error ?? series.error;
    if (hero.isEmpty && liveRow.isEmpty && error != null) {
      return AsyncStateView.error(
        error: error,
        onRetry: () {
          ref.invalidate(m3uPlaylistProvider);
          for (final type in ContentType.values) {
            ref.invalidate(catalogProvider(type));
          }
        },
      );
    }
    if (hero.isEmpty && liveRow.isEmpty) {
      return const EmptyView(
        icon: Icons.tv_off_rounded,
        message: 'Diese Playlist enthält keine Inhalte für diese Sprache.',
      );
    }

    return CustomScrollView(
      slivers: [
        if (hero.isNotEmpty)
          SliverToBoxAdapter(
            child: HeroCarousel(items: hero, compact: compact, leftInset: leftInset, horizontalPadding: hPad),
          )
        else
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        SliverList.list(
          children: [
            if (recommendations.channels.isNotEmpty) ...[
              CategoryRow(
                title: 'Für dich empfohlen',
                channels: recommendations.channels,
                horizontalPadding: hPad,
                leftInset: leftInset,
                posterWidth: posterWidth,
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(leftInset + hPad, 0, hPad, 24),
                child: Text(recommendations.explanation, style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
            if (mostWatched.isNotEmpty)
              _LiveRow(
                title: 'Deine meistgesehenen Sender',
                channels: mostWatched,
                horizontalPadding: hPad,
                leftInset: leftInset,
                cardWidth: compact ? 168 : 220,
              ),
            if (newMovies.isNotEmpty) ...[
              CategoryRow(
                title: 'Neu in deiner Liste',
                channels: newMovies,
                horizontalPadding: hPad,
                leftInset: leftInset,
                posterWidth: posterWidth,
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(leftInset + hPad, 0, hPad, 24),
                child: Text(
                  'In den letzten 30 Tagen hinzugefügt oder erstmals nach dem ersten Import erkannt.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
            if (favoriteVod.isNotEmpty)
              CategoryRow(
                title: 'Meine Liste',
                channels: favoriteVod,
                horizontalPadding: hPad,
                leftInset: leftInset,
                posterWidth: posterWidth,
              ),
            if (liveRow.isNotEmpty)
              _LiveRow(
                title: favoriteLive.isNotEmpty ? 'Meine Sender' : 'Live TV',
                channels: liveRow,
                horizontalPadding: hPad,
                leftInset: leftInset,
                cardWidth: compact ? 168 : 220,
              ),
            if (imdbRows.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(leftInset + hPad, 0, hPad, 12),
                child: Text(
                  'IMDb · ab ${imdb?.minVotes} Stimmen · aus deiner Playlist',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              CategoryRow(
                title: 'Beste Filme aller Zeiten · IMDb',
                channels: imdbRows.take(20).map((row) => row.$1).toList(),
                horizontalPadding: hPad,
                leftInset: leftInset,
                posterWidth: posterWidth,
              ),
              if (imdbRows.any((row) => row.$2.genres.contains('Crime')))
                CategoryRow(
                  title: 'Beste Krimis aller Zeiten · IMDb',
                  channels: imdbRows
                      .where((row) => row.$2.genres.contains('Crime'))
                      .take(20)
                      .map((row) => row.$1)
                      .toList(),
                  horizontalPadding: hPad,
                  leftInset: leftInset,
                  posterWidth: posterWidth,
                ),
            ],
            for (final (category, channels) in movieRows.take(3))
              CategoryRow(
                category: category,
                channels: channels,
                horizontalPadding: hPad,
                leftInset: leftInset,
                posterWidth: posterWidth,
              ),
            for (final (category, channels) in seriesRows.take(3))
              CategoryRow(
                category: category,
                channels: channels,
                horizontalPadding: hPad,
                leftInset: leftInset,
                posterWidth: posterWidth,
              ),
            const SizedBox(height: 40),
          ],
        ),
      ],
    );
  }

  /// Aktuelle Kategorien (Neuerscheinungen, laufendes Jahr, 4K) zuerst.
  static List<(Category, List<Channel>)> _ranked(List<(Category, List<Channel>)> rows) {
    final now = DateTime.now().year;
    int score(Category c) {
      final n = c.name.toLowerCase();
      if (n.contains('neuerscheinung') || n.contains('$now')) return 3;
      if (n.contains('${now - 1}') || n.contains('neu') || n.contains('new')) return 2;
      if (n.contains('4k') || n.contains('top') || n.contains('trend')) return 1;
      return 0;
    }

    return [...rows]..sort((a, b) => score(b.$1).compareTo(score(a.$1)));
  }

  static List<Channel> _interleave(List<Channel> a, List<Channel> b) => [
    for (var i = 0; i < a.length || i < b.length; i++) ...[if (i < a.length) a[i], if (i < b.length) b[i]],
  ];
}

class _LiveRow extends ConsumerWidget {
  const _LiveRow({
    required this.title,
    required this.channels,
    required this.horizontalPadding,
    required this.leftInset,
    required this.cardWidth,
  });

  final String title;
  final List<Channel> channels;
  final double horizontalPadding;
  final double leftInset;
  final double cardWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final left = leftInset + horizontalPadding;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(left, 0, horizontalPadding - 8, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: () => ref.read(sectionProvider.notifier).select(AppSection.live),
                  child: const Text('Alle Sender  ›'),
                ),
              ],
            ),
          ),
          SizedBox(
            height: cardWidth * 9 / 16 + 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.only(left: left, right: horizontalPadding, top: 8, bottom: 4),
              itemCount: channels.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, i) => LiveCard(
                channel: channels[i],
                queue: channels,
                width: cardWidth,
                onTap: () {
                  ref.read(playerControllerProvider.notifier).play(channels[i], queue: channels);
                  ref.read(sectionProvider.notifier).select(AppSection.live);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
