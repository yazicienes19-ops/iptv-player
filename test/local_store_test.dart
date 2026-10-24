import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/models/content_type.dart';
import 'package:iptv_player/models/playlist_credentials.dart';
import 'package:iptv_player/services/local_store.dart';
import 'package:iptv_player/services/secure_store.dart';

class MemorySecureStore extends SecureStore {
  final values = <String, String>{};
  bool failWrites = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('Keychain nicht verfügbar');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const playlist = PlaylistCredentials(
    id: 'm',
    name: 'M3U',
    kind: PlaylistKind.m3uUrl,
    m3uUrl: 'http://tv.example/get.php?username=anna&password=secret',
  );
  const channel = Channel(
    id: '0|http://tv.example/anna/secret/1.ts',
    name: 'Test',
    streamUrl: 'http://tv.example/anna/secret/1.ts',
    type: ContentType.live,
    logo: 'http://tv.example/anna/secret/logo.png',
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Favoriten und Verlauf speichern auch IDs und Logos nur verschlüsselt', () async {
    final prefs = await SharedPreferences.getInstance();
    final secure = MemorySecureStore();
    final store = await LocalStore.open(prefs, secure);
    await store.savePlaylists([playlist]);
    await store.saveFavorites(playlist, [channel]);
    await store.saveRecents(playlist, [channel]);

    expect(prefs.getString('favorites.v2.m'), isNull);
    expect(prefs.getString('recents.v1.m'), isNull);
    expect([for (final key in prefs.getKeys()) prefs.get(key)].join(), isNot(contains('secret')));
    final reopened = await LocalStore.open(prefs, secure);
    expect(reopened.loadFavorites(playlist).single.id, channel.id);
    expect(reopened.loadFavorites(playlist).single.logo, channel.logo);
    expect(reopened.loadRecents(playlist).single.streamUrl, channel.streamUrl);
    await reopened.deleteFavorites(playlist.id);
    expect(secure.values.containsKey('favorites.v2.m'), isFalse);
    expect(secure.values.containsKey('recents.v1.m'), isFalse);
  });

  test('Migriert bestehende Favoriten und Verlauf ohne Verlust der Sender-IDs', () async {
    final prefs = await SharedPreferences.getInstance();
    final secure = MemorySecureStore();
    final store = await LocalStore.open(prefs, secure);
    await store.savePlaylists([playlist]);
    final legacy = jsonEncode([
      {...channel.toJson(), 'streamUrl': 'http://tv.example/{{user}}/{{pass}}/1.ts'},
    ]);
    await prefs.setString('favorites.v2.m', legacy);
    await prefs.setString('recents.v1.m', legacy);

    final migrated = await LocalStore.open(prefs, secure);

    expect(prefs.getString('favorites.v2.m'), isNull);
    expect(prefs.getString('recents.v1.m'), isNull);
    expect(migrated.loadFavorites(playlist).single.id, channel.id);
    expect(migrated.loadFavorites(playlist).single.streamUrl, channel.streamUrl);
    expect(migrated.loadRecents(playlist).single, channel);
    expect(secure.values['favorites.v2.m'], contains(channel.id));
  });

  test('Fehlgeschlagene Migration entfernt die bisherigen Daten nicht', () async {
    final prefs = await SharedPreferences.getInstance();
    final secure = MemorySecureStore();
    final store = await LocalStore.open(prefs, secure);
    await store.savePlaylists([playlist]);
    final legacy = jsonEncode([channel.toJson()]);
    await prefs.setString('favorites.v2.m', legacy);
    secure.failWrites = true;

    await expectLater(LocalStore.open(prefs, secure), throwsStateError);
    expect(prefs.getString('favorites.v2.m'), legacy);
  });
}
