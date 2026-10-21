import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/catalog.dart';
import '../../models/channel.dart';
import '../../models/content_type.dart';
import '../../providers/app_providers.dart';
import '../browse/poster_card.dart';
import '../theme.dart';
import '../widgets/channel_views.dart';
import '../widgets/media_image.dart';

/// Detailseite für Filme und Serien im Netflix-Stil.
class DetailPage extends ConsumerStatefulWidget {
  const DetailPage({super.key, required this.channel, required this.queue});

  static Route<void> route(Channel channel, List<Channel> queue) => MaterialPageRoute(
    builder: (_) => DetailPage(channel: channel, queue: queue),
  );

  final Channel channel;
  final List<Channel> queue;

  @override
  ConsumerState<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends ConsumerState<DetailPage> {
  int _seasonIndex = 0;

  @override
  Widget build(BuildContext context) {
    // Nach verfügbarem Platz statt Fensterbreite (iPad Split View, schmales Mac-Fenster).
    return LayoutBuilder(builder: (context, constraints) => _build(context, constraints.maxWidth < 700));
  }

  Widget _build(BuildContext context, bool compact) {
    final channel = widget.channel;
    final detailsAsync = ref.watch(mediaDetailsProvider(channel));
    final details = detailsAsync.value ?? MediaDetails.empty;
    final isFavorite = ref.watch(favoritesProvider.select((f) => f.contains(channel)));
    final hPad = compact ? 16.0 : 40.0;
    final textTheme = Theme.of(context).textTheme;
    final isSeries = channel.type == ContentType.series && !channel.isPlayable;
    final seasons = details.seasons;
    final season = seasons.isEmpty ? null : seasons[_seasonIndex.clamp(0, seasons.length - 1)];
    final similar = (ref.watch(catalogProvider(channel.type)).value?.channels ?? const <Channel>[])
        .where((c) => c.categoryId == channel.categoryId && c != channel)
        .take(20)
        .toList();

    final meta = [
      ...details.metaParts,
      if (details.rating != null && details.rating! > 0) '★ ${details.rating!.toStringAsFixed(1)}',
      if (isSeries && seasons.isNotEmpty) seasons.length == 1 ? '1 Staffel' : '${seasons.length} Staffeln',
    ];

    void play() {
      if (isSeries) {
        final first = season?.episodes.firstOrNull;
        if (first != null) playFullscreen(context, ref, first.channel, season!.channels);
      } else {
        playFullscreen(context, ref, channel, widget.queue);
      }
    }

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          channel.name,
          style: (compact ? textTheme.headlineSmall : textTheme.displaySmall)?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.05,
            letterSpacing: -0.5,
          ),
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(meta.join('  ·  '), style: const TextStyle(color: AppColors.textSecondary)),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                minimumSize: Size(compact ? double.infinity : 0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 26),
                textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              onPressed: isSeries && season == null ? null : play,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(isSeries ? 'Folge 1 abspielen' : 'Abspielen'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                minimumSize: Size(compact ? double.infinity : 0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                side: const BorderSide(color: Color(0x66FFFFFF)),
              ),
              onPressed: () => ref.read(favoritesProvider.notifier).toggle(channel),
              icon: Icon(isFavorite ? Icons.check_rounded : Icons.add_rounded),
              label: Text(isFavorite ? 'In meiner Liste' : 'Meine Liste'),
            ),
          ],
        ),
        if (details.plot != null) ...[
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Text(details.plot!, style: const TextStyle(height: 1.5, color: Color(0xFFD0D3D9))),
          ),
        ],
        if (details.cast != null) ...[
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Besetzung: ',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  TextSpan(text: details.cast),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ],
    );

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
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: compact ? 300 : 520,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BackdropImage(backdrop: details.backdrop, poster: channel.logo),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x330B0C10), Color(0x000B0C10), AppColors.background],
                        stops: [0, 0.4, 1],
                      ),
                    ),
                  ),
                  if (!compact) ...[
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [Color(0xE60B0C10), Color(0x000B0C10)], stops: [0.1, 0.75]),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(hPad, 80, hPad, 24),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 220,
                              child: AspectRatio(
                                aspectRatio: PosterCard.aspectRatio,
                                child: MediaImage(
                                  url: channel.logo,
                                  placeholder: TitlePlaceholder(title: channel.name),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 32),
                          Expanded(child: info),
                        ],
                      ),
                    ),
                  ] else
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 140,
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
                    ),
                ],
              ),
            ),
          ),
          if (compact)
            SliverToBoxAdapter(
              child: Padding(padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 8), child: info),
            ),
          if (detailsAsync.isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          if (detailsAsync.hasError)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 16),
                child: Row(
                  children: [
                    const Text(
                      'Details konnten nicht geladen werden.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(mediaDetailsProvider(channel)),
                      child: const Text('Erneut laden'),
                    ),
                  ],
                ),
              ),
            ),
          if (isSeries && seasons.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 8),
                child: Row(
                  children: [
                    Text('Folgen', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const Spacer(),
                    if (seasons.length > 1)
                      DropdownButtonHideUnderline(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHigh,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: DropdownButton<int>(
                            value: _seasonIndex.clamp(0, seasons.length - 1),
                            dropdownColor: AppColors.surfaceHigh,
                            borderRadius: BorderRadius.circular(8),
                            items: [
                              for (var i = 0; i < seasons.length; i++)
                                DropdownMenuItem(value: i, child: Text('Staffel ${seasons[i].number}')),
                            ],
                            onChanged: (i) => setState(() => _seasonIndex = i ?? 0),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 40),
              sliver: SliverList.separated(
                itemCount: season!.episodes.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => _EpisodeTile(
                  episode: season.episodes[i],
                  index: i,
                  compact: compact,
                  onPlay: () => playFullscreen(context, ref, season.episodes[i].channel, season.channels),
                ),
              ),
            ),
          ],
          if (similar.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hPad, 32, hPad, 4),
                child: Text('Mehr wie dieses', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: (compact ? 112 : 150) / PosterCard.aspectRatio + 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 6),
                  itemCount: similar.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, i) => PosterCard(
                    channel: similar[i],
                    queue: similar,
                    width: compact ? 112 : 150,
                    onTap: () => Navigator.of(context).pushReplacement(DetailPage.route(similar[i], similar)),
                  ),
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

class _EpisodeTile extends StatefulWidget {
  const _EpisodeTile({required this.episode, required this.index, required this.compact, required this.onPlay});

  final Episode episode;
  final int index;
  final bool compact;
  final VoidCallback onPlay;

  @override
  State<_EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends State<_EpisodeTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final episode = widget.episode;
    final number = episode.number > 0 ? episode.number : widget.index + 1;
    final thumbWidth = widget.compact ? 128.0 : 168.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onPlay,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.compact)
                SizedBox(
                  width: 40,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 28),
                    child: Text(
                      '$number',
                      style: const TextStyle(fontSize: 22, color: AppColors.textSecondary, fontWeight: FontWeight.w300),
                    ),
                  ),
                ),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: thumbWidth,
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        MediaImage(url: episode.channel.logo, cacheWidth: (thumbWidth * 2).round()),
                        Center(
                          child: AnimatedOpacity(
                            opacity: _hovered || widget.compact ? 1 : 0,
                            duration: const Duration(milliseconds: 150),
                            child: const Icon(
                              Icons.play_circle_outline_rounded,
                              size: 36,
                              color: Colors.white,
                              shadows: [Shadow(blurRadius: 8)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.compact ? '$number. ${episode.channel.name}' : episode.channel.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                        ),
                        if (episode.duration != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Text(episode.duration!, style: const TextStyle(color: AppColors.textSecondary)),
                          ),
                      ],
                    ),
                    if (episode.plot != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        episode.plot!,
                        maxLines: widget.compact ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
