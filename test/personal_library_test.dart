import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iptv_player/models/catalog.dart';
import 'package:iptv_player/models/category.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/models/content_type.dart';
import 'package:iptv_player/models/playlist_credentials.dart';
import 'package:iptv_player/providers/app_providers.dart';
import 'package:iptv_player/services/local_store.dart';
import 'package:iptv_player/services/personal_library.dart';
import 'package:iptv_player/services/secure_store.dart';
import 'package:iptv_player/services/xtream_api.dart';

const playlistA = PlaylistCredentials(
  id: 'a',
  name: 'A',
  kind: PlaylistKind.xtream,
  serverUrl: 'http://example.test',
  username: 'test',
  password: 'secret',
);
const playlistB = PlaylistCredentials(
  id: 'b',
  name: 'B',
  kind: PlaylistKind.xtream,
  serverUrl: 'http://other.test',
  username: 'test',
  password: 'secret',
);
final now = DateTime.utc(2026, 10, 24, 12);

Channel movie(String id, {String? added, String? url, String? category}) => Channel(
  id: id,
  name: 'Film $id',
  streamUrl: url ?? 'http://example.test/secret/$id.mp4',
  type: ContentType.movie,
  addedAt: added,
  categoryId: category,
);
Channel live(String id, {String? name, String? category}) => Channel(
  id: id,
  name: name ?? 'Sender $id',
  streamUrl: 'http://example.test/secret/$id.ts',
  type: ContentType.live,
  categoryId: category,
);

class PersonalSecureStore extends SecureStore {
  final values = <String, String>{};
  final writes = <String>[];
  Completer<void>? gate;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (key.startsWith('personal-')) await gate?.future;
    writes.add(key);
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<void> deleteAll() async => values.clear();
}

class CatalogApi extends XtreamApi {
  CatalogApi(this.movies, this.liveChannels) : super(playlistA, dio: Dio());
  List<Channel> movies;
  List<Channel> liveChannels;
  bool fail = false;
  @override
  Future<Catalog> getCatalog(ContentType type) async {
    if (fail) throw StateError('offline');
    return Catalog(
      categories: [
        Category(id: 'de', name: 'Auswahl', type: type, language: 'de'),
        Category(id: 'tr', name: 'Auswahl', type: type, language: 'tr'),
      ],
      channels: type == ContentType.movie
          ? movies
          : type == ContentType.live
          ? liveChannels
          : [],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('upload dates accept epoch seconds, milliseconds and ISO, rejecting release years and invalid/future dates', () {
    final date = now.subtract(const Duration(days: 2));
    expect(parseAddedAt(date.millisecondsSinceEpoch ~/ 1000, now: now), date);
    expect(parseAddedAt('${date.millisecondsSinceEpoch}', now: now), date);
    expect(parseAddedAt(date.toIso8601String(), now: now), date);
    for (final invalid in [
      null,
      '',
      'invalid',
      '2024',
      '0',
      'NaN',
      '2026-02-31',
      '2026-13-01',
      now.add(const Duration(days: 1)).toIso8601String(),
    ]) {
      expect(parseAddedAt(invalid, now: now), isNull, reason: '$invalid');
    }
  });

  test('first successful catalog is a baseline; recent provider additions appear immediately', () {
    final unknown = movie('old');
    final recent = movie('recent', added: now.subtract(const Duration(days: 2)).toIso8601String());
    final oldUpload = movie('upload-old', added: now.subtract(const Duration(days: 40)).toIso8601String());
    final library = const PersonalLibrary().observeMovies([unknown, recent, oldUpload], now);
    expect(library.hasMovieBaseline, isTrue);
    expect(library.newMovies([unknown, recent, oldUpload], now), [recent]);
    expect(library.newMovies([unknown], now), isEmpty);
  });

  test('later catalog additions use first seen, provider dates take precedence, removed entries disappear', () {
    final original = movie('old');
    var library = const PersonalLibrary().observeMovies([original], now);
    final next = now.add(const Duration(days: 1));
    final added = movie('new');
    final recent = movie('recent', added: now.subtract(const Duration(days: 2)).toIso8601String());
    final providerOld = movie('dated-old', added: now.subtract(const Duration(days: 60)).toIso8601String());
    library = library.observeMovies([original, recent, providerOld, added], next);
    expect(library.newMovies([original, recent, providerOld, added], next), [added, recent]);
    expect(library.newMovies([original, providerOld], next), isEmpty);
    expect(library.newMovies([added], next.add(const Duration(days: 31))), isEmpty);
    library = library.observeMovies([], next);
    library = library.observeMovies([original], next);
    expect(library.newMovies([original], next), isEmpty);
  });

  test('M3U reordering preserves identity while new stream URLs count as additions', () {
    final first = movie('0|one', url: 'http://host.test/one.mp4');
    final second = movie('1|two', url: 'http://host.test/two.mp4');
    var library = const PersonalLibrary().observeMovies([first, second], now);
    final newEntry = movie('0|new', url: 'http://host.test/new.mp4');
    final moved = movie('1|one', url: first.streamUrl);
    library = library.observeMovies([
      newEntry,
      moved,
      movie('2|two', url: second.streamUrl),
    ], now.add(const Duration(minutes: 5)));
    expect(library.newMovies([newEntry, moved, second], now.add(const Duration(minutes: 6))), [newEntry]);
  });

  test('most watched ranks real viewing duration, ignores short zaps, and only returns current channels', () {
    final a = live('a');
    final b = live('b');
    final zap = live('zap');
    var library = const PersonalLibrary();
    library = library.addWatch(a, const Duration(seconds: 20), now).addWatch(a, const Duration(seconds: 20), now);
    library = library.addWatch(b, const Duration(minutes: 3), now).addWatch(zap, const Duration(seconds: 29), now);
    expect(library.mostWatched([a, b, zap]), [b, a]);
    expect(library.mostWatched([a, zap]), [a]);
    expect(library.mostWatched([b, b]), [b]);
    expect(PersonalLibrary.fromJson(library.toJson()).mostWatched([a, b]), [b, a]);
  });

  test('watch accumulator excludes buffering, pauses, seek jumps, suspended gaps and playback rate inflation', () {
    final timer = LiveWatchAccumulator();
    void sample(int position, int elapsed, {bool eligible = true, double rate = 1}) => timer.sample(
      position: Duration(milliseconds: position),
      elapsed: Duration(milliseconds: elapsed),
      eligible: eligible,
      rate: rate,
    );
    sample(0, 0);
    sample(1000, 1000);
    sample(2000, 2000);
    sample(2000, 3000, eligible: false); // paused/buffering
    sample(2000, 10000);
    sample(3000, 11000);
    sample(23000, 12000); // seek: no credit
    sample(24000, 13000);
    sample(1000, 14000); // backward seek
    sample(2000, 15000);
    sample(50000, 60000); // app asleep, no credit
    sample(52000, 61000, rate: 2);
    expect(timer.take(), const Duration(seconds: 6));
    expect(timer.take(), Duration.zero);
    timer.resetSample();
    sample(54000, 62000);
    expect(timer.take(), Duration.zero);
  });

  test('personal history is encrypted, isolated by playlist, survives restart, and is removed with playlist', () async {
    final prefs = await SharedPreferences.getInstance();
    final secure = PersonalSecureStore();
    final store = await LocalStore.open(prefs, secure);
    await store.savePlaylists([playlistA, playlistB]);
    final channel = live('same-id');
    await store.updatePersonalLibrary(
      'a',
      (library) => library.addWatch(channel, const Duration(minutes: 1), now).observeMovies([movie('old')], now),
    );
    expect(store.loadPersonalLibrary('b').mostWatched([channel]), isEmpty);
    expect([for (final key in prefs.getKeys()) prefs.get(key)].join(), isNot(contains('secret')));
    final reopened = await LocalStore.open(prefs, secure);
    expect(reopened.loadPersonalLibrary('a').mostWatched([channel]), [channel]);
    expect(reopened.loadPersonalLibrary('a').hasMovieBaseline, isTrue);
    await reopened.deleteFavorites('a');
    expect(secure.values.containsKey('personal-library.v1.a'), isFalse);
    expect(secure.values.containsKey('personal-viewing.v1.a'), isFalse);
  });

  test('watch flushes never rewrite a large movie baseline and unchanged catalogs do not write', () async {
    final prefs = await SharedPreferences.getInstance();
    final secure = PersonalSecureStore();
    final store = await LocalStore.open(prefs, secure);
    await store.savePlaylists([playlistA]);
    final movies = List.generate(1000, (index) => movie('$index'));
    await store.updatePersonalLibrary('a', (library) => library.observeMovies(movies, now));
    final baseline = secure.values['personal-library.v1.a'];
    secure.writes.clear();
    await store.updatePersonalLibrary('a', (library) => library.observeMovies(movies, now));
    expect(secure.writes, isEmpty);
    for (var flush = 0; flush < 3; flush++) {
      await store.updatePersonalLibrary(
        'a',
        (library) => library.addWatch(live('a'), const Duration(seconds: 15), now),
      );
    }
    expect(secure.writes, everyElement('personal-viewing.v1.a'));
    expect(secure.writes.length, 3);
    expect(secure.values['personal-library.v1.a'], baseline);
    expect(secure.values['personal-viewing.v1.a']!.length, lessThan(300));
    final reopened = await LocalStore.open(prefs, secure);
    expect(reopened.loadPersonalLibrary('a').firstSeen.length, 1000);
    expect(reopened.loadPersonalLibrary('a').mostWatched([live('a')]).single.id, 'a');
  });

  test('panic wipe waits for outstanding history writes and prevents delayed session resurrection', () async {
    final prefs = await SharedPreferences.getInstance();
    final secure = PersonalSecureStore();
    final store = await LocalStore.open(prefs, secure);
    await store.savePlaylists([playlistA]);
    secure.gate = Completer<void>();
    final write = store.updatePersonalLibrary(
      'a',
      (library) => library.addWatch(live('a'), const Duration(minutes: 1), now),
    );
    await Future<void>.delayed(Duration.zero);
    final wipe = store.wipe();
    secure.gate!.complete();
    await Future.wait([write, wipe]);
    await store.updatePersonalLibrary('a', (library) => library.addWatch(live('a'), const Duration(minutes: 1), now));
    expect(secure.values, isEmpty);
    expect(store.loadPersonalLibrary('a').viewing, isEmpty);
  });

  test(
    'real catalog provider records successful full snapshots, rows respect language and ignore browse search',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = await LocalStore.open(prefs, PersonalSecureStore());
      await store.savePlaylists([playlistA, playlistB]);
      await store.saveActivePlaylistId('a');
      final a = live('a', category: 'de');
      final b = live('b', category: 'tr');
      final api = CatalogApi([movie('old', category: 'de')], [a, b]);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          localStoreProvider.overrideWithValue(store),
          xtreamApiProvider.overrideWithValue(api),
        ],
      );
      addTearDown(container.dispose);
      await container.read(catalogProvider(ContentType.movie).future);
      await container.read(catalogProvider(ContentType.live).future);
      await container.read(languageFilterProvider.notifier).select(null);
      final personal = container.read(personalLibraryProvider.notifier);
      await personal.addWatch('a', a, const Duration(seconds: 40));
      await personal.addWatch('a', b, const Duration(minutes: 2));
      expect(container.read(mostWatchedChannelsProvider), [b, a]);
      expect(container.read(newMoviesProvider), isEmpty);
      api.movies = [movie('old', category: 'de'), movie('new-de', category: 'de'), movie('new-tr', category: 'tr')];
      container.invalidate(catalogProvider(ContentType.movie));
      await container.read(catalogProvider(ContentType.movie).future);
      expect(container.read(newMoviesProvider).map((channel) => channel.id), containsAll(['new-de', 'new-tr']));
      await container.read(languageFilterProvider.notifier).select('de');
      expect(container.read(mostWatchedChannelsProvider), [a]);
      container.read(searchQueryProvider(AppSection.movies).notifier).set('not-in-catalog');
      container.read(searchQueryProvider(AppSection.live).notifier).set('not-in-catalog');
      expect(container.read(mostWatchedChannelsProvider), [a]);
      expect(container.read(newMoviesProvider).map((channel) => channel.id), ['new-de']);
      api.fail = true;
      container.invalidate(catalogProvider(ContentType.movie));
      await expectLater(container.read(catalogProvider(ContentType.movie).future), throwsStateError);
      expect(store.loadPersonalLibrary('a').firstSeen.length, 3);
      api.fail = false;
      await container.read(playlistsProvider.notifier).select('b');
      await container.read(catalogProvider(ContentType.movie).future);
      await container.read(catalogProvider(ContentType.live).future);
      expect(container.read(mostWatchedChannelsProvider), isEmpty);
      expect(container.read(newMoviesProvider), isEmpty);
      // A late flush from the previous session must not leak into this account.
      await personal.addWatch('a', a, const Duration(seconds: 40));
      expect(container.read(mostWatchedChannelsProvider), isEmpty);
      await container.read(playlistsProvider.notifier).select('a');
      await container.read(catalogProvider(ContentType.movie).future);
      await container.read(catalogProvider(ContentType.live).future);
      expect(container.read(mostWatchedChannelsProvider), [a]);
      expect(container.read(newMoviesProvider).map((channel) => channel.id), ['new-de']);
    },
  );
}
