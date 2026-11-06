import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/catalog.dart';
import '../../models/channel.dart';
import '../../models/channel_name.dart';
import '../../models/content_type.dart';
import '../../models/tmdb.dart';
import '../../providers/app_providers.dart';
import '../../providers/imdb_providers.dart';
import '../../services/download_manager.dart';
import '../../services/imdb_catalog.dart';
import '../../services/personal_library.dart';
import '../browse/browse_view.dart';
import '../browse/poster_card.dart';
import '../theme.dart';
import '../widgets/channel_views.dart';
import '../widgets/glass.dart';
import '../widgets/media_image.dart';
import '../widgets/tv_focus.dart';
import '../downloads/download_button.dart';
import 'tmdb_widgets.dart';

/// Detailseite für Filme und Serien: Titelbild über das ganze Fenster, Infos links unten,
/// darunter Bewertungen, Besetzung, Folgen, Videos und Empfehlungen.
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
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Nach verfügbarem Platz statt Fensterbreite (iPad Split View, schmales Mac-Fenster).
    return LayoutBuilder(
      builder: (context, constraints) => _build(context, constraints.maxWidth < 700, constraints.maxHeight),
    );
  }

  Widget _build(BuildContext context, bool compact, double viewportHeight) {
    final channel = widget.channel;
    final detailsAsync = ref.watch(mediaDetailsProvider(channel));
    final details = detailsAsync.value ?? MediaDetails.empty;
    final isFavorite = ref.watch(favoritesProvider.select((f) => f.contains(channel)));
    final feedback = ref.watch(recommendationFeedbackProvider(channel));
    final hPad = compact ? 16.0 : 40.0;
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
    final genres =
        details.genre ??
        (tmdb != null && tmdb.genres.isNotEmpty
            ? tmdb.genres.take(4).join(', ')
            : matchedMovie?.genres.take(3).join(', '));
    final duration = details.duration ?? tmdb?.runtimeLabel;
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
          ? 'Staffel ${season?.number ?? 1}, Folge 1 abspielen'
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

    Future<void> toggleFeedback(FeedbackChoice option) async {
      try {
        await ref.read(personalLibraryProvider.notifier).toggleFeedback(channel, option);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Deine Auswahl konnte nicht dauerhaft gespeichert werden.')));
        }
      }
    }

    // --- Infospalte links unten im Titelbild -------------------------------------------
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _TitleArt(logo: tmdb?.logo, title: name.title, compact: compact),
        if (genres != null && genres.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(genres, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (rating != null && rating > 0) _RatingChip(rating: rating),
            if (year != null)
              Text(
                tmdb?.endYear != null && tmdb!.endYear != year ? '$year–${tmdb.endYear}' : '$year',
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
              ),
            if (duration != null)
              Text(duration, style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
            if (tmdb?.certification != null) MetaBadge(text: tmdb!.certification!, filled: false),
            for (final q in name.qualities.take(2)) QualityBadge(tag: q),
            if (isSeries && seasons.isNotEmpty)
              Text(seasonSummary(seasons), style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
          ],
        ),
        if (tmdb?.tagline != null) ...[
          const SizedBox(height: 12),
          Text(
            tmdb!.tagline!,
            style: const TextStyle(fontStyle: FontStyle.italic, color: AppColors.textSecondary, fontSize: 14),
          ),
        ],
        if (plot != null) ...[const SizedBox(height: 12), _ExpandablePlot(text: plot, collapsedLines: compact ? 5 : 9)],
        if (tmdb != null && tmdb.directors.isNotEmpty) ...[
          const SizedBox(height: 10),
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
        if (resumeHint != null) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: ResumeBar(fraction: (next?.point ?? movieResume)!.fraction)),
              const SizedBox(width: 12),
              Text(resumeHint, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
        ],
        const SizedBox(height: 18),
        _PillButton(
          key: const ValueKey('detail-play'),
          label: playLabel,
          icon: Icons.play_arrow_rounded,
          primary: true,
          // Nur für die Fernbedienung: am Mac würde der Fokus die Seite aus der Startansicht scrollen.
          autofocus: ref.watch(isTelevisionProvider),
          onPressed: isSeries && season == null ? null : play,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _RoundButton(
              key: const ValueKey('favorite-toggle'),
              tooltip: isFavorite ? 'In meiner Liste' : 'Meine Liste',
              icon: isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              active: isFavorite,
              onPressed: () => ref.read(favoritesProvider.notifier).toggle(channel),
            ),
            const SizedBox(width: 10),
            if (canResume) ...[
              Expanded(
                child: _PillButton(
                  label: 'Von vorne',
                  icon: Icons.replay_rounded,
                  onPressed: () => playFullscreen(context, ref, channel, widget.queue, fromStart: true),
                ),
              ),
              const SizedBox(width: 10),
            ],
            if (!isSeries && isDownloadable(channel)) ...[
              DownloadButton(
                channel: channel,
                title: tmdb?.title ?? cleanCatalogTitle(name.title).title,
                subtitle: year?.toString(),
                poster: poster,
              ),
              const SizedBox(width: 10),
            ],
            for (final option in [FeedbackChoice.like, FeedbackChoice.hide]) ...[
              Semantics(
                selected: feedback == option,
                child: _RoundButton(
                  key: ValueKey('feedback-${option.name}'),
                  tooltip: option == FeedbackChoice.like ? 'Gefällt mir' : 'Nicht interessiert',
                  icon: option == FeedbackChoice.like
                      ? (feedback == option ? Icons.thumb_up_rounded : Icons.thumb_up_outlined)
                      : Icons.not_interested_rounded,
                  active: feedback == option,
                  onPressed: () => toggleFeedback(option),
                ),
              ),
              if (option == FeedbackChoice.like) const SizedBox(width: 10),
            ],
          ],
        ),
        if (feedback != null) ...[
          const SizedBox(height: 10),
          Text(
            feedback == FeedbackChoice.hide
                ? 'Dieser Titel erscheint nicht in deinen Empfehlungen. Erneut auswählen zum Rückgängigmachen.'
                : 'Deine Auswahl verbessert deine Empfehlungen. Erneut auswählen zum Rückgängigmachen.',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ],
    );

    // --- Bewertungen --------------------------------------------------------------------
    final ratings = <_RatingItem>[
      if ((tmdb?.rating ?? 0) > 0) _RatingItem(_RatingSource.tmdb, '${(tmdb!.rating! * 10).round()} %'),
      if (matchedMovie != null && matchedMovie.rating > 0)
        _RatingItem(_RatingSource.imdb, _decimal(matchedMovie.rating)),
      if ((details.rating ?? 0) > 0) _RatingItem(_RatingSource.provider, _decimal(details.rating!)),
      if ((tmdb?.voteCount ?? 0) > 0) _RatingItem(_RatingSource.votes, _compactCount(tmdb!.voteCount)),
    ];

    final sections = <Widget>[
      if (detailsAsync.isLoading)
        const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      if (detailsAsync.hasError)
        Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 16),
          child: Row(
            children: [
              const Text('Details konnten nicht geladen werden.', style: TextStyle(color: AppColors.textSecondary)),
              TextButton(
                onPressed: () => ref.invalidate(mediaDetailsProvider(channel)),
                child: const Text('Erneut laden'),
              ),
            ],
          ),
        ),
      if (ratings.isNotEmpty) ...[
        _SectionLabel('Bewertungen', hPad: hPad),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad),
          child: Wrap(spacing: 28, runSpacing: 12, children: [for (final r in ratings) _RatingTile(item: r)]),
        ),
      ],
      if (tmdb != null && tmdb.cast.isNotEmpty) ...[
        _SectionLabel('Besetzung', hPad: hPad),
        CastRow(cast: tmdb.cast, horizontalPadding: hPad),
      ] else if (details.cast != null) ...[
        // Ohne TMDB wenigstens die Besetzung des Anbieters als Text.
        _SectionLabel('Besetzung', hPad: hPad),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Text(
              details.cast!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, height: 1.4),
            ),
          ),
        ),
      ],
      if (isSeries && seasons.isNotEmpty) ...[
        _SectionLabel('Folgen', hPad: hPad),
        if (seasons.length > 1)
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 8),
              itemCount: seasons.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => GlassPill(
                label: 'Staffel ${seasons[i].number}',
                selected: i == _seasonIndex.clamp(0, seasons.length - 1),
                onTap: () => setState(() => _seasonIndex = i),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 2, hPad, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SeasonDownloadButton(
              seasonNumber: season!.number,
              seriesTitle: tmdb?.title ?? cleanCatalogTitle(name.title).title,
              episodes: [
                for (final (i, e) in season.episodes.indexed)
                  (
                    channel: e.channel,
                    subtitle:
                        'S${season.number.toString().padLeft(2, '0')}E${(e.number > 0 ? e.number : i + 1).toString().padLeft(2, '0')} · ${e.channel.name}',
                  ),
              ],
            ),
          ),
        ),
        SizedBox(
          height: compact ? 128 : 140,
          child: ListView.separated(
            key: PageStorageKey('episodes-${season.number}'),
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: EdgeInsets.symmetric(horizontal: hPad),
            itemCount: season.episodes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _EpisodeCard(
              episode: season.episodes[i],
              seasonNumber: season.number,
              progress: library.resumeFor(season.episodes[i].channel),
              index: i,
              compact: compact,
              seriesTitle: name.title,
              onPlay: () => playFullscreen(context, ref, season.episodes[i].channel, season.channels),
            ),
          ),
        ),
      ],
      if (tmdb != null && tmdb.videos.isNotEmpty) ...[
        _SectionLabel('Videos', hPad: hPad),
        SizedBox(
          height: compact ? 150 : 172,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: EdgeInsets.symmetric(horizontal: hPad),
            itemCount: tmdb.videos.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _VideoCard(video: tmdb.videos[i], width: compact ? 180 : 210),
          ),
        ),
      ],
      if (tmdb?.collectionId != null)
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 28, hPad, 0),
          child: CollectionBanner(id: tmdb!.collectionId!, name: tmdb.collectionName ?? 'Filmreihe'),
        ),
      if (hasTmdbKey && tmdbAsync.isLoading)
        const Padding(padding: EdgeInsets.all(24), child: LinearProgressIndicator()),
      if (moreLikeThis.isNotEmpty) ...[
        _SectionLabel(recommended.length >= 3 ? 'Empfehlungen' : 'Mehr wie dieses', hPad: hPad),
        SizedBox(
          height: (compact ? 112 : 140) / PosterCard.aspectRatio + 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 4),
            itemCount: moreLikeThis.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => PosterCard(
              channel: moreLikeThis[i],
              queue: moreLikeThis,
              width: compact ? 112 : 140,
              onTap: () => Navigator.of(context).pushReplacement(DetailPage.route(moreLikeThis[i], moreLikeThis)),
            ),
          ),
        ),
      ],
      // Ohne TMDB-Schlüssel fehlen Logo, Besetzung und Videos – kurzer Hinweis, wie man sie bekommt.
      if (!hasTmdbKey) Padding(padding: EdgeInsets.fromLTRB(hPad, 32, hPad, 0), child: const TmdbHintCard()),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: _ScrollingBackdrop(
              controller: _scroll,
              fadeDistance: viewportHeight * 0.6,
              backdrop: backdrop,
              poster: poster,
              compact: compact,
            ),
          ),
          CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(
                child: ConstrainedBox(
                  // Ganzes Fenster hoch; längere Infos dürfen darüber hinaus wachsen.
                  constraints: BoxConstraints(minHeight: compact ? viewportHeight * 0.85 : viewportHeight - 24),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(hPad, compact ? 160 : 96, hPad, 28),
                      child: SizedBox(width: compact ? double.infinity : 400, child: info),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPad),
                  child: Divider(height: 1, color: Colors.white.withValues(alpha: 0.10)),
                ),
              ),
              SliverList.list(children: sections),
              const SliverToBoxAdapter(child: SizedBox(height: 48)),
            ],
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 14,
            right: compact ? 12 : 20,
            child: _RoundButton(
              key: const ValueKey('detail-close'),
              tooltip: 'Schließen',
              icon: Icons.close_rounded,
              size: 36,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    );
  }
}

String _compactCount(int n) =>
    n >= 1000 ? '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1).replaceAll('.', ',')} Tsd.' : '$n';

/// Titelbild, das beim Scrollen dunkler und unscharf wird.
class _ScrollingBackdrop extends StatelessWidget {
  const _ScrollingBackdrop({
    required this.controller,
    required this.fadeDistance,
    required this.backdrop,
    required this.poster,
    required this.compact,
  });

  final ScrollController controller;
  final double fadeDistance;
  final String? backdrop;
  final String? poster;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final image = RepaintBoundary(
      child: BackdropImage(backdrop: backdrop, poster: poster),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        ListenableBuilder(
          listenable: controller,
          builder: (context, child) {
            final offset = controller.hasClients ? controller.offset : 0.0;
            final t = (offset / fadeDistance.clamp(1, double.infinity)).clamp(0.0, 1.0);
            // In Stufen weichzeichnen, damit nicht jedes Scroll-Pixel einen neuen Filter baut.
            final sigma = (t * 6).round() * 4.0;
            final blurred = sigma == 0
                ? child!
                : ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp),
                    child: child,
                  );
            return Stack(
              fit: StackFit.expand,
              children: [
                blurred,
                ColoredBox(color: AppColors.background.withValues(alpha: 0.15 + 0.6 * t)),
              ],
            );
          },
          child: image,
        ),
        // Links dunkel für die Infospalte, unten in den Seitenhintergrund auslaufend.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.background.withValues(alpha: compact ? 0.35 : 0.92),
                Colors.transparent,
              ],
              stops: const [0.0, 0.62],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, AppColors.background.withValues(alpha: 0.9)],
              stops: const [0.45, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

/// Schriftzug-Logo von TMDB, sonst der Titel als Text.
class _TitleArt extends StatelessWidget {
  const _TitleArt({required this.logo, required this.title, required this.compact});

  final String? logo;
  final String title;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      title,
      style: (compact ? Theme.of(context).textTheme.headlineSmall : Theme.of(context).textTheme.displaySmall)?.copyWith(
        fontWeight: FontWeight.w800,
        height: 1.05,
        letterSpacing: -0.5,
      ),
    );
    if (logo == null) return text;
    return Semantics(
      label: title,
      header: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: compact ? 260 : 340, maxHeight: compact ? 90 : 120),
        child: MediaImage(
          url: logo,
          fit: BoxFit.contain,
          alignment: Alignment.bottomLeft,
          cacheWidth: 700,
          placeholder: Align(alignment: Alignment.bottomLeft, child: text),
        ),
      ),
    );
  }
}

class _RatingChip extends StatelessWidget {
  const _RatingChip({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(6)),
      child: Text(
        '★ ${rating.toStringAsFixed(1).replaceAll('.', ',')}',
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Weiche Glas-Pille; [primary] ist etwas heller.
class _PillButton extends StatefulWidget {
  const _PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = false,
    this.autofocus = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool autofocus;

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final lit = enabled && (_hovered || _focused);
    final base = widget.primary ? 0.16 : 0.08;
    return TvFocus(
      autofocus: widget.autofocus,
      onActivate: widget.onPressed,
      onFocusChange: (v) => setState(() => _focused = v),
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.label,
        excludeSemantics: true,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: lit ? base + 0.10 : base),
                borderRadius: BorderRadius.circular(21),
                border: Border.all(
                  color: _focused ? Colors.white : Colors.white.withValues(alpha: 0.10),
                  width: _focused ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 20, color: enabled ? Colors.white : AppColors.textSecondary),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: enabled ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Runder Glas-Knopf (Herz, Daumen, Schließen).
class _RoundButton extends StatefulWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.size = 42,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;
  final double size;

  @override
  State<_RoundButton> createState() => _RoundButtonState();
}

class _RoundButtonState extends State<_RoundButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final lit = _hovered || _focused;
    return Tooltip(
      message: widget.tooltip,
      child: TvFocus(
        onActivate: widget.onPressed,
        onFocusChange: (v) => setState(() => _focused = v),
        child: Semantics(
          button: true,
          label: widget.tooltip,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: widget.onPressed,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.active
                      ? Colors.white.withValues(alpha: 0.28)
                      : Colors.white.withValues(alpha: lit ? 0.18 : 0.08),
                  border: Border.all(
                    color: _focused ? Colors.white : Colors.white.withValues(alpha: 0.10),
                    width: _focused ? 2 : 1,
                  ),
                ),
                child: Icon(
                  widget.icon,
                  size: widget.size * 0.48,
                  color: widget.active && widget.icon == Icons.favorite_rounded ? AppColors.accent : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Handlung, bei langen Texten mit „Mehr“ aufklappbar.
class _ExpandablePlot extends StatefulWidget {
  const _ExpandablePlot({required this.text, required this.collapsedLines});

  final String text;
  final int collapsedLines;

  @override
  State<_ExpandablePlot> createState() => _ExpandablePlotState();
}

class _ExpandablePlotState extends State<_ExpandablePlot> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(height: 1.45, fontSize: 14, color: Color(0xFFE2E5EA));
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: widget.collapsedLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        painter.dispose();
        final text = Text(
          widget.text,
          style: style,
          maxLines: _expanded ? null : widget.collapsedLines,
          overflow: _expanded ? null : TextOverflow.ellipsis,
        );
        if (!overflows) return text;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            text,
            TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                alignment: Alignment.centerLeft,
                foregroundColor: Colors.white,
              ),
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? 'Weniger' : 'Mehr', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    );
  }
}

/// Kleine graue Abschnittsüberschrift in Großbuchstaben.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.hPad});

  final String text;
  final double hPad;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 26, hPad, 10),
      child: Semantics(
        header: true,
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.9,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

enum _RatingSource {
  tmdb('TMDB'),
  imdb('IMDb'),
  provider('Anbieter'),
  votes('Stimmen');

  const _RatingSource(this.label);
  final String label;
}

String _decimal(double value) => value.toStringAsFixed(1).replaceAll('.', ',');

class _RatingItem {
  const _RatingItem(this.source, this.value);

  final _RatingSource source;
  final String value;
}

/// Kleines Abzeichen der Bewertungsquelle (in der App gezeichnet, keine Bilddateien).
class _RatingLogo extends StatelessWidget {
  const _RatingLogo(this.source);

  final _RatingSource source;

  @override
  Widget build(BuildContext context) {
    Widget wordmark(String text, {required Gradient gradient, required Color color}) => Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(4)),
      child: Text(
        text,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: color, letterSpacing: 0.2, height: 1),
      ),
    );
    Widget symbol(IconData icon) => Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(4)),
      child: Icon(icon, size: 13, color: Colors.white),
    );
    return switch (source) {
      _RatingSource.tmdb => wordmark(
        'TMDB',
        gradient: const LinearGradient(colors: [Color(0xFF90CEA1), Color(0xFF01B4E4)]),
        color: const Color(0xFF0D253F),
      ),
      _RatingSource.imdb => wordmark(
        'IMDb',
        gradient: const LinearGradient(colors: [Color(0xFFF5C518), Color(0xFFF5C518)]),
        color: Colors.black,
      ),
      _RatingSource.provider => symbol(Icons.live_tv_rounded),
      _RatingSource.votes => symbol(Icons.people_alt_rounded),
    };
  }
}

class _RatingTile extends StatelessWidget {
  const _RatingTile({required this.item});

  final _RatingItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RatingLogo(item.source),
            // Schriftzug-Logos sprechen für sich; Symbole bekommen ihren Namen dazu.
            if (item.source == _RatingSource.provider || item.source == _RatingSource.votes) ...[
              const SizedBox(width: 6),
              Text(item.source.label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(item.value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ],
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

/// Waagerechte Folgenkarte: Vorschaubild links, Nummer, Titel, Handlung und Datum rechts.
class _EpisodeCard extends StatefulWidget {
  const _EpisodeCard({
    required this.episode,
    required this.seasonNumber,
    required this.progress,
    required this.index,
    required this.compact,
    required this.onPlay,
    required this.seriesTitle,
  });

  final Episode episode;
  final int seasonNumber;
  final String seriesTitle;
  final ResumePoint? progress;
  final int index;
  final bool compact;
  final VoidCallback onPlay;

  @override
  State<_EpisodeCard> createState() => _EpisodeCardState();
}

class _EpisodeCardState extends State<_EpisodeCard> {
  bool _hovered = false;
  bool _focused = false;

  bool get _lit => _hovered || _focused;

  static String _two(int n) => n.toString().padLeft(2, '0');

  static const _months = [
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember',
  ];

  @override
  Widget build(BuildContext context) {
    final episode = widget.episode;
    final number = episode.number > 0 ? episode.number : widget.index + 1;
    final compact = widget.compact;
    final thumbWidth = compact ? 120.0 : 196.0;
    final date = episode.airDate;
    final footer = [
      if (date != null) '${date.day}. ${_months[date.month - 1]} ${date.year}',
      ?episode.duration,
    ].join(' · ');

    return TvFocus(
      onActivate: widget.onPlay,
      onFocusChange: (v) => setState(() => _focused = v),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPlay,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: compact ? 300 : 470,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: _lit ? 0.10 : 0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _focused ? Colors.white : Colors.white.withValues(alpha: 0.06),
                width: _focused ? 2 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: SizedBox(
                    width: thumbWidth,
                    height: double.infinity,
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
                            opacity: _lit ? 1 : 0,
                            duration: const Duration(milliseconds: 150),
                            child: const Icon(
                              Icons.play_circle_fill_rounded,
                              size: 40,
                              color: Colors.white,
                              shadows: [Shadow(blurRadius: 10)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'S${_two(widget.seasonNumber)}E${_two(number)}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textSecondary,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          DownloadButton(
                            channel: episode.channel,
                            title: widget.seriesTitle,
                            subtitle: 'S${_two(widget.seasonNumber)}E${_two(number)} · ${episode.channel.name}',
                            poster: episode.channel.logo,
                            size: 28,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        episode.channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      if (episode.plot != null) ...[
                        const SizedBox(height: 4),
                        Expanded(
                          child: Text(
                            episode.plot!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
                          ),
                        ),
                      ] else
                        const Spacer(),
                      if (footer.isNotEmpty)
                        Text(
                          footer,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                        ),
                    ],
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

/// YouTube-Video (Trailer, Teaser …) mit Vorschaubild; öffnet YouTube.
class _VideoCard extends StatefulWidget {
  const _VideoCard({required this.video, required this.width});

  final TmdbVideo video;
  final double width;

  @override
  State<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<_VideoCard> {
  bool _hovered = false;
  bool _focused = false;

  void _open() => launchUrl(Uri.parse(widget.video.url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final lit = _hovered || _focused;
    return TvFocus(
      onActivate: _open,
      onFocusChange: (v) => setState(() => _focused = v),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: _open,
          child: SizedBox(
            width: widget.width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedScale(
                  scale: lit ? 1.03 : 1,
                  duration: const Duration(milliseconds: 150),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _focused ? Colors.white : Colors.transparent, width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            MediaImage(url: widget.video.thumbnail, cacheWidth: (widget.width * 2).round()),
                            Center(
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: lit ? 0.7 : 0.45),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
                                ),
                                child: const Icon(Icons.play_arrow_rounded, size: 22, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.video.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(widget.video.typeLabel, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
