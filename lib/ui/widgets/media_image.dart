import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../services/webos.dart';

import '../theme.dart';

/// Netzwerkbild mit sanftem Einblenden und ruhigem Platzhalter.
class MediaImage extends ConsumerWidget {
  const MediaImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.cacheWidth,
    this.padding = EdgeInsets.zero,
  });

  final String? url;
  final BoxFit fit;
  final Widget? placeholder;
  final int? cacheWidth;

  /// Abstand nur um das geladene Bild; der Platzhalter füllt die ganze Fläche.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = placeholder ?? const ColoredBox(color: AppColors.surfaceHigh);
    // Kill-Switch ohne VPN: auch Logos und Poster nicht laden.
    if (url == null || ref.watch(networkBlockedProvider)) return fallback;
    final userAgent = ref.watch(userAgentProvider);
    return Image.network(
      proxiedUrl(url!, userAgent: userAgent),
      headers: {'User-Agent': userAgent},
      fit: fit,
      cacheWidth: cacheWidth,
      // Der Fehler-Platzhalter läuft nicht durch frameBuilder, bleibt also ungepolstert.
      frameBuilder: (context, child, frame, wasSync) {
        final image = padding == EdgeInsets.zero ? child : Padding(padding: padding, child: child);
        if (wasSync) return image;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 250),
          child: frame == null ? fallback : image,
        );
      },
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

/// Hintergrund für Kopfbereiche: echtes Backdrop oder stark weichgezeichnetes Poster.
class BackdropImage extends StatelessWidget {
  const BackdropImage({super.key, required this.backdrop, required this.poster});

  final String? backdrop;
  final String? poster;

  @override
  Widget build(BuildContext context) {
    if (backdrop != null) {
      return MediaImage(
        url: backdrop,
        placeholder: _BlurredPoster(poster: poster),
      );
    }
    return _BlurredPoster(poster: poster);
  }
}

class _BlurredPoster extends StatelessWidget {
  const _BlurredPoster({required this.poster});

  final String? poster;

  @override
  Widget build(BuildContext context) {
    if (poster == null) {
      return const DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF2A1215), AppColors.background])),
      );
    }
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22, tileMode: TileMode.clamp),
        child: Transform.scale(scale: 1.2, child: MediaImage(url: poster, cacheWidth: 300)),
      ),
    );
  }
}

/// Ersatz-Poster für Einträge ohne Bild: dunkler Juwelenton-Verlauf (stabil je
/// Titel), dezentes Film-Symbol und sauber gesetzter Titel.
class TitlePlaceholder extends StatelessWidget {
  const TitlePlaceholder({super.key, required this.title, this.year, this.isSeries = false});

  final String title;
  final int? year;
  final bool isSeries;

  /// Smaragd, Saphir, Amethyst, Rubin, Topas, Petrol, Granat: jeweils hell → dunkel.
  static const _jewels = [
    (Color(0xFF0F5C4A), Color(0xFF06231D)),
    (Color(0xFF1B3F8C), Color(0xFF0A1633)),
    (Color(0xFF5B2A86), Color(0xFF1E0E2E)),
    (Color(0xFF8C1C3A), Color(0xFF2E0913)),
    (Color(0xFF8A5A12), Color(0xFF2B1B05)),
    (Color(0xFF0E5F74), Color(0xFF052129)),
    (Color(0xFF6E1F2B), Color(0xFF220A0E)),
  ];

  static (Color, Color) colorsFor(String title) {
    // Stabiler Hash (String.hashCode kann je nach Plattform abweichen).
    var hash = 0;
    for (final unit in title.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return _jewels[hash % _jewels.length];
  }

  @override
  Widget build(BuildContext context) {
    final (light, dark) = colorsFor(title);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 150.0;
        final scale = (width / 150).clamp(0.6, 2.0);
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [light, dark]),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Weiches Licht oben links, wie bei einem Kinoplakat.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.7, -0.8),
                    radius: 1.1,
                    colors: [Colors.white.withValues(alpha: 0.16), Colors.transparent],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(12 * scale),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isSeries ? Icons.video_library_rounded : Icons.movie_filter_rounded,
                      size: 26 * scale,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                    SizedBox(height: 10 * scale),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15 * scale,
                        height: 1.15,
                        letterSpacing: -0.2,
                        color: Colors.white,
                        shadows: const [Shadow(color: Color(0x66000000), blurRadius: 8)],
                      ),
                    ),
                    if (year != null) ...[
                      SizedBox(height: 8 * scale),
                      Container(width: 18 * scale, height: 1.5, color: Colors.white.withValues(alpha: 0.4)),
                      SizedBox(height: 8 * scale),
                      Text(
                        '$year',
                        style: TextStyle(
                          fontSize: 11 * scale,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
