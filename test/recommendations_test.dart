import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iptv_player/models/catalog.dart';
import 'package:iptv_player/models/category.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/models/content_type.dart';
import 'package:iptv_player/models/tmdb.dart';
import 'package:iptv_player/providers/app_providers.dart';
import 'package:iptv_player/providers/imdb_providers.dart';
import 'package:iptv_player/services/imdb_catalog.dart';
import 'package:iptv_player/services/local_store.dart';
import 'package:iptv_player/services/personal_library.dart';
import 'package:iptv_player/services/recommendations.dart';
import 'package:iptv_player/ui/detail/detail_page.dart';
import 'package:iptv_player/ui/home/home_view.dart';
import 'package:iptv_player/ui/browse/browse_view.dart';
import 'package:iptv_player/ui/theme.dart';

import 'personal_library_test.dart' show PersonalSecureStore, CatalogApi, playlistA, playlistB;

final testNow = DateTime.utc(2026, 10, 24);
Channel title(
  String id, {
  String? name,
  String? url,
  List<String> genres = const [],
  String? imdbId,
  String? category,
  ContentType type = ContentType.movie,
}) => Channel(
  id: id,
  name: name ?? 'Title $id',
  streamUrl: url ?? 'https://example.test/$id.mp4',
  type: type,
  genres: genres,
  imdbId: imdbId,
  categoryId: category,
);

class NoImdb extends ImdbCatalogNotifier {
  @override
  Future<ImdbCatalog?> build() async => null;
}

class DeferredDetailsApi extends CatalogApi {
  DeferredDetailsApi() : super([], []);
  final details = Completer<MediaDetails>();
  @override
  Future<MediaDetails> getVodDetails(Channel movie) => details.future;
}

ImdbCatalog sampleCatalog() => ImdbCatalog.parse(
  jsonEncode({
    'schemaVersion': 1,
    'generatedAt': '2026-10-24T00:00:00Z',
    'minVotes': 25000,
    'movies': [
      {
        'id': 'tt0000001',
        'title': 'One Crime',
        'originalTitle': 'One Crime',
        'aliases': ['Ein Krimi'],
        'year': 2001,
        'genres': ['Crime'],
        'rating': 8.0,
        'votes': 50000,
      },
      {
        'id': 'tt0000002',
        'title': 'Another Crime',
        'originalTitle': 'Another Crime',
        'year': 2002,
        'genres': ['Crime'],
        'rating': 8.0,
        'votes': 50000,
      },
    ],
  }),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('detail recommendation index rejects ambiguous remakes and prioritizes exact known years', () {
    final older = title('old', name: 'Crash (1996)');
    final newer = title('new', name: 'Crash (2004)');
    final unknown = title('unknown', name: 'Crash');
    final index = PlaylistTitleIndex([older, newer, unknown]);
    expect(index.find(const TmdbRef(id: 1, type: TmdbMediaType.movie, title: 'Crash')), isNull);
    expect(index.find(const TmdbRef(id: 1, type: TmdbMediaType.movie, title: 'Crash', year: 2004)), newer);
    expect(index.find(const TmdbRef(id: 1, type: TmdbMediaType.movie, title: 'Crash', year: 2005)), isNull);
    expect(index.find(const TmdbRef(id: 1, type: TmdbMediaType.movie, title: 'Crash', year: 2020)), unknown);
    expect(index.find(const TmdbRef(id: 1, type: TmdbMediaType.tv, title: 'Crash', year: 2004)), isNull);
    expect(
      PlaylistTitleIndex([unknown]).find(const TmdbRef(id: 1, type: TmdbMediaType.movie, title: 'Crash', year: 2004)),
      unknown,
    );
    final sequel = title('sequel', name: 'Der Pate 2');
    expect(
      PlaylistTitleIndex([sequel]).find(const TmdbRef(id: 2, type: TmdbMediaType.movie, title: 'Der Pate II')),
      sequel,
    );
    final duplicate = title('duplicate', name: 'Crash', url: unknown.streamUrl);
    expect(
      PlaylistTitleIndex([unknown, duplicate]).find(const TmdbRef(id: 1, type: TmdbMediaType.movie, title: 'Crash')),
      unknown,
    );
    expect(
      PlaylistTitleIndex([newer, title('other', name: 'Crash (2004)')])
          .find(const TmdbRef(id: 1, type: TmdbMediaType.movie, title: 'Crash', year: 2004)),
      isNull,
    );
  });

  test('likes rank similar current titles, hide excludes only its title, and recommendations remain diverse', () {
    final seed = title('seed', genres: ['Crime']);
    final crime = title('crime', genres: ['Crime']);
    final hidden = title('hidden', genres: ['Crime']);
    final comedy = title('comedy', genres: ['Comedy']);
    var library = const PersonalLibrary().setFeedback(recommendationKeys(seed, null), FeedbackChoice.like, testNow);
    library = library.setFeedback(recommendationKeys(hidden, null), FeedbackChoice.hide, testNow);
    final result = recommendTitles(
      available: [seed, crime, hidden, comedy],
      sources: [seed, crime, hidden, comedy],
      library: library,
      now: testNow,
    );
    expect(result.channels, [crime, comedy]);
    expect(result.personalized, isTrue);
    expect(result.channels, isNot(contains(hidden)));
    expect(recommendTitles(available: [comedy], sources: [seed, crime, hidden, comedy], library: library).channels, [
      comedy,
    ]);
  });

  test('title-only canonical matches join quality variants; undo through another variant stays neutral', () {
    final imdb = sampleCatalog();
    final a = title('0|a', name: 'Ein Krimi', url: 'https://example.test/one.mp4');
    final b = title('1|b', name: 'One Crime', url: 'https://example.test/one-4k.mp4');
    final other = title('c', name: 'Another Crime');
    var library = const PersonalLibrary().setFeedback(recommendationKeys(a, imdb), FeedbackChoice.hide, testNow);
    expect(recommendTitles(available: [a, b, other], sources: [a, b, other], library: library, imdb: imdb).channels, [
      other,
    ]);
    library = library.setFeedback(recommendationKeys(b, imdb), null, testNow.add(const Duration(seconds: 1)));
    expect(library.feedbackFor(recommendationKeys(a, imdb))?.choice, FeedbackChoice.none);
    final restored = PersonalLibrary.fromJson(library.toJson());
    expect(
      recommendTitles(available: [a, b, other], sources: [a, b, other], library: restored, imdb: imdb).channels.length,
      2,
    );
  });

  test('feedback before metadata import reconciles all variants before deduplication and can be undone', () {
    final imdb = sampleCatalog();
    final a = title('a', name: 'Ein Krimi');
    final b = title('b', name: 'One Crime');
    final other = title('c', name: 'Another Crime');
    final sources = [b, a, other];
    var library = const PersonalLibrary().setFeedback(recommendationKeys(a, null), FeedbackChoice.like, testNow);
    final result = recommendTitles(available: sources, sources: sources, library: library, imdb: imdb);
    expect(result.channels, [other]);
    expect(result.personalized, isTrue);
    library = library.setFeedback(
      recommendationKeys(b, imdb),
      FeedbackChoice.hide,
      testNow.add(const Duration(seconds: 1)),
    );
    expect(recommendTitles(available: sources, sources: sources, library: library, imdb: imdb).channels, [other]);
    library = library.setFeedback(recommendationKeys(b, imdb), null, testNow.add(const Duration(seconds: 2)));
    expect(recommendTitles(available: sources, sources: sources, library: library, imdb: imdb).channels.length, 2);
  });

  test('unknown titles stay discovery suggestions and never imply genres from their names', () {
    final a = title('a', name: 'Thriller Monster Romance');
    final b = title('b', name: 'Romance Thriller');
    final library = const PersonalLibrary().setFeedback(recommendationKeys(a, null), FeedbackChoice.like, testNow);
    final result = recommendTitles(available: [a, b], sources: [a, b], library: library);
    expect(result.personalized, isFalse);
    expect(result.hasSignals, isTrue);
    expect(result.channels, [b]);
  });

  test('verified detail metadata enriches title-only preference without leaking to another identity', () {
    final a = title('a');
    final b = title('b', genres: ['Crime']);
    var library = const PersonalLibrary().rememberMetadata(a, const TitleMetadata(genres: ['Crime']));
    library = library.setFeedback(recommendationKeys(a, null), FeedbackChoice.like, testNow);
    final restored = PersonalLibrary.fromJson(library.toJson());
    expect(recommendTitles(available: [a, b], sources: [a, b], library: restored).personalized, isTrue);
    expect(recommendTitles(available: [a, b], sources: [a, b], library: const PersonalLibrary()).personalized, isFalse);
  });

  test('VOD uses actual playback; seeks to end do not count, sufficient watching seeds and completes only movies', () {
    final seed = title('seed', genres: ['Crime']);
    final crime = title('crime', genres: ['Crime']);
    final keys = recommendationKeys(seed, null);
    var library = const PersonalLibrary().addVodWatch(
      keys,
      const Duration(seconds: 5),
      testNow,
      duration: const Duration(minutes: 100),
      reachedEnd: true,
    );
    expect(library.vodFor(keys)?.completed, isFalse);
    expect(library.vodFor(keys)?.meaningful, isFalse);
    library = library.addVodWatch(keys, const Duration(minutes: 10), testNow, duration: const Duration(minutes: 100));
    expect(library.vodFor(keys)?.meaningful, isTrue);
    expect(recommendTitles(available: [seed, crime], sources: [seed, crime], library: library).personalized, isTrue);
    library = library.addVodWatch(
      keys,
      const Duration(minutes: 75),
      testNow,
      duration: const Duration(minutes: 100),
      reachedEnd: true,
    );
    expect(library.vodFor(keys)?.completed, isTrue);
    expect(recommendTitles(available: [seed, crime], sources: [seed, crime], library: library).channels, [crime]);
    final seriesKeys = recommendationKeys(title('show', type: ContentType.series), null);
    library = library.addVodWatch(
      seriesKeys,
      const Duration(minutes: 60),
      testNow,
      duration: const Duration(minutes: 60),
      reachedEnd: true,
      isMovie: false,
    );
    expect(library.vodFor(seriesKeys)?.completed, isFalse);
  });

  test('feedback and VOD persist privately per playlist, do not rewrite baseline, and wipe with playlist', () async {
    final prefs = await SharedPreferences.getInstance();
    final secure = PersonalSecureStore();
    final store = await LocalStore.open(prefs, secure);
    await store.savePlaylists([playlistA, playlistB]);
    final a = title('a');
    final keys = recommendationKeys(a, null);
    await store.updatePersonalLibrary('a', (l) => l.observeMovies([a], testNow));
    secure.writes.clear();
    await store.updatePersonalLibrary(
      'a',
      (l) => l
          .setFeedback(keys, FeedbackChoice.hide, testNow)
          .rememberMetadata(a, const TitleMetadata(genres: ['Drama']))
          .addVodWatch(keys, const Duration(minutes: 10), testNow),
    );
    expect(secure.writes, ['personal-recommendations.v1.a']);
    expect(prefs.getKeys().any((k) => k.startsWith('personal')), isFalse);
    final reopened = await LocalStore.open(prefs, secure);
    expect(reopened.loadPersonalLibrary('a').feedbackFor(keys)?.choice, FeedbackChoice.hide);
    expect(reopened.loadPersonalLibrary('a').metadata, isNotEmpty);
    expect(reopened.loadPersonalLibrary('b').feedbackFor(keys), isNull);
    await reopened.deleteFavorites('a');
    expect(secure.values.containsKey('personal-recommendations.v1.a'), isFalse);
  });

  test('provider recommendations update immediately and remain scoped to current playlist and language', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = await LocalStore.open(prefs, PersonalSecureStore());
    await store.savePlaylists([playlistA, playlistB]);
    await store.saveActivePlaylistId('a');
    final seed = title('seed', genres: ['Crime'], category: 'de');
    final de = title('de', genres: ['Crime'], category: 'de');
    final tr = title('tr', genres: ['Crime'], category: 'tr');
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        localStoreProvider.overrideWithValue(store),
        imdbCatalogProvider.overrideWith(NoImdb.new),
        catalogProvider(ContentType.movie).overrideWith(
          (ref) async => Catalog(
            categories: const [
              Category(id: 'de', name: 'DE', type: ContentType.movie, language: 'de'),
              Category(id: 'tr', name: 'TR', type: ContentType.movie, language: 'tr'),
            ],
            channels: [seed, de, tr],
          ),
        ),
        catalogProvider(ContentType.series).overrideWith((ref) async => Catalog.empty),
      ],
    );
    addTearDown(container.dispose);
    await container.read(catalogProvider(ContentType.movie).future);
    await container.read(catalogProvider(ContentType.series).future);
    await container.read(imdbCatalogProvider.future);
    final notifier = container.read(personalLibraryProvider.notifier);
    await notifier.toggleFeedback(seed, FeedbackChoice.like);
    expect(container.read(recommendationsProvider).channels, [de]);
    await notifier.toggleFeedback(de, FeedbackChoice.hide);
    expect(container.read(recommendationsProvider).channels, isEmpty);
    await notifier.toggleFeedback(de, FeedbackChoice.hide);
    expect(container.read(recommendationsProvider).channels, [de]);
    await container.read(playlistsProvider.notifier).select('b');
    expect(container.read(recommendationFeedbackProvider(seed)), isNull);
    expect(container.read(recommendationsProvider).personalized, isFalse);
    await notifier.addVodWatch('a', seed, const Duration(minutes: 10), capturedKeys: recommendationKeys(seed, null));
    expect(container.read(recommendationsProvider).personalized, isFalse);
  });

  test('details arriving after a like enrich its persisted recommendations without changing feedback', () async {
    final prefs = await SharedPreferences.getInstance();
    final secure = PersonalSecureStore();
    final store = await LocalStore.open(prefs, secure);
    await store.savePlaylists([playlistA]);
    await store.saveActivePlaylistId('a');
    const seed = Channel(
      id: '1',
      name: 'Only a title',
      streamUrl: 'https://host/one',
      type: ContentType.movie,
      xtreamStreamId: 1,
    );
    final next = title('next', genres: ['Crime']);
    final api = DeferredDetailsApi();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        localStoreProvider.overrideWithValue(store),
        imdbCatalogProvider.overrideWith(NoImdb.new),
        xtreamApiProvider.overrideWithValue(api),
        catalogProvider(ContentType.movie).overrideWith((ref) async => Catalog(categories: [], channels: [seed, next])),
        catalogProvider(ContentType.series).overrideWith((ref) async => Catalog.empty),
      ],
    );
    addTearDown(container.dispose);
    await container.read(catalogProvider(ContentType.movie).future);
    await container.read(catalogProvider(ContentType.series).future);
    await container.read(personalLibraryProvider.notifier).toggleFeedback(seed, FeedbackChoice.like);
    final before = store.loadPersonalLibrary('a').feedbackFor(recommendationKeys(seed, null))!;
    final load = container.read(mediaDetailsProvider(seed).future);
    api.details.complete(const MediaDetails(genre: 'Crime', cast: 'One Actor, Another Actor'));
    await load;
    expect(container.read(recommendationsProvider).personalized, isTrue);
    final reopened = await LocalStore.open(prefs, secure);
    expect(reopened.loadPersonalLibrary('a').metadata[personalItemKey(seed)]?.genres, ['Crime']);
    final after = reopened.loadPersonalLibrary('a').feedbackFor(recommendationKeys(seed, null))!;
    expect(after.choice, before.choice);
    expect(after.at, before.at);
  });

  testWidgets('home recommendation row responds to hidden titles while the browse catalog remains intact', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = await SharedPreferences.getInstance();
    final store = await LocalStore.open(prefs, PersonalSecureStore());
    await store.savePlaylists([playlistA]);
    await store.saveActivePlaylistId('a');
    final seed = title('seed', genres: ['Crime'], category: 'de');
    final next = title('next', genres: ['Crime'], category: 'de');
    await store.updatePersonalLibrary(
      'a',
      (l) => l.setFeedback(recommendationKeys(seed, null), FeedbackChoice.like, testNow),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          localStoreProvider.overrideWithValue(store),
          imdbCatalogProvider.overrideWith(NoImdb.new),
          tmdbApiProvider.overrideWithValue(null),
          catalogProvider(ContentType.movie).overrideWith(
            (ref) async => Catalog(
              categories: const [Category(id: 'de', name: 'Filme', type: ContentType.movie, language: 'de')],
              channels: [seed, next],
            ),
          ),
          catalogProvider(ContentType.series).overrideWith((ref) async => Catalog.empty),
          catalogProvider(ContentType.live).overrideWith((ref) async => Catalog.empty),
          mediaDetailsProvider(seed).overrideWith((ref) async => MediaDetails.empty),
          mediaDetailsProvider(next).overrideWith((ref) async => MediaDetails.empty),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: HomeView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final rows = tester.widgetList<CategoryRow>(find.byType(CategoryRow));
    expect(rows.where((r) => r.title == 'Für dich empfohlen').single.channels, [next]);
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeView)));
    await container.read(personalLibraryProvider.notifier).toggleFeedback(next, FeedbackChoice.hide);
    await tester.pumpAndSettle();
    expect(
      tester.widgetList<CategoryRow>(find.byType(CategoryRow)).where((r) => r.title == 'Für dich empfohlen'),
      isEmpty,
    );
    expect(container.read(catalogProvider(ContentType.movie)).value!.channels, [seed, next]);
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 800.0, 1280.0]) {
    testWidgets('detail feedback is reversible and fits at $width pixels', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final prefs = await SharedPreferences.getInstance();
      final store = await LocalStore.open(prefs, PersonalSecureStore());
      await store.savePlaylists([playlistA]);
      await store.saveActivePlaylistId('a');
      final channel = title(
        'detail',
        name: 'A long title that remains fully usable in a narrow window',
        genres: ['Crime'],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            localStoreProvider.overrideWithValue(store),
            imdbCatalogProvider.overrideWith(NoImdb.new),
            tmdbApiProvider.overrideWithValue(null),
            tmdbTitleProvider(channel).overrideWith((ref) async => null),
            mediaDetailsProvider(channel)
                .overrideWith((ref) async => const MediaDetails(plot: 'A story.', genre: 'Crime', year: '2026')),
            catalogProvider(ContentType.movie)
                .overrideWith((ref) async => Catalog(categories: [], channels: [channel])),
            catalogProvider(ContentType.series).overrideWith((ref) async => Catalog.empty),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: DetailPage(channel: channel, queue: [channel]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final like = find.byKey(const ValueKey('feedback-like'));
      await tester.ensureVisible(like);
      await tester.tap(like);
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(tester.element(find.byType(DetailPage)));
      expect(container.read(recommendationFeedbackProvider(channel)), FeedbackChoice.like);
      final hide = find.byKey(const ValueKey('feedback-hide'));
      await tester.ensureVisible(hide);
      await tester.tap(hide);
      await tester.pumpAndSettle();
      expect(container.read(recommendationFeedbackProvider(channel)), FeedbackChoice.hide);
      await tester.tap(hide);
      await tester.pumpAndSettle();
      expect(container.read(recommendationFeedbackProvider(channel)), isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
