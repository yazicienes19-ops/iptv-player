import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/channel.dart';
import '../../models/tmdb.dart';
import '../../providers/app_providers.dart';
import '../browse/poster_card.dart';
import '../settings/settings_page.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import '../widgets/media_image.dart';
import '../widgets/tv_focus.dart';
import 'collection_page.dart';
import 'detail_page.dart';
import 'person_page.dart';

/// Überschrift für TMDB-Abschnitte.
class TmdbSectionTitle extends StatelessWidget {
  const TmdbSectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        ),
        ?trailing,
      ],
    );
  }
}

/// Darsteller als runde Fotos mit Name und Rolle; Klick öffnet die Person.
class CastRow extends StatelessWidget {
  const CastRow({super.key, required this.cast, required this.horizontalPadding});

  final List<TmdbCast> cast;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 178,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 6),
        itemCount: cast.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, i) => _CastTile(person: cast[i]),
      ),
    );
  }
}

class _CastTile extends StatefulWidget {
  const _CastTile({required this.person});

  final TmdbCast person;

  @override
  State<_CastTile> createState() => _CastTileState();
}

class _CastTileState extends State<_CastTile> {
  bool _hovered = false;
  bool _focused = false;

  void _open() => Navigator.of(context).push(PersonPage.route(widget.person.id, widget.person.name));

  @override
  Widget build(BuildContext context) {
    final lit = _hovered || _focused;
    final person = widget.person;
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
            width: 104,
            child: Column(
              children: [
                AnimatedScale(
                  scale: lit ? 1.06 : 1,
                  duration: const Duration(milliseconds: 160),
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _focused ? Colors.white : Colors.white.withValues(alpha: lit ? 0.3 : 0.1),
                        width: _focused ? 2.5 : 1,
                      ),
                      boxShadow: [if (lit) const BoxShadow(color: Color(0x88000000), blurRadius: 14)],
                    ),
                    child: ClipOval(
                      child: MediaImage(
                        url: person.photo,
                        cacheWidth: 220,
                        placeholder: _Initials(name: person.name),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  person.name,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, height: 1.2),
                ),
                if (person.character != null)
                  Text(
                    person.character!,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final letters = name.split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join();
    return ColoredBox(
      color: AppColors.surfaceHigh,
      child: Center(
        child: Text(
          letters,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

/// „Teil der Reihe: Harry Potter“ – öffnet die Reihen-Seite.
class CollectionBanner extends ConsumerWidget {
  const CollectionBanner({super.key, required this.id, required this.name});

  final int id;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collection = ref.watch(tmdbCollectionProvider(id)).value;
    final index = ref.watch(playlistTitleIndexProvider);
    final parts = collection?.parts ?? const <TmdbRef>[];
    final available = parts.where((p) => index.find(p) != null).length;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(CollectionPage.route(id, name)),
        child: Ink(
          height: 150,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                MediaImage(url: collection?.backdrop),
                const DecoratedBox(
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xF00A0C10), Color(0x660A0C10)])),
                ),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TEIL DER REIHE',
                              style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 2,
                                fontWeight: FontWeight.w800,
                                color: AppColors.accent,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              collection?.name ?? name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            if (parts.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                '${parts.length} Filme  ·  $available in deiner Playlist',
                                style: const TextStyle(color: AppColors.textSecondary),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, size: 32),
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

/// Hinweis, solange kein TMDB-Schlüssel hinterlegt ist.
class TmdbHintCard extends StatelessWidget {
  const TmdbHintCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 16,
      tint: const Color(0x14FFFFFF),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded, color: AppColors.accent),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Darsteller, Trailer, Reihen und Empfehlungen gibt es mit einem kostenlosen TMDB-Schlüssel.',
              style: TextStyle(height: 1.4),
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: () => Navigator.of(context).push(SettingsPage.route()),
            child: const Text('Einrichten'),
          ),
        ],
      ),
    );
  }
}

/// Poster eines TMDB-Titels; abspielbar, wenn er in der Playlist steckt,
/// sonst ausgegraut mit Hinweis. Optional mit Nummer (Reihen-Seite).
class TmdbPosterTile extends ConsumerWidget {
  const TmdbPosterTile({super.key, required this.item, this.number, this.width = 150, this.subtitle});

  final TmdbRef item;
  final int? number;
  final double width;
  final String? subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final match = ref.watch(playlistTitleIndexProvider).find(item);
    final image = Stack(
      fit: StackFit.expand,
      children: [
        MediaImage(
          url: item.poster,
          cacheWidth: (width * 2).round(),
          placeholder: TitlePlaceholder(title: item.title, year: item.year, isSeries: item.type == TmdbMediaType.tv),
        ),
        if (match == null)
          Container(
            color: const Color(0xA60A0C10),
            alignment: Alignment.bottomCenter,
            padding: const EdgeInsets.all(8),
            child: const Text(
              'Nicht in deiner Playlist',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
            ),
          ),
        if (number != null)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(6)),
              child: Text('$number', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            ),
          ),
      ],
    );

    if (match != null) {
      // Verfügbar: die normale Poster-Karte (Hover, Fokus, Detailseite).
      return Stack(
        children: [
          PosterCard(
            channel: match,
            queue: [match],
            width: width,
            onTap: () => Navigator.of(context).push(DetailPage.route(match, [match])),
          ),
          if (number != null)
            Positioned(
              top: 14,
              left: 8,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(6)),
                  child: Text('$number', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                ),
              ),
            ),
        ],
      );
    }

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(PosterCard.radius),
              child: AspectRatio(aspectRatio: PosterCard.aspectRatio, child: image),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            [item.title, if (item.year != null) '${item.year}'].join('  ·  '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// Waagerechte Reihe aus TMDB-Titeln.
class TmdbRow extends StatelessWidget {
  const TmdbRow({super.key, required this.items, required this.horizontalPadding, this.width = 150});

  final List<TmdbRef> items;
  final double horizontalPadding;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: width / PosterCard.aspectRatio + 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) => TmdbPosterTile(item: items[i], width: width),
      ),
    );
  }
}

/// Playlist-Einträge zu TMDB-Empfehlungen (nur verfügbare).
List<Channel> availableRecommendations(WidgetRef ref, List<TmdbRef> refs) {
  final index = ref.watch(playlistTitleIndexProvider);
  return [for (final r in refs) ?index.find(r)];
}
