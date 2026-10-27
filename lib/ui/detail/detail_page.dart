import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/catalog.dart';
import '../../models/channel.dart';
import '../../models/channel_name.dart';
import '../../models/content_type.dart';
import '../../providers/app_providers.dart';
import '../../providers/imdb_providers.dart';
import '../../services/personal_library.dart';
import '../browse/browse_view.dart';
import '../browse/poster_card.dart';
import '../theme.dart';
import '../widgets/channel_views.dart';
import '../widgets/glass.dart';
import 'tmdb_widgets.dart';
import '../widgets/media_image.dart';
import '../widgets/tv_focus.dart';

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
    final feedback = ref.watch(recommendationFeedbackProvider(channel));
    final hPad = compact ? 16.0 : 40.0;
    final textTheme = Theme.of(context).textTheme;
    final isSeries = channel.type == ContentType.series && !channel.isPlayable;
    final seasons = details.seasons;
    final season = seasons.isEmpty ? null : seasons[_seasonIndex.clamp(0, seasons.length - 1)];
    final similar = (ref.watch(catalogProvider(channel.type)).value?.channels ?? const <Channel>[])
        .where((c) => c.categoryId == channel.categoryId && c != channel)
        .take(20)
        .toList();

    final name = channel.display;
    final hasTmdbKey = ref.watch(tmdbApiProvider) != null;
    final tmdbAsync = ref.watch(tmdbTitleProvider(channel));
    final tmdb = tmdbAsync.value;
    final matchedMovie = ref.watch(imdbCatalogProvider).value?.match(channel);
    final year = name.year ?? channel.year ?? int.tryParse(details.year ?? '') ?? tmdb?.year ?? matchedMovie?.year;
    final rating = (tmdb?.rating ?? 0) > 0 ? tmdb!.rating : details.rating;
    // Deutsche TMDB-Handlung vor der des Anbieters (oft englisch), englische TMDB-Handlung zuletzt.
    final germanOverview = tmdb != null && tmdb.overviewIsGerman ? tmdb.overview : null;
    final plot = germanOverview ?? details.plot ?? tmdb?.overview;
    final backdrop = details.backdrop ?? tmdb?.backdrop;
    final poster = channel.logo ?? tmdb?.poster;
    final meta = [
      details.genre ??
          (tmdb != null && tmdb.genres.isNotEmpty
              ? tmdb.genres.take(3).join(', ')
              : matchedMovie?.genres.take(3).join(', ')),
      details.duration ?? tmdb?.runtimeLabel,
      if (rating != null && rating > 0) '★ ${rating.toStringAsFixed(1)}${tmdb?.rating == rating ? ' TMDB' : ''}',
    ].nonNulls.toList();
    // TMDB-Empfehlungen, die in der Playlist stecken; sonst dieselbe Kategorie.
    final recommended = tmdb == null ? const <Channel>[] : availableRecommendations(ref, tmdb.recommendations);
    final language = ref.watch(languageFilterProvider);
    final languageIndex = ref.watch(languageIndexProvider(channel.type));
    final moreLikeThis = (recommended.length >= 3 ? recommended : similar)
        .where(
          (c) =>
              c != channel &&
              languageIndex.matches(c, language) &&
              ref.watch(recommendationFeedbackProvider(c)) != FeedbackChoice.hide,
        )
        .take(20)
        .toList();

    final library = ref.watch(personalLibraryProvider);
    final next = isSeries ? continueEpisode(library, seasons) : null;
    final movieResume = isSeries ? null : library.resumeFor(channel);
    final canResume = movieResume != null && !movieResume.done;
    final String playLabel;
    if (next != null) {
      final where =
          'S${next.season.number} F${next.episode.number > 0 ? next.episode.number : next.season.episodes.indexOf(next.episode) + 1}';
      playLabel = next.point != null ? '$where fortsetzen' : 'Weiter mit $where';
    } else {
      playLabel = isSeries
          ? 'Folge 1 abspielen'
          : canResume
          ? 'Fortsetzen'
          : 'Abspielen';
    }
    final resumeHint = next?.point != null
        ? remainingLabel(next!.point!.remaining)
        : canResume
        ? remainingLabel(movieResume.remaining)
        : null;

    void play() {
      if (next != null) {
        playFullscreen(context, ref, next.episode.channel, next.season.channels);
      } else if (isSeries) {
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
          name.title,
          style: (compact ? textTheme.headlineSmall : textTheme.displaySmall)?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.05,
            letterSpacing: -0.5,
          ),
        ),
        if (tmdb?.tagline != null) ...[
          const SizedBox(height: 8),
          Text(
            tmdb!.tagline!,
            style: const TextStyle(fontStyle: FontStyle.italic, color: AppColors.textSecondary, fontSize: 15),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (year != null)
              MetaBadge(text: tmdb?.endYear != null && tmdb!.endYear != year ? '$year–${tmdb.endYear}' : '$year'),
            if (tmdb?.certification != null) MetaBadge(text: tmdb!.certification!, filled: false),
            for (final q in name.qualities.take(2)) QualityBadge(tag: q),
            if (isSeries && seasons.isNotEmpty) MetaBadge(text: seasonSummary(seasons), filled: false),
          ],
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(meta.join('  ·  '), style: const TextStyle(color: AppColors.textSecondary)),
        ],
        if (resumeHint != null) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: compact ? double.infinity : 320,
            child: Row(
              children: [
                Expanded(child: ResumeBar(fraction: (next?.point ?? movieResume)!.fraction)),
                const SizedBox(width: 12),
                Text(resumeHint, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          ),
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
              label: Text(playLabel),
            ),
            if (canResume)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  minimumSize: Size(compact ? double.infinity : 0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  side: const BorderSide(color: Color(0x66FFFFFF)),
                ),
                onPressed: () => playFullscreen(context, ref, channel, widget.queue, fromStart: true),
                icon: const Icon(Icons.replay_rounded),
                label: const Text('Von vorne'),
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
            for (final option in [FeedbackChoice.like, FeedbackChoice.hide])
              Semantics(
                selected: feedback == option,
                child: OutlinedButton.icon(
                  key: ValueKey('feedback-${option.name}'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: feedback == option ? const Color(0x334A90E2) : null,
                    minimumSize: Size(compact ? double.infinity : 0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    side: BorderSide(color: feedback == option ? Colors.white : const Color(0x66FFFFFF)),
                  ),
                  onPressed: () async {
                    try {
                      await ref.read(personalLibraryProvider.notifier).toggleFeedback(channel, option);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Deine Auswahl konnte nicht dauerhaft gespeichert werden.')),
                        );
                      }
                    }
                  },
                  icon: Icon(
                    feedback == option
                        ? Icons.check_rounded
                        : option == FeedbackChoice.like
                        ? Icons.thumb_up_outlined
                        : Icons.not_interested_rounded,
                  ),
                  label: Text(option == FeedbackChoice.like ? 'Gefällt mir' : 'Nicht interessiert'),
                ),
              ),
            if (tmdb?.trailerYoutubeKey != null)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  minimumSize: Size(compact ? double.infinity : 0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  side: const BorderSide(color: Color(0x66FFFFFF)),
                ),
                // Öffnet YouTube im Browser bzw. in der YouTube-App.
                onPressed: () => launchUrl(
                  Uri.parse('https://www.youtube.com/watch?v=${tmdb!.trailerYoutubeKey}'),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.smart_display_rounded),
                label: const Text('Trailer'),
              ),
          ],
        ),
        if (feedback != null) ...[
          const SizedBox(height: 10),
          Text(
            feedback == FeedbackChoice.hide
                ? 'Dieser Titel erscheint nicht in deinen Empfehlungen. Erneut auswählen zum Rückgängigmachen.'
                : 'Deine Auswahl verbessert deine Empfehlungen. Erneut auswählen zum Rückgängigmachen.',
            style: textTheme.bodySmall,
          ),
        ],
        if (plot != null) ...[
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Text(plot, style: const TextStyle(height: 1.5, color: Color(0xFFD0D3D9))),
          ),
        ],
        if (tmdb != null && tmdb.directors.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: isSeries ? 'Idee: ' : 'Regie: ',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                TextSpan(text: tmdb.directors.take(3).join(', ')),
              ],
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ],
        // Ohne TMDB-Darsteller wenigstens die Besetzung des Anbieters als Text.
        if (details.cast != null && (tmdb == null || tmdb.cast.isEmpty)) ...[
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
                  BackdropImage(backdrop: backdrop, poster: poster),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x330A0C10), Color(0x000A0C10), AppColors.background],
                        stops: [0, 0.4, 1],
                      ),
                    ),
                  ),
                  if (!compact) ...[
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [Color(0xE60A0C10), Color(0x000A0C10)], stops: [0.1, 0.75]),
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
                                  url: poster,
                                  placeholder: TitlePlaceholder(
                                    title: channel.display.title,
                                    year: channel.display.year,
                                    isSeries: channel.type == ContentType.series,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 32),
                          Expanded(child: SingleChildScrollView(child: info)),
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
                                url: poster,
                                placeholder: TitlePlaceholder(
                                  title: channel.display.title,
                                  year: channel.display.year,
                                  isSeries: channel.type == ContentType.series,
                                ),
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
                    const SizedBox(width: 12),
                    Text(
                      '${season!.episodes.length} in Staffel ${season.number}',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            if (seasons.length > 1)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 52,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 8),
                    itemCount: seasons.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => GlassPill(
                      label: 'Staffel ${seasons[i].number}',
                      selected: i == _seasonIndex.clamp(0, seasons.length - 1),
                      onTap: () => setState(() => _seasonIndex = i),
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 40),
              sliver: SliverList.separated(
                itemCount: season.episodes.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => _EpisodeTile(
                  episode: season.episodes[i],
                  progress: library.resumeFor(season.episodes[i].channel),
                  index: i,
                  compact: compact,
                  onPlay: () => playFullscreen(context, ref, season.episodes[i].channel, season.channels),
                ),
              ),
            ),
          ],
          // TMDB: Darsteller, Reihe – oder ein Hinweis, wie man sie bekommt.
          if (!hasTmdbKey)
            SliverToBoxAdapter(
              child: Padding(padding: EdgeInsets.fromLTRB(hPad, 28, hPad, 0), child: const TmdbHintCard()),
            ),
          if (tmdb != null && tmdb.cast.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hPad, 32, hPad, 8),
                child: TmdbSectionTitle(isSeries ? 'Besetzung' : 'Darsteller'),
              ),
            ),
            SliverToBoxAdapter(
              child: CastRow(cast: tmdb.cast, horizontalPadding: hPad),
            ),
          ],
          if (tmdb?.collectionId != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hPad, 28, hPad, 0),
                child: CollectionBanner(id: tmdb!.collectionId!, name: tmdb.collectionName ?? 'Filmreihe'),
              ),
            ),
          if (hasTmdbKey && tmdbAsync.isLoading)
            const SliverToBoxAdapter(
              child: Padding(padding: EdgeInsets.all(24), child: LinearProgressIndicator()),
            ),
          if (moreLikeThis.isNotEmpty) ...[
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
                  itemCount: moreLikeThis.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, i) => PosterCard(
                    channel: moreLikeThis[i],
                    queue: moreLikeThis,
                    width: compact ? 112 : 150,
                    onTap: () => Navigator.of(context).pushReplacement(DetailPage.route(moreLikeThis[i], moreLikeThis)),
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

/// Schmaler Fortschrittsbalken für angefangene Filme und Folgen.
class ResumeBar extends StatelessWidget {
  const ResumeBar({super.key, required this.fraction, this.height = 4});

  final double fraction;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height),
    child: LinearProgressIndicator(
      value: fraction,
      minHeight: height,
      backgroundColor: const Color(0x55FFFFFF),
      valueColor: const AlwaysStoppedAnimation(AppColors.accent),
    ),
  );
}

class _EpisodeTile extends StatefulWidget {
  const _EpisodeTile({
    required this.episode,
    required this.progress,
    required this.index,
    required this.compact,
    required this.onPlay,
  });

  final Episode episode;
  final ResumePoint? progress;
  final int index;
  final bool compact;
  final VoidCallback onPlay;

  @override
  State<_EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends State<_EpisodeTile> {
  bool _hovered = false;
  bool _focused = false;

  /// Maus darüber oder per Fernbedienung/Tastatur fokussiert.
  bool get _lit => _hovered || _focused;

  @override
  Widget build(BuildContext context) => TvFocus(
    onActivate: widget.onPlay,
    onFocusChange: (v) => setState(() => _focused = v),
    child: FocusRing(visible: _focused, radius: 8, child: _buildTile(context)),
  );

  Widget _buildTile(BuildContext context) {
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
            color: _lit ? AppColors.surface : Colors.transparent,
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
                        if (widget.progress != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: ResumeBar(fraction: widget.progress!.fraction, height: 4),
                          ),
                        if (widget.progress?.done == true)
                          const Positioned(
                            top: 6,
                            right: 6,
                            child: Icon(
                              Icons.check_circle_rounded,
                              size: 20,
                              color: Colors.white,
                              shadows: [Shadow(blurRadius: 6)],
                            ),
                          ),
                        Center(
                          child: AnimatedOpacity(
                            opacity: _lit || widget.compact ? 1 : 0,
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
