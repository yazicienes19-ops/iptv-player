import 'package:dio/dio.dart';

import '../models/catalog.dart';
import '../models/category.dart';
import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/epg_item.dart';
import '../models/playlist_credentials.dart';
import 'http_client.dart';
import 'network_security.dart';

class XtreamException implements Exception {
  const XtreamException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Client für die Xtream-Codes-`player_api.php`.
class XtreamApi {
  XtreamApi(this.credentials, {required this.dio});

  final PlaylistCredentials credentials;
  final Dio dio;

  String get _server => credentials.normalizedServer;
  String get _user => Uri.encodeComponent(credentials.username ?? '');
  String get _pass => Uri.encodeComponent(credentials.password ?? '');

  Future<dynamic> _get(String? action, [Map<String, Object?> params = const {}]) async {
    try {
      final response = await dio.get<dynamic>(
        '$_server/player_api.php',
        queryParameters: {
          'username': credentials.username,
          'password': credentials.password,
          'action': ?action,
          ...params,
        },
      );
      return response.data;
    } on DioException catch (e) {
      if (isKillSwitchError(e)) throw XtreamException('${const KillSwitchException()}');
      throw XtreamException(switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout => 'Server antwortet nicht (Zeitüberschreitung).',
        DioExceptionType.badResponse => 'Server-Fehler ${e.response?.statusCode}.',
        _ => 'Verbindung fehlgeschlagen: ${e.message ?? e.error}',
      });
    }
  }

  /// Prüft die Zugangsdaten. Wirft bei falschem Login eine [XtreamException].
  Future<void> authenticate() async {
    final data = await _get(null);
    if (data is! Map || data['user_info'] is! Map) {
      throw const XtreamException('Ungültige Antwort, ist das ein Xtream-Codes-Server?');
    }
    final info = data['user_info'] as Map;
    if ('${info['auth']}' != '1') throw const XtreamException('Benutzername oder Passwort falsch.');
    final status = '${info['status']}'.toLowerCase();
    if (status != 'active') throw XtreamException('Konto nicht aktiv (Status: ${info['status']}).');
  }

  static const _categoryActions = {
    ContentType.live: 'get_live_categories',
    ContentType.movie: 'get_vod_categories',
    ContentType.series: 'get_series_categories',
  };

  static const _streamActions = {
    ContentType.live: 'get_live_streams',
    ContentType.movie: 'get_vod_streams',
    ContentType.series: 'get_series',
  };

  Future<List<Category>> getCategories(ContentType type) async {
    final data = await _get(_categoryActions[type]);
    return _asMaps(data).map((json) => Category.fromXtream(json, type)).toList();
  }

  Future<List<Channel>> getStreams(ContentType type, {String? categoryId}) async {
    final data = await _get(_streamActions[type], {'category_id': ?categoryId});
    return _asMaps(data).map((json) => _channelFromJson(json, type)).toList();
  }

  Future<Catalog> getCatalog(ContentType type) async {
    final results = await Future.wait([getCategories(type), getStreams(type)]);
    return Catalog(categories: results[0] as List<Category>, channels: results[1] as List<Channel>);
  }

  Future<List<EpgItem>> getShortEpg(int streamId, {int limit = 4}) async {
    final data = await _get('get_short_epg', {'stream_id': streamId, 'limit': limit});
    final listings = data is Map ? data['epg_listings'] : null;
    return _asMaps(listings).map(EpgItem.fromXtream).toList()..sort((a, b) => a.start.compareTo(b.start));
  }

  Future<MediaDetails> getVodDetails(Channel movie) async {
    final data = await _get('get_vod_info', {'vod_id': movie.xtreamStreamId});
    final info = data is Map && data['info'] is Map ? (data['info'] as Map).cast<String, dynamic>() : null;
    if (info == null) return MediaDetails.empty;
    return _detailsFromInfo(info);
  }

  Future<MediaDetails> getSeriesDetails(Channel series) async {
    final data = await _get('get_series_info', {'series_id': series.xtreamStreamId});
    if (data is! Map) return MediaDetails.empty;
    final info = data['info'] is Map ? (data['info'] as Map).cast<String, dynamic>() : <String, dynamic>{};
    final episodes = data['episodes'];

    final seasons = <Season>[];
    if (episodes is Map) {
      for (final entry in episodes.entries) {
        final number = int.tryParse('${entry.key}') ?? 0;
        final items = _asMaps(entry.value).map((json) {
          final id = '${json['id']}';
          final ext = json['container_extension'] ?? 'mp4';
          final episodeNum = int.tryParse('${json['episode_num']}') ?? 0;
          final epInfo = json['info'] is Map
              ? (json['info'] as Map).cast<String, dynamic>()
              : const <String, dynamic>{};
          final title = (json['title'] as String?)?.trim();
          return Episode(
            number: episodeNum,
            plot: _text(epInfo['plot']),
            duration: _formatDuration(epInfo['duration_secs'], epInfo['duration']),
            channel: Channel(
              id: 'episode-$id',
              name: title?.isNotEmpty == true ? title! : 'Folge $episodeNum',
              streamUrl: '$_server/series/$_user/$_pass/$id.$ext',
              type: ContentType.series,
              logo: _text(epInfo['movie_image']) ?? series.logo,
            ),
          );
        }).toList()..sort((a, b) => a.number.compareTo(b.number));
        seasons.add(Season(number: number, episodes: items));
      }
      seasons.sort((a, b) => a.number.compareTo(b.number));
    }
    return _detailsFromInfo(info, seasons: seasons);
  }

  MediaDetails _detailsFromInfo(Map<String, dynamic> info, {List<Season> seasons = const []}) {
    final backdrops = info['backdrop_path'];
    final release = _text(info['releasedate'] ?? info['releaseDate'] ?? info['release_date']);
    return MediaDetails(
      plot: _text(info['plot'] ?? info['description']),
      genre: _text(info['genre']),
      year: release != null && release.length >= 4 ? release.substring(0, 4) : null,
      rating: double.tryParse('${info['rating']}'),
      duration: _formatDuration(info['duration_secs'], info['duration']),
      backdrop: backdrops is List && backdrops.isNotEmpty ? _text(backdrops.first) : _text(backdrops),
      cast: _text(info['cast'] ?? info['actors']),
      seasons: seasons,
      tmdbId: int.tryParse('${info['tmdb_id'] ?? info['tmdb'] ?? ''}'),
    );
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _formatDuration(Object? seconds, Object? fallback) {
    final secs = int.tryParse('$seconds');
    if (secs == null || secs <= 0) return _text(fallback);
    final hours = secs ~/ 3600;
    final minutes = (secs % 3600) ~/ 60;
    return hours > 0 ? '$hours Std. $minutes Min.' : '$minutes Min.';
  }

  Channel _channelFromJson(Map<String, dynamic> json, ContentType type) {
    final rawId = json['stream_id'] ?? json['series_id'];
    final id = int.tryParse('$rawId');
    final logo = (json['stream_icon'] ?? json['cover']) as String?;
    final streamUrl = switch (type) {
      // `.ts` ist der robusteste Container für Live-Streams; libmpv spielt ihn direkt.
      ContentType.live => '$_server/live/$_user/$_pass/$rawId.ts',
      ContentType.movie => '$_server/movie/$_user/$_pass/$rawId.${json['container_extension'] ?? 'mp4'}',
      ContentType.series => '',
    };
    return Channel(
      id: '$rawId',
      name: (json['name'] as String?)?.trim() ?? 'Ohne Namen',
      streamUrl: streamUrl,
      type: type,
      logo: logo?.isNotEmpty == true ? logo : null,
      categoryId: json['category_id'] == null ? null : '${json['category_id']}',
      epgChannelId: json['epg_channel_id'] as String?,
      xtreamStreamId: id,
    );
  }

  static List<Map<String, dynamic>> _asMaps(Object? data) {
    if (data is List) return data.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
    // Manche Panels liefern statt einer Liste ein Objekt mit numerischen Schlüsseln.
    if (data is Map) return data.values.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
    return const [];
  }
}
