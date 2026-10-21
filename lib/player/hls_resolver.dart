import 'package:dio/dio.dart';

/// Eine zusätzliche Tonspur aus `#EXT-X-MEDIA:TYPE=AUDIO`.
class HlsAudioRendition {
  const HlsAudioRendition({required this.url, required this.name, this.language, this.isDefault = false});

  final String url;
  final String name;
  final String? language;
  final bool isDefault;
}

/// Was libmpv tatsächlich öffnen soll.
class ResolvedStream {
  const ResolvedStream(this.url, {this.audio = const []});

  final String url;
  final List<HlsAudioRendition> audio;
}

/// Umgeht einen Hänger im HLS-Demuxer des mitgelieferten FFmpeg: Master-
/// Playlists mit separaten Ton-/Untertitelspuren (z. B. Das Erste, ARD-alpha)
/// bleiben dort beim Öffnen ewig stehen. Stattdessen öffnen wir direkt die
/// beste Bildvariante und hängen die Tonspuren einzeln an.
class HlsResolver {
  HlsResolver({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 6),
              headers: {'User-Agent': 'IPTVPlayer/1.0 (libmpv)'},
              responseType: ResponseType.plain,
            ));

  final Dio _dio;

  static bool looksLikeHls(String url) => Uri.tryParse(url)?.path.toLowerCase().endsWith('.m3u8') ?? false;

  /// Bei Netzfehlern oder normalen Playlists bleibt es bei der Original-URL.
  Future<ResolvedStream> resolve(String url) async {
    if (!looksLikeHls(url)) return ResolvedStream(url);
    try {
      final response = await _dio.get<String>(url);
      final finalUrl = response.realUri.toString();
      return parseMaster(response.data ?? '', finalUrl) ?? ResolvedStream(url);
    } catch (_) {
      return ResolvedStream(url);
    }
  }

  /// Gibt `null` zurück, wenn nichts umgangen werden muss.
  static ResolvedStream? parseMaster(String content, String baseUrl) {
    if (!content.contains('#EXT-X-STREAM-INF') || !content.contains('#EXT-X-MEDIA:')) return null;
    final base = Uri.parse(baseUrl);
    final lines = content.split(RegExp(r'\r?\n')).map((l) => l.trim()).toList();

    final audioByGroup = <String, List<HlsAudioRendition>>{};
    var hasSeparateTracks = false;
    _Variant? best;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith('#EXT-X-MEDIA:')) {
        final attrs = _attributes(line.substring(13));
        final uri = attrs['URI'];
        if (uri == null) continue;
        hasSeparateTracks = true;
        if (attrs['TYPE'] == 'AUDIO') {
          audioByGroup.putIfAbsent(attrs['GROUP-ID'] ?? '', () => []).add(HlsAudioRendition(
                url: base.resolve(uri).toString(),
                name: attrs['NAME'] ?? attrs['LANGUAGE'] ?? 'Ton',
                language: attrs['LANGUAGE'],
                isDefault: attrs['DEFAULT'] == 'YES',
              ));
        }
      } else if (line.startsWith('#EXT-X-STREAM-INF:')) {
        final attrs = _attributes(line.substring(18));
        final uri = lines.skip(i + 1).firstWhere((l) => l.isNotEmpty && !l.startsWith('#'), orElse: () => '');
        if (uri.isEmpty) continue;
        final variant = _Variant(
          url: base.resolve(uri).toString(),
          bandwidth: int.tryParse(attrs['BANDWIDTH'] ?? '') ?? 0,
          audioGroup: attrs['AUDIO'],
        );
        if (best == null || variant.bandwidth > best.bandwidth) best = variant;
      }
    }

    if (!hasSeparateTracks || best == null) return null;
    final audio = [...?audioByGroup[best.audioGroup]]..sort((a, b) => (b.isDefault ? 1 : 0) - (a.isDefault ? 1 : 0));
    return ResolvedStream(best.url, audio: audio);
  }

  static final _attributePattern = RegExp(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)');

  static Map<String, String> _attributes(String text) => {
        for (final m in _attributePattern.allMatches(text))
          m.group(1)!: m.group(2)!.replaceAll('"', ''),
      };
}

class _Variant {
  const _Variant({required this.url, required this.bandwidth, this.audioGroup});

  final String url;
  final int bandwidth;
  final String? audioGroup;
}
