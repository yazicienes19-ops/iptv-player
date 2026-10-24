import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/channel.dart';
import '../../models/channel_name.dart';
import '../../models/content_type.dart';
import '../../providers/app_providers.dart';
import '../../providers/imdb_providers.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import 'browse_view.dart';
import '../widgets/channel_views.dart';
import '../widgets/media_image.dart';
import '../widgets/tv_focus.dart';

/// Hochformat-Poster für Filme und Serien, vergrößert sich beim Überfahren.
class PosterCard extends ConsumerStatefulWidget {
  const PosterCard({super.key, required this.channel, required this.queue, this.width = 140, this.onTap});

  static const aspectRatio = 2 / 3;
  static const radius = 12.0;

  final Channel channel;
  final List<Channel> queue;
  final double width;

  /// Ersetzt das Standardverhalten (Detailseite öffnen).
  final VoidCallback? onTap;

  @override
  ConsumerState<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends ConsumerState<PosterCard> {
  bool _hovered = false;
  bool _focused = false;

  /// Maus darüber oder per Fernbedienung/Tastatur fokussiert.
  bool get _lit => _hovered || _focused;

  @override
  Widget build(BuildContext context) => TvFocus(
    onActivate: widget.onTap ?? () => openChannel(context, ref, widget.channel, widget.queue),
    onFocusChange: (v) => setState(() => _focused = v),
    child: _buildTile(context),
  );

  Widget _buildTile(BuildContext context) {
    final channel = widget.channel;
    final isFavorite = ref.watch(favoritesProvider.select((f) => f.contains(channel)));
    final name = channel.display;
    final imdb = ref.watch(imdbCatalogProvider).value?.match(channel);
    // M3U-Serien: Staffeln stammen aus der Zusammenfassung beim Einlesen.
    final seasons = channel.isPlayable
        ? null
        : ref.watch(catalogProvider(ContentType.series).select((c) => c.value?.seriesSeasons[channel.id]));
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap ?? () => openChannel(context, ref, channel, widget.queue),
        child: SizedBox(
          width: widget.width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedScale(
                scale: _lit ? 1.035 : 1,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  // Feine Lichtkante; bei Fokus (Fernbedienung) kräftig weiß.
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(PosterCard.radius),
                    border: Border.all(
                      color: _focused ? Colors.white : Colors.white.withValues(alpha: _lit ? 0.3 : 0.08),
                      width: _focused ? 2.5 : 1,
                    ),
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(PosterCard.radius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: _lit ? 0.5 : 0.2),
                        blurRadius: _lit ? 24 : 12,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(PosterCard.radius),
                    child: AspectRatio(
                      aspectRatio: PosterCard.aspectRatio,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          MediaImage(
                            url: channel.logo,
                            cacheWidth: (widget.width * dpr * 1.1).round(),
                            placeholder: TitlePlaceholder(
                              title: channel.display.title,
                              year: channel.display.year,
                              isSeries: channel.type == ContentType.series,
                            ),
                          ),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.center,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Color(0x66090B10)],
                              ),
                            ),
                          ),
                          if (isFavorite)
                            const Positioned(
                              top: 8,
                              right: 8,
                              child: DecoratedBox(
                                decoration: BoxDecoration(color: Color(0xD9090B10), shape: BoxShape.circle),
                                child: Padding(
                                  padding: EdgeInsets.all(5),
                                  child: Icon(Icons.check_rounded, color: Colors.white, size: 15),
                                ),
                              ),
                            ),
                          if (imdb != null)
                            Positioned(
                              top: 8,
                              left: 8,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(0xF0E6B91E),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                  child: Text(
                                    'IMDb ${imdb.rating.toStringAsFixed(1)}',
                                    style: const TextStyle(
                                      color: Color(0xFF171717),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (seasons != null && seasons.isNotEmpty)
                            Positioned(
                              left: 6,
                              right: 6,
                              bottom: 6,
                              child: Align(
                                alignment: Alignment.bottomLeft,
                                child: Glass(
                                  radius: 6,
                                  blur: 12,
                                  tint: const Color(0x99000000),
                                  border: false,
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                  child: Text(
                                    seasonSummary(seasons),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, height: 1.2),
                                  ),
                                ),
                              ),
                            ),
                          if (_lit)
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Color(0x99000000)],
                                ),
                              ),
                              child: Align(
                                alignment: Alignment.center,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(color: Color(0xF2FFFFFF), shape: BoxShape.circle),
                                  child: Padding(
                                    padding: EdgeInsets.all(10),
                                    child: Icon(Icons.arrow_forward_rounded, size: 24, color: AppColors.background),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _lit ? FontWeight.w700 : FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (name.year != null)
                    Text(
                      ' ${name.year}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
