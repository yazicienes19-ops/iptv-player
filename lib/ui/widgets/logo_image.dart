import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../services/webos.dart';
import '../theme.dart';
import 'channel_views.dart';
import 'media_image.dart';

/// Wie ein Logo auf der dunklen Kachel wirkt.
enum LogoTone {
  /// Gut sichtbar (hell, farbig oder mit eigenem Hintergrund).
  normal,

  /// Dunkel auf durchsichtigem Grund: braucht eine helle Kachel.
  dark,

  /// Leer oder fast unsichtbar: Monogramm statt Bild.
  empty,
}

/// Wertet Logos einmal klein aus und merkt sich das Ergebnis je Adresse.
abstract final class LogoAnalyzer {
  static const _size = 48;
  static final _results = <String, LogoTone>{};
  static final _pending = <String, Future<LogoTone>>{};

  static LogoTone? cached(String url) => _results[url];

  static Future<LogoTone> analyze(String url, String userAgent) =>
      _pending[url] ??= _run(url, userAgent).catchError((_) => LogoTone.normal).then((tone) => _results[url] = tone);

  static Future<LogoTone> _run(String url, String userAgent) async {
    final provider = ResizeImage(NetworkImage(proxiedUrl(url, userAgent: userAgent), headers: {'User-Agent': userAgent}), width: _size);
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) completer.complete(info.image.clone());
        stream.removeListener(listener);
      },
      onError: (error, stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    final image = await completer.future.timeout(const Duration(seconds: 20));
    try {
      final data = await image.toByteData();
      if (data == null) return LogoTone.normal;
      return classify(data.buffer.asUint8List(), image.width * image.height);
    } finally {
      image.dispose();
    }
  }

  /// [rgba] sind die Pixel als R,G,B,A-Bytes. Öffentlich für Tests.
  static LogoTone classify(List<int> rgba, int pixelCount) {
    var visible = 0;
    var dark = 0;
    var luminance = 0.0;
    for (var i = 0; i + 3 < rgba.length; i += 4) {
      if (rgba[i + 3] < 40) continue;
      visible++;
      // Stärkste Farbkomponente statt Helligkeit: Kräftiges Rot oder Blau ist auf
      // dunklem Grund gut sichtbar, nur Schwarz und sehr dunkle Töne nicht.
      final value = [rgba[i], rgba[i + 1], rgba[i + 2]].reduce((a, b) => a > b ? a : b) / 255;
      luminance += value;
      if (value < 0.3) dark++;
    }
    if (pixelCount == 0 || visible / pixelCount < 0.02) return LogoTone.empty;
    // Logos mit eigenem, deckendem Hintergrund bringen ihren Kontrast selbst mit.
    if (visible / pixelCount > 0.9) return LogoTone.normal;
    final average = luminance / visible;
    return average < 0.35 || dark / visible > 0.7 ? LogoTone.dark : LogoTone.normal;
  }
}

/// Senderlogo, das immer sichtbar ist: dunkle Logos bekommen eine helle
/// Fläche, leere oder fehlende werden zum Monogramm.
class LogoImage extends ConsumerStatefulWidget {
  const LogoImage({
    super.key,
    required this.url,
    required this.name,
    this.padding = EdgeInsets.zero,
    this.monogramSize = 64,
  });

  final String? url;
  final String name;
  final EdgeInsets padding;
  final double monogramSize;

  @override
  ConsumerState<LogoImage> createState() => _LogoImageState();
}

class _LogoImageState extends ConsumerState<LogoImage> {
  LogoTone? _tone;

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  @override
  void didUpdateWidget(LogoImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _analyze();
  }

  void _analyze() {
    final url = widget.url;
    _tone = url == null ? null : LogoAnalyzer.cached(url);
    if (url == null || _tone != null || ref.read(networkBlockedProvider)) return;
    LogoAnalyzer.analyze(url, ref.read(userAgentProvider)).then((tone) {
      if (mounted && widget.url == url) setState(() => _tone = tone);
    });
  }

  @override
  Widget build(BuildContext context) {
    final monogram = Monogram(name: widget.name, size: widget.monogramSize);
    if (widget.url == null || _tone == LogoTone.empty) return monogram;
    final image = MediaImage(
      url: widget.url,
      fit: BoxFit.contain,
      // Logos nie in voller Größe dekodieren; spart bei hunderten Kacheln Speicher.
      cacheWidth: 320,
      padding: widget.padding,
      placeholder: monogram,
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      color: _tone == LogoTone.dark ? AppColors.logoLight : Colors.transparent,
      child: image,
    );
  }
}
