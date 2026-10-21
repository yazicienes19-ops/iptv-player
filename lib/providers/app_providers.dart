import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/catalog.dart';
import '../models/category.dart';
import '../models/channel.dart';
import '../models/channel_name.dart';
import '../models/content_type.dart';
import '../models/epg_item.dart';
import '../models/playlist_credentials.dart';
import '../services/local_store.dart';
import '../services/m3u_parser.dart';
import '../services/playlist_loader.dart';
import '../services/xtream_api.dart';

/// Wird in `main()` mit der geladenen Instanz überschrieben.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider muss überschrieben werden'),
);

final localStoreProvider = Provider((ref) => LocalStore(ref.watch(sharedPreferencesProvider)));

final playlistLoaderProvider = Provider((ref) => PlaylistLoader());

// ---------------------------------------------------------------------------
// Playlists
// ---------------------------------------------------------------------------

class PlaylistsState {
  const PlaylistsState({required this.playlists, required this.activeId});

  final List<PlaylistCredentials> playlists;
  final String? activeId;

  PlaylistCredentials? get active {
    for (final p in playlists) {
      if (p.id == activeId) return p;
    }
    return playlists.isEmpty ? null : playlists.first;
  }
}

class PlaylistsNotifier extends Notifier<PlaylistsState> {
  LocalStore get _store => ref.read(localStoreProvider);

  @override
  PlaylistsState build() {
    final store = ref.watch(localStoreProvider);
    return PlaylistsState(playlists: store.loadPlaylists(), activeId: store.loadActivePlaylistId());
  }

  Future<void> add(PlaylistCredentials playlist) async {
    state = PlaylistsState(playlists: [...state.playlists, playlist], activeId: playlist.id);
    await _store.savePlaylists(state.playlists);
    await _store.saveActivePlaylistId(playlist.id);
  }

  Future<void> select(String id) async {
    state = PlaylistsState(playlists: state.playlists, activeId: id);
    await _store.saveActivePlaylistId(id);
  }

  Future<void> remove(PlaylistCredentials playlist) async {
    final remaining = state.playlists.where((p) => p.id != playlist.id).toList();
    final activeId = state.activeId == playlist.id ? remaining.firstOrNull?.id : state.activeId;
    state = PlaylistsState(playlists: remaining, activeId: activeId);
    await _store.savePlaylists(remaining);
    await _store.saveActivePlaylistId(activeId);
    await _store.deleteFavorites(playlist.id);
    await PlaylistLoader.deleteImportedFile(playlist);
  }
}

final playlistsProvider = NotifierProvider<PlaylistsNotifier, PlaylistsState>(PlaylistsNotifier.new);

final activePlaylistProvider = Provider<PlaylistCredentials?>((ref) => ref.watch(playlistsProvider).active);

final xtreamApiProvider = Provider<XtreamApi?>((ref) {
  final playlist = ref.watch(activePlaylistProvider);
  return playlist != null && playlist.isXtream ? XtreamApi(playlist) : null;
});

// ---------------------------------------------------------------------------
// Kataloge
// ---------------------------------------------------------------------------

/// Die komplette, im Isolate geparste M3U-Liste der aktiven Playlist.
final m3uPlaylistProvider = FutureProvider<M3uPlaylist?>((ref) async {
  final playlist = ref.watch(activePlaylistProvider);
  if (playlist == null || playlist.isXtream) return null;
  return ref.watch(playlistLoaderProvider).loadM3u(playlist);
});

final catalogProvider = FutureProvider.family<Catalog, ContentType>((ref, type) async {
  final api = ref.watch(xtreamApiProvider);
  if (api != null) return api.getCatalog(type);
  final m3u = await ref.watch(m3uPlaylistProvider.future);
  return m3u?[type] ?? Catalog.empty;
});

/// Detailinfos für Filme und Serien (bei Serien inklusive Staffeln).
final mediaDetailsProvider = FutureProvider.family<MediaDetails, Channel>((ref, channel) async {
  final api = ref.watch(xtreamApiProvider);
  if (api == null || channel.xtreamStreamId == null) return MediaDetails.empty;
  return switch (channel.type) {
    ContentType.movie => api.getVodDetails(channel),
    ContentType.series => api.getSeriesDetails(channel),
    ContentType.live => MediaDetails.empty,
  };
});

/// Einträge nach Kategorie gruppiert, in Katalog-Reihenfolge (für die Reihen-Ansicht).
final channelsByCategoryProvider =
    Provider.family<AsyncValue<List<(Category, List<Channel>)>>, ContentType>((ref, type) {
  return ref.watch(catalogProvider(type)).whenData((catalog) {
    final grouped = <String, List<Channel>>{};
    for (final channel in catalog.channels) {
      if (channel.isSeparator) continue;
      grouped.putIfAbsent(channel.categoryId ?? '', () => []).add(channel);
    }
    return [
      for (final category in catalog.categories)
        if (grouped[category.id]?.isNotEmpty == true) (category, grouped[category.id]!),
    ];
  });
});

// ---------------------------------------------------------------------------
// Navigation, Filter, Suche
// ---------------------------------------------------------------------------

enum AppSection {
  live(ContentType.live),
  movies(ContentType.movie),
  series(ContentType.series),
  favorites(null);

  const AppSection(this.contentType);

  final ContentType? contentType;

  String get label => contentType?.label ?? 'Favoriten';
}

class SectionNotifier extends Notifier<AppSection> {
  @override
  AppSection build() => AppSection.live;

  void select(AppSection section) => state = section;
}

final sectionProvider = NotifierProvider<SectionNotifier, AppSection>(SectionNotifier.new);

/// Gewählte Kategorie pro Inhaltsart; `null` bedeutet „Alle“.
class SelectedCategoryNotifier extends Notifier<Category?> {
  SelectedCategoryNotifier(this.type);

  final ContentType type;

  @override
  Category? build() {
    ref.watch(activePlaylistProvider);
    return null;
  }

  void select(Category? category) => state = category;
}

final selectedCategoryProvider =
    NotifierProvider.family<SelectedCategoryNotifier, Category?, ContentType>(SelectedCategoryNotifier.new);

class SearchQueryNotifier extends Notifier<String> {
  SearchQueryNotifier(this.section);

  final AppSection section;

  @override
  String build() => '';

  void set(String query) => state = query;
}

final searchQueryProvider = NotifierProvider.family<SearchQueryNotifier, String, AppSection>(SearchQueryNotifier.new);

/// Gefilterte Einträge für eine Inhaltsart: Kategorie + Suchbegriff.
///
/// Trennzeilen („----- SPORT -----“) bleiben nur in der Live-Liste ohne
/// Suche erhalten, und nur wenn sie nicht ausgeblendet sind.
final visibleChannelsProvider = Provider.family<AsyncValue<List<Channel>>, ContentType>((ref, type) {
  final catalog = ref.watch(catalogProvider(type));
  final category = ref.watch(selectedCategoryProvider(type));
  final section = AppSection.values.firstWhere((s) => s.contentType == type);
  final query = ref.watch(searchQueryProvider(section)).trim().toLowerCase();
  final keepSeparators = type == ContentType.live && query.isEmpty && !ref.watch(hideSeparatorsProvider);

  return catalog.whenData((c) {
    Iterable<Channel> result = c.channels;
    if (!keepSeparators) result = result.where((ch) => !ch.isSeparator);
    if (category != null) result = result.where((ch) => ch.categoryId == category.id);
    if (query.isNotEmpty) result = result.where((ch) => ch.name.toLowerCase().contains(query));
    return result.toList();
  });
});

/// Anzahl echter Einträge (ohne Trennzeilen) je Kategorie-ID, Schlüssel `null` = alle.
final categoryCountsProvider = Provider.family<Map<String?, int>, ContentType>((ref, type) {
  final channels = ref.watch(catalogProvider(type)).value?.channels ?? const <Channel>[];
  final counts = <String?, int>{null: 0};
  for (final channel in channels) {
    if (channel.isSeparator) continue;
    counts[null] = counts[null]! + 1;
    counts[channel.categoryId] = (counts[channel.categoryId] ?? 0) + 1;
  }
  return counts;
});

class HideSeparatorsNotifier extends Notifier<bool> {
  static const _key = 'live.hideSeparators.v1';

  @override
  bool build() => ref.watch(sharedPreferencesProvider).getBool(_key) ?? false;

  Future<void> toggle() async {
    state = !state;
    await ref.read(sharedPreferencesProvider).setBool(_key, state);
  }
}

/// Trennzeilen in der Senderliste komplett ausblenden statt als Überschrift zeigen.
final hideSeparatorsProvider = NotifierProvider<HideSeparatorsNotifier, bool>(HideSeparatorsNotifier.new);

// ---------------------------------------------------------------------------
// Favoriten
// ---------------------------------------------------------------------------

class FavoritesNotifier extends Notifier<List<Channel>> {
  @override
  List<Channel> build() {
    final playlist = ref.watch(activePlaylistProvider);
    if (playlist == null) return const [];
    return ref.watch(localStoreProvider).loadFavorites(playlist.id);
  }

  bool contains(Channel channel) => state.contains(channel);

  Future<void> toggle(Channel channel) async {
    final playlist = ref.read(activePlaylistProvider);
    if (playlist == null || channel.isSeparator) return;
    state = state.contains(channel) ? state.where((c) => c != channel).toList() : [...state, channel];
    await ref.read(localStoreProvider).saveFavorites(playlist.id, state);
  }
}

final favoritesProvider = NotifierProvider<FavoritesNotifier, List<Channel>>(FavoritesNotifier.new);

final visibleFavoritesProvider = Provider<List<Channel>>((ref) {
  final favorites = ref.watch(favoritesProvider);
  final query = ref.watch(searchQueryProvider(AppSection.favorites)).trim().toLowerCase();
  if (query.isEmpty) return favorites;
  return favorites.where((c) => c.name.toLowerCase().contains(query)).toList();
});

// ---------------------------------------------------------------------------
// EPG
// ---------------------------------------------------------------------------

/// Kurz-EPG (aktuelle + nächste Sendungen). Nur für Xtream-Live-Sender.
final shortEpgProvider = FutureProvider.autoDispose.family<List<EpgItem>, Channel>((ref, channel) async {
  final api = ref.watch(xtreamApiProvider);
  final streamId = channel.xtreamStreamId;
  if (api == null || streamId == null || channel.type != ContentType.live) return const [];
  return api.getShortEpg(streamId);
});
