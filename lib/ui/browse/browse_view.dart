import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/catalog.dart';
import '../../models/category.dart';
import '../../models/channel.dart';
import '../../models/channel_name.dart';
import '../../models/content_type.dart';
import '../../providers/app_providers.dart';
import '../detail/detail_page.dart';
import '../theme.dart';
import '../widgets/channel_views.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/media_image.dart';
import 'poster_card.dart';

/// Filme oder Serien im Stil von Apple TV+/Netflix: Kino-Banner, darunter
/// Glas-Chips für Kategorien und Poster-Reihen. Mit Suche oder gewählter
/// Kategorie wird daraus ein Raster.
class BrowseView extends ConsumerWidget {
  const BrowseView({super.key, required this.type, this.compact = false, this.leftInset = 0});

  final ContentType type;
  final bool compact;

  /// Breite der darüber schwebenden Glas-Seitenleiste; Banner laufen darunter durch.
  final double leftInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = AppSection.values.firstWhere((s) => s.contentType == type);
    final query = ref.watch(searchQueryProvider(section)).trim();
    final category = ref.watch(selectedCategoryProvider(type));
    final filtering = query.isNotEmpty || category != null;
    final hPad = compact ? 16.0 : 40.0;
    final rows = ref.watch(channelsByCategoryProvider(type));

    return rows.when(
      loading: () => const AsyncStateView.loading(),
      error: (e, _) => AsyncStateView.error(
        error: e,
        onRetry: () {
          ref.invalidate(m3uPlaylistProvider);
          ref.invalidate(catalogProvider(type));
        },
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return EmptyView(icon: Icons.movie_outlined, message: 'Keine ${type.label} für diese Sprache.');
        }
        return Stack(
          children: [
            CustomScrollView(
              slivers: [
                if (!filtering)
                  SliverToBoxAdapter(
                    child: HeroCarousel(
                      items: pickHeroItems(rows),
                      compact: compact,
                      leftInset: leftInset,
                      horizontalPadding: hPad,
                    ),
                  )
                else
                  SliverToBoxAdapter(child: SizedBox(height: compact ? 72 : 96)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 18),
                    child: CategoryPills(type: type, horizontalPadding: hPad, leadingInset: leftInset),
                  ),
                ),
                if (filtering)
                  ...filteredGridSlivers(
                    context,
                    ref,
                    type: type,
                    padding: EdgeInsets.only(left: leftInset + hPad, right: hPad),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.only(bottom: 40),
                    sliver: SliverList.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, i) => CategoryRow(
                        category: rows[i].$1,
                        channels: rows[i].$2,
                        horizontalPadding: hPad,
                        leftInset: leftInset,
                        posterWidth: compact ? 112 : 158,
                      ),
                    ),
                  ),
              ],
            ),
            // Suche schwebt oben rechts über dem Banner.
            Positioned(
              top: compact ? 12 : 24,
              right: hPad,
              left: compact ? hPad + leftInset : null,
              child: SizedBox(
                width: compact ? null : 320,
                child: GlassSearch(section: section),
              ),
            ),
          ],
        );
      },
    );
  }
}

class GlassSearch extends StatelessWidget {
  const GlassSearch({super.key, required this.section});

  final AppSection section;

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 12,
      tint: const Color(0x8A0E1117),
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(fillColor: Colors.transparent),
        ),
        child: SearchField(section: section),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Banner
// ---------------------------------------------------------------------------

/// Bevorzugt aktuelle Kategorien (Neuerscheinungen, 2026/2025, 4K, Top) und
/// nur Einträge mit Bild; höchstens fünf, täglich anders gemischt.
List<Channel> pickHeroItems(List<(Category, List<Channel>)> rows, {int max = 5}) {
  final now = DateTime.now().year;
  int score(Category c) {
    final n = c.name.toLowerCase();
    if (n.contains('neuerscheinung') || n.contains('$now')) return 4;
    if (n.contains('${now - 1}') || n.contains('neu') || n.contains('new')) return 3;
    if (n.contains('4k') || n.contains('uhd') || n.contains('top') || n.contains('trend') || n.contains('kino')) {
      return 2;
    }
    return 0;
  }

  final ranked = [...rows]..sort((a, b) => score(b.$1).compareTo(score(a.$1)));
  final candidates = <Channel>[];
  for (final (_, channels) in ranked.take(6)) {
    candidates.addAll(channels.take(12).where((c) => c.logo != null && (c.releaseYear ?? now) >= now - 2));
  }
  if (candidates.isEmpty) {
    for (final (_, channels) in ranked.take(6)) {
      candidates.addAll(channels.take(12).where((c) => c.logo != null));
    }
  }
  if (candidates.isEmpty) return [rows.first.$2.first];
  final day = DateTime.now().difference(DateTime(2024)).inDays;
  final start = day % candidates.length;
  return {for (var i = 0; i < candidates.length && i < max; i++) candidates[(start + i * 7) % candidates.length]}
      .toList();
}

/// Wechselt alle 8 Sekunden sanft zum nächsten Titel; Punkte zum Springen.
class HeroCarousel extends StatefulWidget {
  const HeroCarousel({
    super.key,
    required this.items,
    required this.compact,
    required this.leftInset,
    required this.horizontalPadding,
  });

  final List<Channel> items;
  final bool compact;
  final double leftInset;
  final double horizontalPadding;

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  void _restart() {
    _timer?.cancel();
    if (widget.items.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) setState(() => _index = (_index + 1) % widget.items.length);
    });
  }

  @override
  void didUpdateWidget(HeroCarousel old) {
    super.didUpdateWidget(old);
    if (_index >= widget.items.length) _index = 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.items[_index];
    return SizedBox(
      height: widget.compact ? 470 : 420,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 700),
            child: HeroBanner(
              key: ValueKey(channel.id),
              channel: channel,
              compact: widget.compact,
              leftInset: widget.leftInset,
              horizontalPadding: widget.horizontalPadding,
            ),
          ),
          if (widget.items.length > 1)
            Positioned(
              right: widget.horizontalPadding,
              bottom: 22,
              child: Row(
                children: [
                  for (var i = 0; i < widget.items.length; i++)
                    GestureDetector(
                      onTap: () {
                        setState(() => _index = i);
                        _restart();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.only(left: 6),
                        width: i == _index ? 22 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: i == _index ? 0.9 : 0.35),
                          borderRadius: BorderRadius.circular(4),
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

class HeroBanner extends ConsumerWidget {
  const HeroBanner({
    super.key,
    required this.channel,
    required this.compact,
    required this.horizontalPadding,
    this.leftInset = 0,
  });

  final Channel channel;
  final bool compact;
  final double horizontalPadding;
  final double leftInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(mediaDetailsProvider(channel)).value;
    final name = channel.display;
    final textTheme = Theme.of(context).textTheme;
    final seasons = details?.seasons ?? const <Season>[];
    final category = _categoryName(ref);
    final year = name.year ?? int.tryParse(details?.year ?? '');
    final isFavorite = ref.watch(favoritesProvider.select((f) => f.contains(channel)));
    final now = DateTime.now().year;
    final isNew = (year != null && year >= now - 1) || (category?.toLowerCase().contains('neuerscheinung') ?? false);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Ambient-Glow: stark weichgezeichnetes, abgedunkeltes Poster bzw. echtes Backdrop.
        if (details?.backdrop != null) MediaImage(url: details!.backdrop) else _AmbientGlow(poster: channel.logo),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xF20A0C10), Color(0xA60A0C10), Color(0x330A0C10)],
              stops: [0, 0.5, 1],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x660A0C10), Color(0x000A0C10), Color(0xFF0A0C10)],
              stops: [0, 0.35, 1],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(leftInset + horizontalPadding, compact ? 72 : 40, horizontalPadding, 40),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (compact) ...[
                      Center(child: _HeroPoster(channel: channel, width: 150)),
                      const SizedBox(height: 18),
                    ],
                    Text(
                      channel.type == ContentType.series ? 'SERIE' : 'FILM',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.4,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: Text(
                        name.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: (compact ? textTheme.headlineMedium : textTheme.displaySmall)?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                          letterSpacing: -0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (isNew) const HeroPill(text: 'NEU', accent: true),
                        for (final q in name.qualities.take(2)) HeroPill(text: q.label),
                        if (year != null) HeroPill(text: '$year'),
                        if (category != null) HeroPill(text: category),
                        if (seasons.isNotEmpty) HeroPill(text: seasonSummary(seasons)),
                        if (details?.rating != null && details!.rating! > 0)
                          HeroPill(text: '★ ${details.rating!.toStringAsFixed(1)}'),
                      ],
                    ),
                    if (!compact && details?.plot != null) ...[
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Text(
                          details!.plot!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(height: 1.45, color: Color(0xFFD0D3D9)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        _GlowButton(
                          label: 'Abspielen',
                          icon: Icons.play_arrow_rounded,
                          onPressed: () => _play(context, ref, seasons),
                        ),
                        const SizedBox(width: 12),
                        _GlassButton(
                          label: isFavorite ? 'In meiner Liste' : 'Meine Liste',
                          icon: isFavorite ? Icons.check_rounded : Icons.add_rounded,
                          onPressed: () => ref.read(favoritesProvider.notifier).toggle(channel),
                        ),
                        const SizedBox(width: 10),
                        _GlassButton(
                          icon: Icons.info_outline_rounded,
                          tooltip: 'Mehr Infos',
                          onPressed: () => Navigator.of(context).push(DetailPage.route(channel, [channel])),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!compact && details?.backdrop == null && channel.logo != null) ...[
                const SizedBox(width: 32),
                _HeroPoster(channel: channel, height: 300),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Filme direkt abspielen; Serien ab Staffel 1, Folge 1 (sonst Detailseite).
  void _play(BuildContext context, WidgetRef ref, List<Season> seasons) {
    if (channel.isPlayable) return playFullscreen(context, ref, channel, [channel]);
    final first = seasons.firstOrNull;
    if (first != null && first.episodes.isNotEmpty) {
      return playFullscreen(context, ref, first.episodes.first.channel, first.channels);
    }
    openChannel(context, ref, channel, [channel]);
  }

  String? _categoryName(WidgetRef ref) {
    final categories = ref.watch(catalogProvider(channel.type)).value?.categories ?? const <Category>[];
    for (final c in categories) {
      if (c.id == channel.categoryId) return c.name;
    }
    return null;
  }
}

/// Metadaten-Pill im Banner (NEU, 4K, Jahr, Kategorie …).
class HeroPill extends StatelessWidget {
  const HeroPill({super.key, required this.text, this.accent = false});

  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent ? AppColors.accent : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent ? Colors.transparent : Colors.white.withValues(alpha: 0.14)),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(
          fontSize: 12,
          fontWeight: accent ? FontWeight.w800 : FontWeight.w600,
          letterSpacing: accent ? 1 : 0.2,
          color: Colors.white,
          height: 1.2,
        ),
      ),
    );
  }
}

/// Leuchtender Haupt-Knopf mit rotem Schein.
class _GlowButton extends StatefulWidget {
  const _GlowButton({required this.label, required this.icon, required this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<_GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<_GlowButton> {
  bool _lit = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: _lit ? 0.75 : 0.45),
            blurRadius: _lit ? 30 : 20,
            spreadRadius: _lit ? 1 : 0,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: FilledButton.icon(
        onHover: (v) => setState(() => _lit = v),
        onFocusChange: (v) => setState(() => _lit = v),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 17),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, letterSpacing: 0.2),
        ),
        onPressed: widget.onPressed,
        icon: Icon(widget.icon, size: 24),
        label: Text(widget.label),
      ),
    );
  }
}

/// Glas-Knopf (Meine Liste, Infos).
class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.icon, required this.onPressed, this.label, this.tooltip});

  final IconData icon;
  final VoidCallback onPressed;
  final String? label;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      backgroundColor: Colors.white.withValues(alpha: 0.12),
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
      ),
      padding: EdgeInsets.symmetric(horizontal: label == null ? 16 : 22, vertical: 17),
      textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
    );
    final button = label == null
        ? FilledButton(style: style, onPressed: onPressed, child: Icon(icon, size: 22))
        : FilledButton.icon(style: style, onPressed: onPressed, icon: Icon(icon, size: 22), label: Text(label!));
    return Glass(
      radius: 14,
      blur: 16,
      tint: Colors.transparent,
      border: false,
      child: tooltip == null ? button : Tooltip(message: tooltip, child: button),
    );
  }
}

class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow({required this.poster});

  final String? poster;

  @override
  Widget build(BuildContext context) {
    if (poster == null) return const ColoredBox(color: AppColors.background);
    return ColoredBox(
      color: AppColors.background,
      child: Opacity(
        opacity: 0.55,
        child: ClipRect(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50, tileMode: TileMode.decal),
            child: Transform.scale(scale: 1.35, child: MediaImage(url: poster, cacheWidth: 240)),
          ),
        ),
      ),
    );
  }
}

class _HeroPoster extends StatelessWidget {
  const _HeroPoster({required this.channel, this.width, this.height});

  final Channel channel;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0xCC000000), blurRadius: 40, offset: Offset(0, 18))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: width,
          height: height,
          child: AspectRatio(
            aspectRatio: PosterCard.aspectRatio,
            child: MediaImage(
              url: channel.logo,
              placeholder: TitlePlaceholder(
                title: channel.display.title,
                year: channel.display.year,
                isSeries: channel.type == ContentType.series,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kleines Badge für Jahr oder Staffel-Anzahl.
class MetaBadge extends StatelessWidget {
  const MetaBadge({super.key, required this.text, this.filled = true});

  final String text;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.white.withValues(alpha: filled ? 0 : 0.35)),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.3, height: 1.2),
      ),
    );
  }
}

/// „3 Staffeln • 19 Folgen“
String seasonSummary(List<Season> seasons) {
  final episodes = seasons.fold<int>(0, (sum, s) => sum + s.episodes.length);
  final s = seasons.length == 1 ? '1 Staffel' : '${seasons.length} Staffeln';
  return '$s • $episodes ${episodes == 1 ? 'Folge' : 'Folgen'}';
}

// ---------------------------------------------------------------------------
// Reihen und Raster
// ---------------------------------------------------------------------------

/// Eine waagerechte Poster-Reihe mit Überschrift und „Alle anzeigen“.
class CategoryRow extends ConsumerWidget {
  const CategoryRow({
    super.key,
    required this.channels,
    required this.horizontalPadding,
    required this.posterWidth,
    this.category,
    this.leftInset = 0,
    this.title,
  });

  static const maxItems = 30;

  final Category? category;
  final List<Channel> channels;
  final double horizontalPadding;
  final double posterWidth;
  final double leftInset;

  /// Überschrift, wenn die Reihe zu keiner Kategorie gehört (z. B. auf der Startseite).
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = channels.take(maxItems).toList();
    final posterHeight = posterWidth / PosterCard.aspectRatio;
    final left = leftInset + horizontalPadding;
    final category = this.category;

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
                    title ?? category?.name ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
                  ),
                ),
                if (category != null)
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
            height: posterHeight + 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.only(left: left, right: horizontalPadding, top: 8, bottom: 4),
              clipBehavior: Clip.none,
              itemCount: visible.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, i) => PosterCard(channel: visible[i], queue: channels, width: posterWidth),
            ),
          ),
        ],
      ),
    );
  }
}

/// Raster für gewählte Kategorie oder Suche.
List<Widget> filteredGridSlivers(
  BuildContext context,
  WidgetRef ref, {
  required ContentType type,
  required EdgeInsets padding,
}) {
  final channels = ref.watch(visibleChannelsProvider(type));
  final category = ref.watch(selectedCategoryProvider(type));
  return [
    if (category != null)
      SliverToBoxAdapter(
        child: Padding(
          padding: padding.copyWith(bottom: 12),
          child: Text(
            category.name,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
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
            padding: padding.copyWith(top: 4, bottom: 40),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 170,
                // Poster 2:3 plus Titelzeile.
                childAspectRatio: 0.56,
                mainAxisSpacing: 18,
                crossAxisSpacing: 16,
              ),
              itemCount: list.length,
              itemBuilder: (context, i) => LayoutBuilder(
                builder: (context, c) => PosterCard(channel: list[i], queue: list, width: c.maxWidth),
              ),
            ),
          ),
      ],
    ),
  ];
}
