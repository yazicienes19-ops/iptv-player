import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/channel.dart';
import '../models/playlist_credentials.dart';
import 'secure_store.dart';
import 'personal_library.dart';

/// Playlists, Favoriten und Verlauf. Nur öffentliche Playlist-Metadaten liegen
/// in SharedPreferences; vollständige Senderdaten liegen im [SecureStore].
///
/// Beim Start lädt [open] alles einmal in den Speicher; danach liest die App
/// synchron und schreibt in beide Speicher.
class LocalStore {
  LocalStore._(this._prefs, this._secure, this._playlists);

  final SharedPreferences _prefs;
  final SecureStore _secure;
  List<PlaylistCredentials> _playlists;
  final Map<String, List<Channel>> _channels = {};
  final Map<String, PersonalLibrary> _personal = {};
  final Map<String, Future<void>> _personalWrites = {};
  int _personalGeneration = 0;

  static const _playlistsKey = 'playlists.v2';
  static const _legacyPlaylistsKey = 'playlists.v1';
  static const _activeKey = 'playlists.active.v1';
  static String _favoritesKey(String playlistId) => 'favorites.v2.$playlistId';
  static String _recentsKey(String playlistId) => 'recents.v1.$playlistId';
  static String _secretKey(String playlistId) => 'playlist.$playlistId';
  static String _personalKey(String playlistId) => 'personal-library.v1.$playlistId';
  static String _viewingKey(String playlistId) => 'personal-viewing.v1.$playlistId';
  static String _recommendationsKey(String playlistId) => 'personal-recommendations.v1.$playlistId';

  static Future<LocalStore> open(SharedPreferences prefs, SecureStore secure) async {
    await _migrateLegacy(prefs, secure);
    final raw = prefs.getString(_playlistsKey);
    final publicParts = raw == null
        ? const <Map<String, dynamic>>[]
        : (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    // Gezielt pro Playlist lesen: Der klassische Mac-Schlüsselbund lehnt
    // „alle Einträge samt Inhalt“ in einer Abfrage ab (errSecParam, -50).
    final playlists = <PlaylistCredentials>[];
    for (final json in publicParts) {
      final secret = await secure.read(_secretKey(json['id'] as String));
      playlists.add(PlaylistCredentials.fromJson({...json, ...?_decode(secret)}));
    }
    final store = LocalStore._(prefs, secure, playlists);
    for (final playlist in playlists) {
      await store._readChannels(_favoritesKey(playlist.id), playlist);
      await store._readChannels(_recentsKey(playlist.id), playlist);
      final parts = <String, dynamic>{};
      for (final key in [_personalKey(playlist.id), _viewingKey(playlist.id), _recommendationsKey(playlist.id)]) {
        final raw = await secure.read(key);
        if (raw == null) continue;
        try {
          parts.addAll(jsonDecode(raw) as Map<String, dynamic>);
        } on FormatException {
          // A damaged optional history must not prevent the playlist opening.
        } on TypeError {
          // Retain the original in the keychain until the next valid write.
        }
      }
      store._personal[playlist.id] = PersonalLibrary.fromJson(parts);
    }
    return store;
  }

  /// Frühere Versionen speicherten Passwörter im Klartext; sie wandern jetzt
  /// in den Schlüsselbund und werden aus SharedPreferences entfernt.
  static Future<void> _migrateLegacy(SharedPreferences prefs, SecureStore secure) async {
    final legacy = prefs.getString(_legacyPlaylistsKey);
    if (legacy == null) return;
    final playlists = (jsonDecode(legacy) as List).cast<Map<String, dynamic>>().map(PlaylistCredentials.fromJson);
    for (final p in playlists) {
      await secure.write(_secretKey(p.id), jsonEncode(_secretPart(p)));
    }
    await prefs.setString(_playlistsKey, jsonEncode([for (final p in playlists) _publicPart(p)]));
    await prefs.remove(_legacyPlaylistsKey);
    for (final key in prefs.getKeys().where((k) => k.startsWith('favorites.v1.')).toList()) {
      await prefs.remove(key);
    }
  }

  static Map<String, dynamic>? _decode(String? raw) => raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;

  static Map<String, dynamic> _publicPart(PlaylistCredentials p) => {
    'id': p.id,
    'name': p.name,
    'kind': p.kind.name,
    'localFilePath': p.localFilePath,
  };

  static Map<String, dynamic> _secretPart(PlaylistCredentials p) => {
    'serverUrl': p.serverUrl,
    'username': p.username,
    'password': p.password,
    'm3uUrl': p.m3uUrl,
  };

  List<PlaylistCredentials> loadPlaylists() => List.unmodifiable(_playlists);

  Future<void> savePlaylists(List<PlaylistCredentials> playlists) async {
    final removed = _playlists.where((old) => playlists.every((p) => p.id != old.id));
    for (final p in removed) {
      await _secure.delete(_secretKey(p.id));
    }
    for (final p in playlists) {
      await _secure.write(_secretKey(p.id), jsonEncode(_secretPart(p)));
    }
    _playlists = List.of(playlists);
    await _prefs.setString(_playlistsKey, jsonEncode([for (final p in playlists) _publicPart(p)]));
  }

  String? loadActivePlaylistId() => _prefs.getString(_activeKey);

  Future<void> saveActivePlaylistId(String? id) =>
      id == null ? _prefs.remove(_activeKey) : _prefs.setString(_activeKey, id);

  /// Favoriten werden komplett gespeichert, damit der Favoriten-Tab ohne
  /// geladenen Katalog sofort angezeigt werden kann. Auch IDs und Logo-URLs
  /// können Zugangsdaten enthalten, deshalb wird der ganze Eintrag verschlüsselt.
  List<Channel> loadFavorites(PlaylistCredentials playlist) =>
      List.unmodifiable(_channels[_favoritesKey(playlist.id)] ?? []);

  Future<void> saveFavorites(PlaylistCredentials playlist, List<Channel> favorites) =>
      _saveChannels(_favoritesKey(playlist.id), favorites);

  /// Zuletzt gesehene Live-Sender (neueste zuerst), ebenfalls verschlüsselt.
  List<Channel> loadRecents(PlaylistCredentials playlist) =>
      List.unmodifiable(_channels[_recentsKey(playlist.id)] ?? []);

  Future<void> saveRecents(PlaylistCredentials playlist, List<Channel> recents) =>
      _saveChannels(_recentsKey(playlist.id), recents);

  Future<void> _readChannels(String key, PlaylistCredentials playlist) async {
    final protected = await _secure.read(key);
    final legacy = _prefs.getString(key);
    final raw = protected ?? legacy;
    if (raw == null) return;
    final redactor = UrlRedactor.forPlaylist(playlist);
    final channels = (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(
          (json) => Channel.fromJson(
            protected != null
                ? json
                : {
                    ...json,
                    'id': redactor.restore(json['id'] as String),
                    'streamUrl': redactor.restore(json['streamUrl'] as String),
                  },
          ),
        )
        .toList();
    _channels[key] = channels;
    if (legacy != null) {
      // Alte Klartext-IDs erst nach erfolgreichem Schreiben in die Keychain entfernen.
      if (protected == null) {
        await _secure.write(key, jsonEncode([for (final channel in channels) channel.toJson()]));
      }
      await _prefs.remove(key);
    }
  }

  Future<void> _saveChannels(String key, List<Channel> channels) async {
    _channels[key] = List.of(channels);
    await _secure.write(key, jsonEncode([for (final channel in channels) channel.toJson()]));
    await _prefs.remove(key);
  }

  /// Favoriten und Verlauf einer gelöschten Playlist entfernen.
  Future<void> deleteFavorites(String playlistId) async {
    await _personalWrites[playlistId]?.catchError((Object _) {});
    _personal.remove(playlistId);
    for (final key in [
      _favoritesKey(playlistId),
      _recentsKey(playlistId),
      _personalKey(playlistId),
      _viewingKey(playlistId),
      _recommendationsKey(playlistId),
    ]) {
      _channels.remove(key);
      await _secure.delete(key);
      await _prefs.remove(key);
    }
  }

  PersonalLibrary loadPersonalLibrary(String playlistId) => _personal[playlistId] ?? const PersonalLibrary();

  /// Update in memory atomically, then serialize writes. Playlist identity can
  /// contain URL credentials, therefore even the identity-only history is kept
  /// in the keychain, never SharedPreferences.
  Future<void> updatePersonalLibrary(String playlistId, PersonalLibrary Function(PersonalLibrary) change) {
    if (!_playlists.any((playlist) => playlist.id == playlistId)) return Future.value();
    final before = loadPersonalLibrary(playlistId);
    final after = change(before);
    if (identical(before, after)) return Future.value();
    _personal[playlistId] = after;
    // A large movie baseline is written only when the catalog changes. The
    // frequent playback flush must serialize only the small viewing totals.
    final writes = <String, String>{};
    if (before.hasMovieBaseline != after.hasMovieBaseline || !identical(before.firstSeen, after.firstSeen)) {
      writes[_personalKey(playlistId)] = jsonEncode({
        'hasMovieBaseline': after.hasMovieBaseline,
        'firstSeen': after.firstSeen,
      });
    }
    if (!identical(before.viewing, after.viewing)) {
      writes[_viewingKey(playlistId)] = jsonEncode({
        'viewing': {for (final entry in after.viewing.entries) entry.key: entry.value.toJson()},
      });
    }
    if (!identical(before.feedback, after.feedback) ||
        !identical(before.vodViewing, after.vodViewing) ||
        !identical(before.metadata, after.metadata)) {
      writes[_recommendationsKey(playlistId)] = jsonEncode({
        'metadata': {for (final entry in after.metadata.entries) entry.key: entry.value.toJson()},
        'feedback': {for (final entry in after.feedback.entries) entry.key: entry.value.toJson()},
        'vodViewing': {for (final entry in after.vodViewing.entries) entry.key: entry.value.toJson()},
      });
    }
    final generation = _personalGeneration;
    final write = (_personalWrites[playlistId] ?? Future<void>.value()).catchError((Object _) {}).then((_) async {
      if (generation != _personalGeneration || !_playlists.any((playlist) => playlist.id == playlistId)) return;
      for (final entry in writes.entries) {
        await _secure.write(entry.key, entry.value);
      }
    });
    _personalWrites[playlistId] = write;
    return write;
  }

  static const _tmdbKey = 'tmdb.apiKey';

  /// TMDB-Schlüssel; wie Zugangsdaten nur im Schlüsselbund.
  Future<String?> readTmdbKey() => _secure.read(_tmdbKey);

  Future<void> writeTmdbKey(String? key) =>
      key == null || key.trim().isEmpty ? _secure.delete(_tmdbKey) : _secure.write(_tmdbKey, key.trim());

  /// Panik-Knopf: entfernt Playlists, Favoriten, Einstellungen und Schlüsselbund.
  Future<void> wipe() async {
    _personalGeneration++;
    _playlists = [];
    _channels.clear();
    _personal.clear();
    await Future.wait(_personalWrites.values.map((write) => write.catchError((Object _) {})));
    _personalWrites.clear();
    await _prefs.clear();
    await _secure.deleteAll();
  }
}

/// Ersetzt Zugangsdaten in URLs durch Platzhalter und zurück.
class UrlRedactor {
  UrlRedactor(this._secrets);

  /// Platzhalter → echter Wert. Sehr kurze Werte (z. B. „1“) werden nicht
  /// ersetzt, sonst würden zufällige Zeichen in Pfaden mitgetroffen.
  final Map<String, String> _secrets;

  factory UrlRedactor.forPlaylist(PlaylistCredentials p) {
    final secrets = <String, String>{};
    void add(String token, String? value) {
      if (value != null && value.length >= 3) secrets[token] = value;
    }

    add('{{server}}', p.isXtream ? p.normalizedServer : null);
    add('{{user}}', p.username);
    add('{{pass}}', p.password);
    final m3u = Uri.tryParse(p.m3uUrl ?? '');
    if (m3u != null) {
      add('{{user}}', m3u.queryParameters['username'] ?? m3u.queryParameters['user']);
      add('{{pass}}', m3u.queryParameters['password'] ?? m3u.queryParameters['pass']);
      add('{{token}}', m3u.queryParameters['token']);
    }
    // Auch in kodierter Form, wie sie in Stream-Pfaden vorkommen kann
    // (Panels kodieren Sonderzeichen unterschiedlich, z. B. „!“ roh oder als %21).
    for (final entry in secrets.entries.toList()) {
      final variants = {Uri.encodeComponent(entry.value), _percentEncodeAll(entry.value)}..remove(entry.value);
      for (final (i, encoded) in variants.indexed) {
        secrets['${entry.key.substring(0, entry.key.length - 2)}:enc$i}}'] = encoded;
      }
    }
    return UrlRedactor(secrets);
  }

  static String _percentEncodeAll(String value) => value.runes.map((r) {
    final char = String.fromCharCode(r);
    if (RegExp(r'[A-Za-z0-9\-._~]').hasMatch(char)) return char;
    return Uri.encodeComponent(char).replaceAllMapped(RegExp(r'^[^%]+$'), (m) {
      return m[0]!.codeUnits.map((c) => '%${c.toRadixString(16).toUpperCase().padLeft(2, '0')}').join();
    });
  }).join();

  String redact(String url) {
    var result = url;
    // Längste Werte zuerst, damit z. B. der Server vor einem enthaltenen Benutzernamen ersetzt wird.
    final entries = _secrets.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));
    for (final e in entries) {
      result = result.replaceAll(e.value, e.key);
    }
    return result;
  }

  String restore(String url) {
    var result = url;
    for (final e in _secrets.entries) {
      result = result.replaceAll(e.key, e.value);
    }
    return result;
  }
}
