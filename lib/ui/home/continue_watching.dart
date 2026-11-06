import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/catalog.dart';
import '../../models/channel_name.dart';
import '../../providers/app_providers.dart';
import '../../services/personal_library.dart';
import '../detail/detail_page.dart';
import '../theme.dart';
import '../widgets/channel_views.dart';
import '../widgets/media_image.dart';
import '../widgets/tv_focus.dart';

/// „Weiterschauen“ wie bei Streamingdiensten: breite Karten mit Fortschritt,
/// ein Klick spielt an der gemerkten Stelle bzw. mit der nächsten Folge weiter.
class ContinueWatchingRow extends ConsumerWidget {
  const ContinueWatchingRow({super.key, required this.horizontalPadding, this.leftInset = 0, this.compact = false});

  final double horizontalPadding;
  final double leftInset;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(continueWatchingProvider);
    if (items.isEmpty) return const SizedBox.shrink();
    final left = leftInset + horizontalPadding;
    final width = compact ? 250.0 : 320.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(left, 0, horizontalPadding, 2),
            child: Text(
              'Weiterschauen',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4),
            ),
          ),
          SizedBox(
            height: width * 9 / 16 + 70,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.only(left: left, right: horizontalPadding, top: 8, bottom: 4),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 16),
              itemBuilder: (context, i) => ContinueCard(item: items[i], width: width),
            ),
          ),
        ],
      ),
    );
  }
}

class ContinueCard extends ConsumerStatefulWidget {
  const ContinueCard({super.key, required this.item, required this.width});

  final ContinueItem item;
  final double width;

  @override
  ConsumerState<ContinueCard> createState() => _ContinueCardState();
}

class _ContinueCardState extends ConsumerState<ContinueCard> {
  bool _hovered = false;
  bool _focused = false;
  bool _starting = false;

  void _openDetails() {
    final title = widget.item.title;
    Navigator.of(context).push(DetailPage.route(title, [title]));
  }

  /// Film: an der Stelle weiter. Serie: angefangene oder nächste Folge.
  Future<void> _play() async {
    final title = widget.item.title;
    if (!widget.item.isSeries) {
      playFullscreen(context, ref, title, [title]);
      return;
    }
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final details = await ref.read(mediaDetailsProvider(title).future);
      if (!mounted) return;
      final next = continueEpisode(ref.read(personalLibraryProvider), details.seasons);
      if (next == null) {
        _openDetails();
      } else {
        playFullscreen(context, ref, next.episode.channel, next.season.channels);
      }
    } catch (_) {
      if (mounted) _openDetails();
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final title = item.title;
    final lit = _hovered || _focused;
    // Details liefern Hintergrundbild und bei Serien die nächste Folge.
    final details = ref.watch(mediaDetailsProvider(title)).value ?? MediaDetails.empty;
    final library = ref.watch(personalLibraryProvider);
    final tmdb = ref.watch(tmdbTitleProvider(title)).value;
    final next = item.isSeries ? continueEpisode(library, details.seasons) : null;
    final point = item.isSeries ? next?.point : item.point;
    final backdrop = details.backdrop ?? tmdb?.backdrop;

    final String headline;
    final String? subline;
    if (item.isSeries) {
      if (next != null) {
        final number = next.episode.number > 0 ? next.episode.number : next.season.episodes.indexOf(next.episode) + 1;
        headline = 'S${next.season.number} F$number ${next.episode.channel.name}';
      } else {
        headline = title.display.title;
      }
      subline = next == null ? null : title.display.title;
    } else {
      headline = title.display.title;
      subline = point == null ? null : remainingLabel(point.remaining);
    }

    return TvFocus(
      onActivate: _play,
      onSecondary: _openDetails,
      onFocusChange: (v) => setState(() => _focused = v),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: _play,
          child: SizedBox(
            width: widget.width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedScale(
                  scale: lit ? 1.03 : 1,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _focused ? Colors.white : Colors.transparent, width: 2),
                      boxShadow: [if (lit) const BoxShadow(color: Color(0x99000000), blurRadius: 18)],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (backdrop != null)
                              MediaImage(url: backdrop, cacheWidth: (widget.width * 2).round())
                            else
                              // Ohne Querformat-Bild: Poster unscharf als Fläche, scharf in der Mitte.
                              Stack(
                                fit: StackFit.expand,
                                children: [
                                  BackdropImage(backdrop: null, poster: title.logo),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    child: MediaImage(url: title.logo, fit: BoxFit.contain),
                                  ),
                                ],
                              ),
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Color(0xAA000000)],
                                  stops: [0.55, 1],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 10,
                              bottom: 12,
                              child: _starting
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                    )
                                  : Icon(
                                      Icons.play_arrow_rounded,
                                      size: lit ? 36 : 32,
                                      color: Colors.white,
                                      shadows: const [Shadow(blurRadius: 8)],
                                    ),
                            ),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: AnimatedOpacity(
                                opacity: lit ? 1 : 0,
                                duration: const Duration(milliseconds: 150),
                                child: IconButton.filled(
                                  tooltip: 'Details',
                                  style: IconButton.styleFrom(
                                    backgroundColor: const Color(0x99000000),
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(32, 32),
                                    padding: EdgeInsets.zero,
                                  ),
                                  iconSize: 18,
                                  onPressed: _openDetails,
                                  icon: const Icon(Icons.info_outline_rounded),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: LinearProgressIndicator(
                                value: point?.fraction ?? 0,
                                minHeight: 4,
                                backgroundColor: const Color(0x55FFFFFF),
                                valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  headline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                ),
                if (subline != null)
                  Text(
                    subline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
