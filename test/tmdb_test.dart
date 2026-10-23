import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/models/content_type.dart';
import 'package:iptv_player/models/tmdb.dart';
import 'package:iptv_player/providers/app_providers.dart';
import 'package:iptv_player/services/tmdb_api.dart';

/// Beantwortet Anfragen mit festen JSON-Daten statt des echten TMDB-Servers.
class FakeTmdb implements HttpClientAdapter {
  FakeTmdb(this.routes);

  final Map<String, Object> Function(RequestOptions) routes;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final body = routes(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

TmdbApi apiWith(Map<String, Object> Function(RequestOptions) routes, {String key = 'abc123'}) {
  final dio = Dio()..httpClientAdapter = FakeTmdb(routes);
  return TmdbApi(key, dio: dio);
}

const potterJson = {
  'id': 671,
  'title': 'Harry Potter und der Stein der Weisen',
  'original_title': "Harry Potter and the Philosopher's Stone",
  'tagline': 'Lass dich verzaubern.',
  'overview': 'Harry erfährt an seinem elften Geburtstag, dass er ein Zauberer ist.',
  'release_date': '2001-11-16',
  'runtime': 152,
  'vote_average': 7.9,
  'vote_count': 27000,
  'genres': [
    {'id': 12, 'name': 'Abenteuer'},
    {'id': 14, 'name': 'Fantasy'},
  ],
  'poster_path': '/poster.jpg',
  'backdrop_path': '/backdrop.jpg',
  'belongs_to_collection': {'id': 1241, 'name': 'Harry Potter Filmreihe'},
  'credits': {
    'cast': [
      {'id': 10980, 'name': 'Daniel Radcliffe', 'character': 'Harry Potter', 'profile_path': '/dr.jpg'},
      {'id': 10989, 'name': 'Rupert Grint', 'character': 'Ron Weasley', 'profile_path': null},
    ],
    'crew': [
      {'id': 10965, 'name': 'Chris Columbus', 'job': 'Director'},
      {'id': 1, 'name': 'Jemand', 'job': 'Producer'},
    ],
  },
  'videos': {
    'results': [
      {'site': 'YouTube', 'type': 'Teaser', 'key': 'teaser1'},
      {'site': 'YouTube', 'type': 'Trailer', 'key': 'trailer1'},
    ],
  },
  'release_dates': {
    'results': [
      {
        'iso_3166_1': 'DE',
        'release_dates': [
          {'certification': '6'},
        ],
      },
    ],
  },
  'recommendations': {
    'results': [
      {'id': 672, 'title': 'Harry Potter und die Kammer des Schreckens', 'release_date': '2002-11-13'},
    ],
  },
};

void main() {
  test('Filmdetails: Darsteller, Regie, Trailer, FSK, Reihe, Laufzeit', () async {
    final api = apiWith((o) => potterJson);
    final movie = await api.title(671, TmdbMediaType.movie);

    expect(movie.title, 'Harry Potter und der Stein der Weisen');
    expect(movie.year, 2001);
    expect(movie.runtimeLabel, '2 Std. 32 Min.');
    expect(movie.genres, ['Abenteuer', 'Fantasy']);
    expect(movie.directors, ['Chris Columbus']);
    expect(movie.cast.first.name, 'Daniel Radcliffe');
    expect(movie.cast.first.photo, 'https://image.tmdb.org/t/p/w185/dr.jpg');
    expect(movie.cast.last.photo, isNull);
    expect(movie.trailerYoutubeKey, 'trailer1');
    expect(movie.certification, 'FSK 6');
    expect(movie.collectionId, 1241);
    expect(movie.recommendations.single.year, 2002);
  });

  test('Schlüsselart: kurzer Schlüssel als Parameter, Lesetoken als Bearer-Header', () async {
    final short = FakeTmdb((o) => potterJson);
    await TmdbApi('abc123', dio: Dio()..httpClientAdapter = short).title(671, TmdbMediaType.movie);
    expect(short.requests.single.queryParameters['api_key'], 'abc123');
    expect(short.requests.single.headers['Authorization'], isNull);

    final token = FakeTmdb((o) => potterJson);
    await TmdbApi('eyJhbGciOi.token', dio: Dio()..httpClientAdapter = token).title(671, TmdbMediaType.movie);
    expect(token.requests.single.queryParameters.containsKey('api_key'), isFalse);
    expect(token.requests.single.headers['Authorization'], 'Bearer eyJhbGciOi.token');
  });

  test('Fehlt die deutsche Handlung, wird die englische nachgeladen', () async {
    final api = apiWith(
      (o) => o.queryParameters['language'] == 'en-US'
          ? {'id': 1, 'overview': 'English plot.'}
          : {'id': 1, 'title': 'Film', 'overview': ''},
    );
    final movie = await api.title(1, TmdbMediaType.movie);
    expect(movie.overview, 'English plot.');
    expect(movie.overviewIsGerman, isFalse);
  });

  test('Suche: exakter Titel und passendes Jahr gewinnen', () {
    final results = [
      const TmdbRef(id: 1, type: TmdbMediaType.movie, title: 'Dune', year: 1984),
      const TmdbRef(id: 2, type: TmdbMediaType.movie, title: 'Dune: Part Two', year: 2024),
      const TmdbRef(id: 3, type: TmdbMediaType.movie, title: 'Dune', year: 2021),
    ];
    expect(TmdbApi.pickBestMatch(results, 'Dune', year: 2021).id, 3);
    expect(TmdbApi.pickBestMatch(results, 'Dune: Part Two').id, 2);
  });

  test('Reihe: Teile nach Jahr, angekündigte Teile ans Ende', () {
    final collection = TmdbCollection.fromJson({
      'id': 1241,
      'name': 'Harry Potter Filmreihe',
      'parts': [
        {'id': 3, 'title': 'Teil 3', 'release_date': '2004-05-31'},
        {'id': 9, 'title': 'Angekündigt', 'release_date': ''},
        {'id': 1, 'title': 'Teil 1', 'release_date': '2001-11-16'},
      ],
    });
    expect(collection.parts.map((p) => p.title), ['Teil 1', 'Teil 3', 'Angekündigt']);
  });

  test('Playlist-Index findet deutschen oder Originaltitel, Jahr ±1', () {
    Channel movie(String name) => Channel(id: name, name: name, streamUrl: 'http://x', type: ContentType.movie);
    final index = PlaylistTitleIndex([
      movie('(DE-) Harry Potter und der Stein der Weisen - 2001'),
      movie('(DE-) Inception (2010)'),
    ]);

    expect(
      index.find(
        const TmdbRef(id: 671, type: TmdbMediaType.movie, title: 'Harry Potter und der Stein der Weisen', year: 2002),
      ),
      isNotNull,
    );
    expect(
      index.find(
        const TmdbRef(id: 27205, type: TmdbMediaType.movie, title: 'Inception', originalTitle: 'Inception', year: 2010),
      ),
      isNotNull,
    );
    expect(index.find(const TmdbRef(id: 1, type: TmdbMediaType.movie, title: 'Inception', year: 2016)), isNull);
    expect(index.find(const TmdbRef(id: 1, type: TmdbMediaType.tv, title: 'Inception', year: 2010)), isNull);
  });
}
