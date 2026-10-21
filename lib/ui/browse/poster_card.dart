import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/channel.dart';
import '../../providers/app_providers.dart';
import '../theme.dart';
import '../widgets/channel_views.dart';
import '../widgets/media_image.dart';

/// Hochformat-Poster für Filme und Serien, vergrößert sich beim Überfahren.
class PosterCard extends ConsumerStatefulWidget {
  const PosterCard({super.key, required this.channel, required this.queue, this.width = 140, this.onTap});

  static const aspectRatio = 2 / 3;

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

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    final isFavorite = ref.watch(favoritesProvider.select((f) => f.contains(channel)));
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
                scale: _hovered ? 1.05 : 1,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      if (_hovered) const BoxShadow(color: Colors.black87, blurRadius: 18, offset: Offset(0, 8)),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: PosterCard.aspectRatio,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          MediaImage(
                            url: channel.logo,
                            cacheWidth: (widget.width * dpr * 1.1).round(),
                            placeholder: TitlePlaceholder(title: channel.name),
                          ),
                          if (isFavorite)
                            const Positioned(
                              top: 6,
                              right: 6,
                              child: Icon(Icons.star_rounded, color: Colors.amber, size: 18,
                                  shadows: [Shadow(blurRadius: 6)]),
                            ),
                          if (_hovered)
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Color(0x99000000)],
                                ),
                              ),
                              child: Align(
                                alignment: Alignment(0, 0.85),
                                child: Icon(Icons.play_circle_fill_rounded, size: 34, color: Colors.white),
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
                channel.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: _hovered ? AppColors.textPrimary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
