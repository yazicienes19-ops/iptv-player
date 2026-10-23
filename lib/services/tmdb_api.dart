import 'package:dio/dio.dart';

import '../models/tmdb.dart';
import 'http_client.dart';
import 'network_security.dart';

class TmdbException implements Exception {
  const TmdbException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Zugriff auf The Movie Database. Läuft über den gemeinsamen HTTP-Client,
/// also mit getarntem User-Agent und Kill-Switch.
///
/// Akzeptiert den kurzen „API-Schlüssel“ (v3) und das lange
/// „API-Lesezugriffstoken“ (v4, beginnt mit `eyJ`).
class TmdbApi {
  TmdbApi(String key, {required this.dio}) : _key = key.trim();

  static const _base = 'https://api.themoviedb.org/3';
  static const _language = 'de-DE';

  final Dio dio;
  final String _key;

  bool get _isBearer => _key.startsWith('eyJ');

  Future<Map<String, dynamic>> _get(String path, [Map<String, Object?> params = const {}]) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '$_base$path',
        queryParameters: {'language': _language, if (!_isBearer) 'api_key': _key, ...params},
        options: Options(headers: {if (_isBearer) 'Authorization': 'Bearer $_key'}, responseType: ResponseType.json),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      if (isKillSwitchError(e)) throw TmdbException('${const KillSwitchException()}');
      final status = e.response?.statusCode;
      throw TmdbException(switch (status) {
        401 => 'Der TMDB-Schlüssel ist ungültig.',
        404 => 'Bei TMDB nicht gefunden.',
        429 => 'TMDB: zu viele Anfragen, bitte kurz warten.',
        _ => 'TMDB nicht erreichbar${status == null ? '' : ' ($status)'}.',
      });
    }
  }

  /// Prüft den Schlüssel mit einer günstigen Anfrage.
  Future<void> verify() => _get('/configuration');

  /// Sucht einen Film bzw. eine Serie nach Titel (und Jahr, falls bekannt).
  Future<TmdbRef?> search(String title, TmdbMediaType type, {int? year}) async {
    final path = type == TmdbMediaType.movie ? '/search/movie' : '/search/tv';
    final yearParam = type == TmdbMediaType.movie ? 'year' : 'first_air_date_year';
    Future<List<TmdbRef>> run({int? withYear}) async {
      final data = await _get(path, {'query': title, 'include_adult': 'false', yearParam: ?withYear});
      return [
        for (final r in (data['results'] as List? ?? const [])) TmdbRef.fromJson(r as Map<String, dynamic>, type: type),
      ];
    }

    var results = await run(withYear: year);
    // Jahresangaben in Playlists weichen oft um ein Jahr ab (Kino- vs. Heimkinostart).
    if (results.isEmpty && year != null) results = await run();
    if (results.isEmpty) return null;
    return pickBestMatch(results, title, year: year);
  }

  /// Bevorzugt exakte Titelgleichheit und passendes Jahr; sonst den ersten Treffer.
  static TmdbRef pickBestMatch(List<TmdbRef> results, String title, {int? year}) {
    final wanted = normalizeTitle(title);
    int score(TmdbRef r) {
      var points = 0;
      if (normalizeTitle(r.title) == wanted || normalizeTitle(r.originalTitle ?? '') == wanted) points += 10;
      if (year != null && r.year != null) {
        final diff = (r.year! - year).abs();
        if (diff == 0) points += 5;
        if (diff == 1) points += 3;
      }
      return points;
    }

    final ranked = [...results]..sort((a, b) => score(b).compareTo(score(a)));
    return ranked.first;
  }

  Future<TmdbTitle> title(int id, TmdbMediaType type) async {
    final isTv = type == TmdbMediaType.tv;
    final append = isTv
        ? 'aggregate_credits,videos,recommendations,content_ratings'
        : 'credits,videos,recommendations,release_dates';
    final data = await _get('/${isTv ? 'tv' : 'movie'}/$id', {
      'append_to_response': append,
      // Trailer auch auf Englisch, falls es keinen deutschen gibt.
      'include_video_language': 'de,en,null',
    });
    var result = TmdbTitle.fromJson(data, type);
    if (result.overview == null) {
      final english = await _get('/${isTv ? 'tv' : 'movie'}/$id', {'language': 'en-US'});
      result = TmdbTitle.fromJson({...data, 'overview': english['overview'], '_overviewFallback': true}, type);
    }
    return result;
  }

  Future<TmdbCollection> collection(int id) async => TmdbCollection.fromJson(await _get('/collection/$id'));

  Future<TmdbPerson> person(int id) async {
    final data = await _get('/person/$id', {'append_to_response': 'combined_credits'});
    if (data['biography'] is String && (data['biography'] as String).trim().isEmpty) {
      final english = await _get('/person/$id', {'language': 'en-US'});
      return TmdbPerson.fromJson({...data, 'biography': english['biography']});
    }
    return TmdbPerson.fromJson(data);
  }
}

/// Für Titelvergleiche: klein, ohne Satzzeichen, Artikel und Umlaut-Varianten.
String normalizeTitle(String title) => title
    .toLowerCase()
    .replaceAll('ä', 'ae')
    .replaceAll('ö', 'oe')
    .replaceAll('ü', 'ue')
    .replaceAll('ß', 'ss')
    .replaceAll('&', 'und')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .replaceAll(RegExp(r'^(the|der|die|das|a|an) '), '')
    .replaceAll(' ', '');
