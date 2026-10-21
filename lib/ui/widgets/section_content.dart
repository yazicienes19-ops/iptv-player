import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/channel.dart';
import '../../models/channel_name.dart';
import '../../models/content_type.dart';
import '../../player/player_controller.dart';
import '../../providers/app_providers.dart';
import '../browse/poster_card.dart';
import '../theme.dart';
import 'category_views.dart';
import 'channel_views.dart';
import 'common.dart';

/// Live TV: Suche, (auf dem Handy) Kategorie-Chips und die Senderliste.
class LiveChannelsView extends ConsumerWidget {
  const LiveChannelsView({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const type = ContentType.live;
    final channels = ref.watch(visibleChannelsProvider(type));
    final categories = ref.watch(catalogProvider(type)).value?.categories ?? const [];
    final selected = ref.watch(selectedCategoryProvider(type));
    // Mit gewählter Kategorie steht sie schon in der Überschrift; pro Sender wäre sie doppelt.
    final categoryNames = selected != null ? const <String, String>{} : {for (final c in categories) c.id: c.name};
    final hideSeparators = ref.watch(hideSeparatorsProvider);
    final searching = ref.watch(searchQueryProvider(AppSection.live)).trim().isNotEmpty;
    final channelCount = searching
        ? channels.value?.where((c) => !c.isSeparator).length ?? 0
        : ref.watch(categoryCountsProvider(type))[selected?.id] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 2),
            child: Text(
              selected?.name ?? 'Live TV',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        if (!compact && channels.hasValue)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Text('$channelCount Sender',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              const Expanded(child: SearchField(section: AppSection.live)),
              const SizedBox(width: 4),
              IconButton(
                tooltip: hideSeparators ? 'Abschnitts-Trennzeilen anzeigen' : 'Abschnitts-Trennzeilen ausblenden',
                icon: Icon(
                  hideSeparators ? Icons.format_list_bulleted_rounded : Icons.view_agenda_outlined,
                  color: hideSeparators ? AppColors.textSecondary : AppColors.textPrimary,
                ),
                onPressed: () => ref.read(hideSeparatorsProvider.notifier).toggle(),
              ),
            ],
          ),
        ),
        if (compact) ...[
          const CategoryChips(type: type),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: channels.when(
            loading: () => const AsyncStateView.loading(),
            error: (e, _) => AsyncStateView.error(
              error: e,
              onRetry: () {
                ref.invalidate(m3uPlaylistProvider);
                ref.invalidate(catalogProvider(type));
              },
            ),
            data: (list) => list.isEmpty
                ? const EmptyView(icon: Icons.search_off_rounded, message: 'Keine Sender gefunden.')
                : ChannelList(channels: list, categoryNames: categoryNames),
          ),
        ),
      ],
    );
  }
}

/// „Meine Liste“: Sender als Logo-Kacheln, Filme und Serien als Poster.
class FavoritesView extends ConsumerWidget {
  const FavoritesView({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(favoritesProvider);
    final visible = ref.watch(visibleFavoritesProvider);
    final hPad = compact ? 16.0 : 32.0;
    final textTheme = Theme.of(context).textTheme;

    List<Channel> ofType(ContentType t) => visible.where((c) => c.type == t).toList();
    final live = ofType(ContentType.live);
    final movies = ofType(ContentType.movie);
    final series = ofType(ContentType.series);

    Widget rowTitle(String text) => Padding(
          padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 8),
          child: Text(text, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        );

    Widget posterRow(List<Channel> items) {
      final width = compact ? 112.0 : 150.0;
      return SizedBox(
        height: width / PosterCard.aspectRatio + 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 6),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, i) => PosterCard(channel: items[i], queue: items, width: width),
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hPad, compact ? 4 : 20, hPad, 16),
            child: Row(
              children: [
                if (!compact) ...[
                  Text('Meine Liste', style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  const SizedBox(width: 320, child: SearchField(section: AppSection.favorites)),
                ] else
                  const Expanded(child: SearchField(section: AppSection.favorites)),
              ],
            ),
          ),
        ),
        if (all.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyView(
              icon: Icons.star_outline_rounded,
              message: 'Deine Liste ist noch leer.\nMarkiere Sender, Filme oder Serien mit dem Stern.',
            ),
          )
        else if (visible.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyView(icon: Icons.search_off_rounded, message: 'Nichts gefunden.'),
          )
        else
          SliverList.list(
            children: [
              if (live.isNotEmpty) ...[
                rowTitle('Sender'),
                SizedBox(
                  height: (compact ? 160 : 200) * 9 / 16 + 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 6),
                    itemCount: live.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, i) => LiveCard(
                      channel: live[i],
                      queue: live,
                      width: compact ? 160 : 200,
                      onTap: () {
                        ref.read(playerControllerProvider.notifier).play(live[i], queue: live);
                        ref.read(sectionProvider.notifier).select(AppSection.live);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (movies.isNotEmpty) ...[rowTitle('Filme'), posterRow(movies), const SizedBox(height: 16)],
              if (series.isNotEmpty) ...[rowTitle('Serien'), posterRow(series), const SizedBox(height: 16)],
              const SizedBox(height: 32),
            ],
          ),
      ],
    );
  }
}
