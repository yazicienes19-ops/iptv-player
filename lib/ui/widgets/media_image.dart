import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';

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
    return Image.network(
      url!,
      headers: {'User-Agent': ref.watch(userAgentProvider)},
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

/// Platzhalter für Einträge ohne Poster: Name auf dezentem Verlauf.
class TitlePlaceholder extends StatelessWidget {
  const TitlePlaceholder({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF262A34), Color(0xFF14161B)],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 1.25),
          ),
        ),
      ),
    );
  }
}
