import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iptv_player/models/catalog.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/models/content_type.dart';
import 'package:iptv_player/services/local_store.dart';
import 'package:iptv_player/services/personal_library.dart';

import 'personal_library_test.dart' show PersonalSecureStore, live, movie, now, playlistA;

Channel episode(String id) => Channel(
  id: id,
  name: 'Folge $id',
  streamUrl: 'http://example.test/secret/$id.mkv',
  type: ContentType.series,
  seriesId: 'show',
);

const hour = Duration(hours: 1);

void main() {
  test('Merkt sich die Stelle erst ab 30 s und nie bei Live-Sendern', () {
    var library = const PersonalLibrary();
    library = library.saveResume(movie('m'), const Duration(seconds: 20), hour, now);
    expect(library.resumeFor(movie('m')), isNull);
    library = library.saveResume(live('l'), const Duration(minutes: 5), hour, now);
    expect(library.resume, isEmpty);
    library = library.saveResume(movie('m'), const Duration(minutes: 42), hour, now);
    expect(library.resumeFor(movie('m'))!.position, const Duration(minutes: 42));
    expect(remainingLabel(library.resumeFor(movie('m'))!.remaining), 'noch 18 Min.');
    // Kurzes Reinschauen von vorne überschreibt die alte Stelle nicht.
    library = library.saveResume(movie('m'), const Duration(seconds: 10), hour, now);
    expect(library.resumeFor(movie('m'))!.position, const Duration(minutes: 42));
  });

  test('Kurz vor dem Ende gilt der Titel als gesehen', () {
    final library = const PersonalLibrary().saveResume(movie('m'), const Duration(minutes: 59), hour, now);
    expect(library.resumeFor(movie('m'))!.done, isTrue);
    expect(library.clearResume(movie('m')).resumeFor(movie('m')), isNull);
  });

  test('Serie geht bei der angefangenen oder der nächsten Folge weiter', () {
    final seasons = [
      Season(
        number: 1,
        episodes: [
          Episode(channel: episode('1'), number: 1),
          Episode(channel: episode('2'), number: 2),
        ],
      ),
      Season(number: 2, episodes: [Episode(channel: episode('3'), number: 1)]),
    ];
    var library = const PersonalLibrary();
    expect(continueEpisode(library, seasons), isNull);

    library = library.saveResume(episode('1'), const Duration(minutes: 10), hour, now);
    expect(continueEpisode(library, seasons)!.episode.channel.id, '1');
    expect(continueEpisode(library, seasons)!.point!.position, const Duration(minutes: 10));

    library = library.saveResume(episode('2'), hour, hour, now.add(const Duration(minutes: 1)));
    final next = continueEpisode(library, seasons)!;
    expect(next.episode.channel.id, '3');
    expect(next.season.number, 2);
    expect(next.point, isNull);

    library = library.saveResume(episode('3'), hour, hour, now.add(const Duration(minutes: 2)));
    expect(continueEpisode(library, seasons), isNull);
  });

  test('Fortsetzungsstellen überleben einen Neustart', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secure = PersonalSecureStore();
    final store = await LocalStore.open(prefs, secure);
    await store.savePlaylists([playlistA]);
    await store.updatePersonalLibrary(
      playlistA.id,
      (library) => library.saveResume(movie('m'), const Duration(minutes: 7), hour, now),
    );
    final reopened = await LocalStore.open(prefs, secure);
    expect(reopened.loadPersonalLibrary(playlistA.id).resumeFor(movie('m'))!.position, const Duration(minutes: 7));
    expect(prefs.getKeys().any((key) => key.contains('resume')), isFalse);
  });
}
