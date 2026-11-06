import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/models/content_type.dart';
import 'package:iptv_player/services/local_store.dart';
import 'package:iptv_player/services/personal_library.dart';

import 'personal_library_test.dart' show PersonalSecureStore, playlistA;

const _movie = Channel(
  id: '1',
  name: 'Dune',
  streamUrl: 'https://x.test/1.mkv',
  type: ContentType.movie,
  xtreamStreamId: 1,
);

void main() {
  test('Infos beim Öffnen: sofort im Speicher, gesammelt und nur einmal in den Schlüsselbund', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secure = PersonalSecureStore();
    final store = await LocalStore.open(prefs, secure);
    await store.savePlaylists([playlistA]);
    secure.writes.clear();

    LocalStore.deferredDelay = const Duration(milliseconds: 30);
    addTearDown(() => LocalStore.deferredDelay = const Duration(seconds: 8));
    for (var i = 0; i < 20; i++) {
      store.updatePersonalLibraryDeferred(
        'a',
        (l) => l.rememberMetadata(
          Channel(
            id: '$i',
            name: 'Titel $i',
            streamUrl: 'https://x.test/$i.mkv',
            type: ContentType.movie,
            xtreamStreamId: i,
          ),
          TitleMetadata(genres: const ['Drama'], cast: ['Person $i']),
        ),
      );
    }
    // Sofort nutzbar, aber noch kein einziger Schlüsselbund-Zugriff.
    expect(store.loadPersonalLibrary('a').metadata, hasLength(20));
    expect(secure.writes, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(secure.writes.where((k) => k.contains('recommendations')), hasLength(1));
  });

  test('ein normales Speichern nimmt zurückgestellte Infos gleich mit', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secure = PersonalSecureStore();
    final store = await LocalStore.open(prefs, secure);
    await store.savePlaylists([playlistA]);
    store.updatePersonalLibraryDeferred(
      'a',
      (l) => l.rememberMetadata(_movie, const TitleMetadata(genres: ['Sci-Fi'])),
    );
    await store.updatePersonalLibrary(
      'a',
      (l) => l.saveResume(_movie, const Duration(minutes: 5), const Duration(minutes: 90), DateTime(2026)),
    );
    final reopened = await LocalStore.open(prefs, secure);
    expect(reopened.loadPersonalLibrary('a').metadata, isNotEmpty);
    await store.flushDeferred();
  });
}
