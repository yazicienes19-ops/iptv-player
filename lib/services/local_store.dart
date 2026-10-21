import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/channel.dart';
import '../models/playlist_credentials.dart';

/// Dünne Schicht über SharedPreferences für Playlists und Favoriten.
class LocalStore {
  LocalStore(this._prefs);

  final SharedPreferences _prefs;

  static const _playlistsKey = 'playlists.v1';
  static const _activeKey = 'playlists.active.v1';
  static String _favoritesKey(String playlistId) => 'favorites.v1.$playlistId';

  List<PlaylistCredentials> loadPlaylists() {
    final raw = _prefs.getString(_playlistsKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>().map(PlaylistCredentials.fromJson).toList();
  }

  Future<void> savePlaylists(List<PlaylistCredentials> playlists) =>
      _prefs.setString(_playlistsKey, jsonEncode(playlists.map((p) => p.toJson()).toList()));

  String? loadActivePlaylistId() => _prefs.getString(_activeKey);

  Future<void> saveActivePlaylistId(String? id) =>
      id == null ? _prefs.remove(_activeKey) : _prefs.setString(_activeKey, id);

  /// Favoriten werden komplett gespeichert, damit der Favoriten-Tab ohne
  /// geladenen Katalog sofort angezeigt werden kann.
  List<Channel> loadFavorites(String playlistId) {
    final raw = _prefs.getString(_favoritesKey(playlistId));
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>().map(Channel.fromJson).toList();
  }

  Future<void> saveFavorites(String playlistId, List<Channel> favorites) =>
      _prefs.setString(_favoritesKey(playlistId), jsonEncode(favorites.map((c) => c.toJson()).toList()));

  Future<void> deleteFavorites(String playlistId) => _prefs.remove(_favoritesKey(playlistId));
}
