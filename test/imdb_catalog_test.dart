import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/models/catalog.dart';
import 'package:iptv_player/models/content_type.dart';
import 'package:iptv_player/providers/app_providers.dart';
import 'package:iptv_player/providers/imdb_providers.dart';
import 'package:iptv_player/services/imdb_catalog.dart';
import 'package:iptv_player/services/imdb_catalog_store.dart';
import 'package:iptv_player/ui/browse/browse_view.dart';
import 'package:iptv_player/ui/theme.dart';

class TestImdbCatalog extends ImdbCatalogNotifier {
  @override
  Future<ImdbCatalog?> build() async => ImdbCatalog.parse(jsonEncode(fixture()));
}

class AllLanguages extends LanguageFilterNotifier {
  @override
  String? build() => null;
}

Map<String, Object> fixture() => {
  'schemaVersion': 1,
  'generatedAt': '2026-10-24T00:00:00Z',
  'minVotes': 25000,
  'movies': [
    {
      'id': 'tt0000001',
      'title': 'First Crime',
      'originalTitle': 'Primo Crimine',
      'year': 1990,
      'genres': ['Crime', 'Drama'],
      'rating': 8.8,
      'votes': 100000,
    },
    {
      'id': 'tt0000002',
      'title': 'Second Crime',
      'year': 2000,
      'genres': ['Crime'],
      'rating': 9.0,
      'votes': 80000,
    },
    {
      'id': 'tt0000003',
      'title': 'Tomorrow',
      'year': 1990,
      'genres': ['Sci-Fi'],
      'rating': 8.8,
      'votes': 200000,
    },
    {
      'id': 'tt0000004',
      'title': 'Tomorrow',
      'year': 2010,
      'genres': ['Drama'],
      'rating': 8.0,
      'votes': 26000,
    },
    {
      'id': 'tt0000005',
      'title': 'Unclear',
      'year': 1999,
      'genres': ['Drama'],
      'rating': 8.2,
      'votes': 26000,
    },
    {
      'id': 'tt0000006',
      'title': 'Unclear',
      'year': 1999,
      'genres': ['Drama'],
      'rating': 8.4,
      'votes': 30000,
    },
  ],
};

Channel movie(
  String name, {
  int? year,
  String? imdbId,
  String? id,
  List<String> genres = const [],
  List<String> cast = const [],
  String? director,
}) => Channel(
  id: id ?? name,
  name: name,
  streamUrl: 'https://example.test/movie.mp4',
  type: ContentType.movie,
  year: year,
  imdbId: imdbId,
  genres: genres,
  cast: cast,
  director: director,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('matches only an IMDb ID or a unique cleaned title and release year', () {
    final catalog = ImdbCatalog.parse(jsonEncode(fixture()));
    expect(catalog.match(movie('Translated name', imdbId: 'tt0000001'))?.id, 'tt0000001');
    expect(catalog.match(movie('DE | First Crime (1990) 4K'))?.id, 'tt0000001');
    expect(catalog.match(movie('Primo Crimine', year: 1990))?.id, 'tt0000001');
    expect(catalog.match(movie('Tomorrow', year: 2010))?.id, 'tt0000004');
    expect(catalog.match(movie('Tomorrow')), isNull);
    expect(catalog.match(movie('Unclear', year: 1999)), isNull);
    expect(catalog.match(movie('First Crime', year: 1991)), isNull);
    expect(catalog.match(movie('First Crime', year: 1990, imdbId: 'tt9999999')), isNull);
  });

  test('title-only metadata matches unique localized aliases and preserves numeric titles', () {
    final data = fixture();
    final rows = data['movies']! as List<Map<String, Object>>;
    rows.first['aliases'] = ['Das erste Verbrechen', 'İlk Suç'];
    rows[2]['aliases'] = ['Morgen'];
    rows[3]['aliases'] = ['Morgen'];
    final numeric = ['1917', '2001: A Space Odyssey', 'Blade Runner 2049', '[REC]', 'Class of 1984'];
    for (var i = 0; i < numeric.length; i++) {
      rows.add({
        'id': 'tt100000$i',
        'title': numeric[i],
        'year': 2000 + i,
        'genres': ['Drama'],
        'rating': 8,
        'votes': 30000,
      });
    }
    final catalog = ImdbCatalog.parse(jsonEncode(data));
    for (final title in [
      'First Crime',
      'Das erste Verbrechen',
      'İlk Suç',
      '(V|DE) DE: Das erste Verbrechen FHD HEVC',
      'DE | Das erste Verbrechen 1990 WEB-DL x265',
      'DE | FHD | Das erste Verbrechen',
      '[4K] Das erste Verbrechen',
      'Das erste Verbrechen [1990] [FHD]',
    ]) {
      expect(catalog.match(movie(title))?.id, 'tt0000001', reason: title);
    }
    expect(catalog.match(movie('Morgen')), isNull);
    expect(catalog.match(movie('Morgen 2010'))?.id, 'tt0000004');
    expect(catalog.match(movie('Das erste Verbrechen 1991')), isNull);
    expect(catalog.match(movie('First Crime', imdbId: 'not-an-id')), isNull);
    for (var i = 0; i < numeric.length; i++) {
      expect(catalog.match(movie(numeric[i]))?.id, 'tt100000$i', reason: numeric[i]);
    }
  });

  test('sequel Roman suffixes match Arabic aliases without resolving ambiguous collisions', () {
    final data = fixture();
    final rows = data['movies']! as List<Map<String, Object>>;
    final titles = ['Der Pate 2', 'Story VIII', 'Conflict II', 'Conflict 2', 'II', 'Malcolm X', 'Rocky V'];
    for (var i = 0; i < titles.length; i++) {
      rows.add({
        'id': 'tt200000$i',
        'title': titles[i],
        'year': 2000,
        'genres': ['Drama'],
        'rating': 8,
        'votes': 30000,
      });
    }
    final catalog = ImdbCatalog.parse(jsonEncode(data));
    expect(catalog.match(movie('Der Pate II'))?.id, 'tt2000000');
    expect(catalog.match(movie('Story 8'))?.id, 'tt2000001');
    expect(cleanCatalogTitle('Der Pate II').title, 'Der Pate II');
    expect(catalog.match(movie('Conflict II')), isNull);
    expect(catalog.match(movie('Conflict 2', year: 2000)), isNull);
    expect(catalog.match(movie('II'))?.id, 'tt2000004');
    expect(catalog.match(movie('2')), isNull);
    expect(catalog.match(movie('Malcolm 10')), isNull);
    expect(catalog.match(movie('Rocky 5')), isNull);
    expect(catalogTitleKey('I'), 'i');
  });

  test('ranking uses actual ratings and vote tie breaks, deduplicates and filters genres', () {
    final catalog = ImdbCatalog.parse(jsonEncode(fixture()));
    final movies = [
      movie('First Crime', year: 1990),
      movie('Second Crime', year: 2000),
      movie('Tomorrow', year: 1990),
      movie('Duplicate', imdbId: 'tt0000001'),
    ];
    expect(catalog.ranked(movies).map((row) => row.$2.id), ['tt0000002', 'tt0000003', 'tt0000001']);
    expect(catalog.ranked(movies, genre: 'Krimi', limit: 1).single.$2.id, 'tt0000002');
    expect(catalog.ranked(movies, genre: 'Science Fiction').single.$2.id, 'tt0000003');
    expect(catalog.minVotes, 25000);
  });

  test('search accepts title typos, accents, genres and people without a metadata import', () {
    final movies = [
      movie('Interstellar', year: 2014, genres: ['Sci-Fi', 'Adventure'], cast: ['Anne Hathaway']),
      movie('München', year: 2005, genres: ['Crime', 'Drama']),
      movie('Another', genres: ['Drama']),
    ];
    expect(searchCatalog(movies, 'interstelalr'), [movies[0]]);
    expect(searchCatalog(movies, 'Munchen'), [movies[1]]);
    expect(searchCatalog(movies, 'Krimi'), [movies[1]]);
    expect(searchCatalog(movies, 'Science Fiction'), [movies[0]]);
    expect(searchCatalog(movies, 'Hathaway'), [movies[0]]);
    expect(searchCatalog(movies, 'adventure 2014'), [movies[0]]);
    expect(searchCatalog(movies, 'Unrelated missing title'), isEmpty);
  });

  test('similar-title searches use real metadata and never invent unrelated results', () {
    final catalog = ImdbCatalog.parse(jsonEncode(fixture()));
    final movies = [
      movie('First Crime', year: 1990),
      movie('Second Crime', year: 2000),
      movie('Tomorrow', year: 1990),
      movie('Unrelated'),
    ];
    for (final query in [
      'Filme wie First Crime',
      'ähnlich wie First Crime',
      'aehnlich wie First Crime',
      'ähnliche Filme wie First Crime',
      'aehnliche Filme wie First Crime',
      'wie First Crime',
    ]) {
      expect(searchCatalog(movies, query, imdb: catalog), [movies[1]]);
    }
    expect(searchCatalog(movies, 'wie Missing', imdb: catalog), isEmpty);
    expect(searchCatalog(movies, 'wie Unrelated', imdb: catalog), isEmpty);
  });

  test('similar parser handles ASCII and umlaut forms, series and incomplete input consistently', () {
    for (final prefix in [
      'ähnlich wie',
      'aehnlich wie',
      'ÄHNLICHE FILME WIE',
      'ähnliche Serien wie',
      'aehnliche Serie zu',
      'Serien ähnlich wie',
      'Serie wie',
      'Serien wie',
      'Filme wie',
      'wie',
      'zu',
    ]) {
      expect(parseSimilarQuery('  $prefix  Dark  '), 'Dark');
    }
    for (final query in ['', 'ähnlich wie', 'aehnliche Filme wie ', 'Dark', 'Krimi']) {
      expect(parseSimilarQuery(query), isNull);
    }
    const first = Channel(
      id: 'a',
      name: 'Dark',
      streamUrl: '',
      type: ContentType.series,
      genres: ['Sci-Fi', 'Mystery'],
    );
    const second = Channel(id: 'b', name: '1899', streamUrl: '', type: ContentType.series, genres: ['Mystery']);
    expect(
      searchCatalog([
        first,
        second,
        movie('A movie', genres: ['Mystery']),
      ], 'aehnliche Serien wie Dark'),
      [second],
    );
  });

  test('channel metadata survives favorites and recent JSON serialization', () {
    final original = movie(
      'Film',
      year: 1990,
      imdbId: 'tt0000001',
      genres: ['Crime'],
      cast: ['Actor'],
      director: 'Director',
    );
    final restored = Channel.fromJson(original.toJson());
    expect(restored.imdbId, 'tt0000001');
    expect(restored.year, 1990);
    expect(restored.genres, ['Crime']);
    expect(restored.cast, ['Actor']);
    expect(restored.director, 'Director');
  });

  test('local import persists, rejects malformed replacement and clears only its own file', () async {
    final directory = await Directory.systemTemp.createTemp('ipflix-imdb-test-');
    addTearDown(() => directory.delete(recursive: true));
    final store = ImdbCatalogStore(directory: () async => directory);
    final source = File('${directory.path}/source.json');
    await source.writeAsString(jsonEncode(fixture()));
    expect(await store.load(), isNull);
    await store.importFile(source.path);
    expect((await store.load())?.movies.length, 6);
    await source.writeAsString('{invalid');
    await expectLater(store.importFile(source.path), throwsFormatException);
    expect((await store.load())?.movies.length, 6);
    await store.clear();
    expect(await store.load(), isNull);
    expect(await source.exists(), isTrue);
  });

  testWidgets('IMDb genre chips wrap in a small native window and update the filter', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imdbCatalogProvider.overrideWith(TestImdbCatalog.new),
          activePlaylistProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: SingleChildScrollView(child: ImdbFilters(left: 16, right: 16))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Beste Krimis'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(ImdbFilters)));
    expect(container.read(imdbFilterProvider), 'Crime');
    expect(find.textContaining('25000 Stimmen'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Alle Filme'));
    await tester.pumpAndSettle();
    expect(container.read(imdbFilterProvider), isNull);
  });

  test('native browse provider combines fuzzy search with imported IMDb category filtering', () async {
    final movies = [movie('First Crime', year: 1990), movie('Second Crime', year: 2000), movie('Tomorrow', year: 1990)];
    final container = ProviderContainer(
      overrides: [
        imdbCatalogProvider.overrideWith(TestImdbCatalog.new),
        activePlaylistProvider.overrideWithValue(null),
        languageFilterProvider.overrideWith(AllLanguages.new),
        catalogProvider(ContentType.movie).overrideWith((ref) async => Catalog(categories: const [], channels: movies)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(imdbCatalogProvider.future);
    await container.read(catalogProvider(ContentType.movie).future);
    container.read(searchQueryProvider(AppSection.movies).notifier).set('firts crime');
    expect(container.read(visibleChannelsProvider(ContentType.movie)).value, [movies[0]]);
    container.read(searchQueryProvider(AppSection.movies).notifier).set('');
    container.read(imdbFilterProvider.notifier).select('Crime');
    expect(container.read(visibleChannelsProvider(ContentType.movie)).value, [movies[1], movies[0]]);
    expect(container.read(imdbRowsProvider).length, 3, reason: 'home rows ignore the temporary browse filter');
  });
}
