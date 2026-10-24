import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/catalog.dart';
import '../models/category.dart';
import '../models/channel.dart';
import '../models/channel_name.dart';
import '../models/content_type.dart';
import '../models/epg_item.dart';
import '../models/language.dart';
import '../models/tmdb.dart';
import '../models/playlist_credentials.dart';
import '../services/app_settings.dart';
import '../services/http_client.dart';
import '../services/imdb_catalog.dart';
import '../services/local_store.dart';
import '../services/personal_library.dart';
import '../services/recommendations.dart';
import '../services/m3u_parser.dart';
import '../services/network_security.dart';
import '../services/tmdb_api.dart';
import '../services/playlist_loader.dart';
import '../services/xtream_api.dart';
import 'imdb_providers.dart';

/// Wird in `main()` mit der geladenen Instanz überschrieben.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider muss überschrieben werden'),
);

/// `true` auf Android TV / Google TV / Fire TV; wird in `main()` überschrieben.
final isTelevisionProvider = Provider<bool>((ref) => false);

/// Wird in `main()` mit dem geöffneten Speicher (inkl. Schlüsselbund) überschrieben.
final localStoreProvider = Provider<LocalStore>(
  (ref) => throw UnimplementedError('localStoreProvider muss überschrieben werden'),
);

// ---------------------------------------------------------------------------
// Einstellungen, VPN-Wächter, HTTP
// ---------------------------------------------------------------------------

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => AppSettings.load(ref.watch(sharedPreferencesProvider));

  Future<void> update(AppSettings Function(AppSettings) change) async {
    state = change(state);
    await state.save(ref.read(sharedPreferencesProvider));
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

final userAgentProvider = Provider<String>((ref) => ref.watch(settingsProvider.select((s) => s.userAgent)));

final networkSecurityProvider = Provider((ref) => const NetworkSecurityService());

/// Aktueller VPN-Zustand, alle 3 Sekunden neu geprüft.
final vpnStatusProvider = StreamProvider<VpnStatus>((ref) => ref.watch(networkSecurityProvider).watch());

final networkGuardProvider = Provider<NetworkGuard>(
  (ref) => NetworkGuard(
    killSwitch: ref.watch(settingsProvider.select((s) => s.killSwitch)),
    service: ref.watch(networkSecurityProvider),
  ),
);

/// `true`, wenn der Kill-Switch gerade jede Verbindung sperrt.
final networkBlockedProvider = Provider<bool>((ref) {
  final killSwitch = ref.watch(settingsProvider.select((s) => s.killSwitch));
  // Im Browser lässt sich kein VPN erkennen; der Kill-Switch gilt dort nicht.
  if (!killSwitch || kIsWeb) return false;
  return !(ref.watch(vpnStatusProvider).value?.active ?? false);
});

final httpClientProvider = Provider<Dio>(
  (ref) => createHttpClient(userAgent: ref.watch(userAgentProvider), guard: ref.watch(networkGuardProvider)),
);

final playlistLoaderProvider = Provider(
  (ref) => PlaylistLoader(
    dio: createHttpClient(
      userAgent: ref.watch(userAgentProvider),
      guard: ref.watch(networkGuardProvider),
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 3),
    ),
  ),
);

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
  return playlist != null && playlist.isXtream ? XtreamApi(playlist, dio: ref.watch(httpClientProvider)) : null;
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
  final playlist = ref.watch(activePlaylistProvider);
  final store = ref.read(localStoreProvider);
  final api = ref.watch(xtreamApiProvider);
  final Catalog catalog;
  if (api != null) {
    catalog = await api.getCatalog(type);
  } else {
    final m3u = await ref.watch(m3uPlaylistProvider.future);
    catalog = m3u?[type] ?? Catalog.empty;
  }
  if (ref.mounted && type == ContentType.movie && playlist != null) {
    // Observe only a successful complete catalog, never a filtered row or a
    // failed request. Account changes dispose this load before it can commit.
    try {
      await store.updatePersonalLibrary(
        playlist.id,
        (library) => library.observeMovies(catalog.channels, DateTime.now()),
      );
    } catch (_) {
      // Optional history persistence must not block normal catalog playback.
    }
  }
  return type == ContentType.live ? borrowMissingLogos(catalog) : catalog;
});

/// Sender ohne Logo übernehmen das Logo einer anderen Fassung mit gleichem
/// Namen („TRT 1“ bekommt das Logo von „TRT 1 HD“).
Catalog borrowMissingLogos(Catalog catalog) {
  String key(Channel c) => c.display.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9äöüçğışş]+'), '');
  final logos = <String, String>{};
  for (final c in catalog.channels) {
    if (c.logo != null && !c.isSeparator) logos.putIfAbsent(key(c), () => c.logo!);
  }
  if (logos.isEmpty) return catalog;
  return Catalog(
    categories: catalog.categories,
    seriesSeasons: catalog.seriesSeasons,
    channels: [
      for (final c in catalog.channels)
        if (c.logo != null || c.isSeparator || logos[key(c)] == null)
          c
        else
          Channel(
            id: c.id,
            name: c.name,
            streamUrl: c.streamUrl,
            type: c.type,
            logo: logos[key(c)],
            categoryId: c.categoryId,
            epgChannelId: c.epgChannelId,
            xtreamStreamId: c.xtreamStreamId,
            imdbId: c.imdbId,
            year: c.year,
            genres: c.genres,
            cast: c.cast,
            director: c.director,
            addedAt: c.addedAt,
            seriesId: c.seriesId,
          ),
    ],
  );
}

/// Detailinfos für Filme und Serien (bei Serien inklusive Staffeln).
final mediaDetailsProvider = FutureProvider.family<MediaDetails, Channel>((ref, channel) async {
  final api = ref.watch(xtreamApiProvider);
  final playlistId = ref.read(activePlaylistProvider)?.id;
  if (api == null) {
    // M3U: Staffeln stammen aus der Zusammenfassung beim Einlesen.
    if (channel.type != ContentType.series) return MediaDetails.empty;
    final catalog = await ref.watch(catalogProvider(ContentType.series).future);
    return MediaDetails(seasons: catalog.seriesSeasons[channel.id] ?? const []);
  }
  if (channel.xtreamStreamId == null) return MediaDetails.empty;
  final details = switch (channel.type) {
    ContentType.movie => await api.getVodDetails(channel),
    ContentType.series => await api.getSeriesDetails(channel),
    ContentType.live => MediaDetails.empty,
  };
  await _rememberRecommendationMetadata(
    ref,
    playlistId,
    channel,
    TitleMetadata(
      genres:
          details.genre?.split(RegExp(r'[,/|]')).map((v) => v.trim()).where((v) => v.isNotEmpty).toList() ?? const [],
      cast: details.cast?.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).take(10).toList() ?? const [],
    ),
  );
  return details;
});

Future<void> _rememberRecommendationMetadata(
  Ref ref,
  String? playlistId,
  Channel channel,
  TitleMetadata metadata,
) async {
  if (!ref.mounted || playlistId == null || metadata.isEmpty) return;
  final store = ref.read(localStoreProvider);
  final before = store.loadPersonalLibrary(playlistId);
  final after = before.rememberMetadata(channel, metadata);
  if (identical(before, after)) return;
  try {
    await store.updatePersonalLibrary(playlistId, (library) => library.rememberMetadata(channel, metadata));
  } catch (_) {
    // Film information stays usable even if optional preference storage fails.
  }
  if (ref.mounted) ref.invalidate(personalLibraryProvider);
}

// ---------------------------------------------------------------------------
// Länder-/Sprachfilter
// ---------------------------------------------------------------------------

/// Gewählte Sprache (Code aus [Language]) oder `null` für „Alle“.
class LanguageFilterNotifier extends Notifier<String?> {
  static const _key = 'filter.language.v1';
  static const _all = 'all';

  @override
  String? build() {
    final stored = ref.watch(sharedPreferencesProvider).getString(_key);
    if (stored == null) return 'de';
    return stored == _all ? null : stored;
  }

  Future<void> select(String? code) async {
    state = code;
    await ref.read(sharedPreferencesProvider).setString(_key, code ?? _all);
  }
}

final languageFilterProvider = NotifierProvider<LanguageFilterNotifier, String?>(LanguageFilterNotifier.new);

/// Ordnet jedem Eintrag eine Sprache zu, damit der Länderfilter streng greift.
///
/// Reihenfolge: eigenes Kürzel des Senders („DE: ZDF“) → Sprache der Kategorie →
/// aus den Sendern der Kategorie geschlossen (mind. 60 % einer Sprache).
class LanguageIndex {
  const LanguageIndex(this.categoryLanguage, {required this.hasInfo});

  static const minShare = 0.6;

  /// Kategorie-ID → Sprachcode (ausdrücklich oder erschlossen).
  final Map<String, String> categoryLanguage;

  /// `false`, wenn die Playlist gar keine Länderangaben enthält.
  final bool hasInfo;

  String? of(Channel channel) =>
      Language.fromCode(channel.display.country)?.code ?? categoryLanguage[channel.categoryId];

  bool matches(Channel channel, String? filter) {
    if (filter == null) return true;
    final language = of(channel);
    if (language != null) return language == filter;
    // Trennzeilen ohne Kürzel bleiben; leere Abschnitte fallen beim Anzeigen ohnehin weg.
    if (channel.isSeparator) return true;
    // Ohne jede Länderangabe in der Playlist würde ein strenger Filter alles ausblenden.
    return !hasInfo;
  }

  factory LanguageIndex.build(Catalog catalog) {
    final languages = <String, String>{
      for (final c in catalog.categories)
        if (c.language != null) c.id: c.language!,
    };
    final tally = <String, Map<String, int>>{};
    final totals = <String, int>{};
    var channelInfo = false;
    for (final channel in catalog.channels) {
      if (channel.isSeparator) continue;
      final id = channel.categoryId ?? '';
      totals[id] = (totals[id] ?? 0) + 1;
      final code = Language.fromCode(channel.display.country)?.code;
      if (code == null) continue;
      channelInfo = true;
      final counts = tally.putIfAbsent(id, () => {});
      counts[code] = (counts[code] ?? 0) + 1;
    }
    for (final MapEntry(key: id, value: counts) in tally.entries) {
      if (languages.containsKey(id)) continue;
      final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
      if (top.value >= minShare * totals[id]!) languages[id] = top.key;
    }
    return LanguageIndex(languages, hasInfo: languages.isNotEmpty || channelInfo);
  }
}

final languageIndexProvider = Provider.family<LanguageIndex, ContentType>((ref, type) {
  final catalog = ref.watch(catalogProvider(type)).value;
  return catalog == null ? const LanguageIndex({}, hasInfo: false) : LanguageIndex.build(catalog);
});

/// Sprachen, die in der Playlist tatsächlich vorkommen (nach Häufigkeit).
final availableLanguagesProvider = Provider<List<Language>>((ref) {
  final counts = <String, int>{};
  for (final type in ContentType.values) {
    for (final code in ref.watch(languageIndexProvider(type)).categoryLanguage.values) {
      counts[code] = (counts[code] ?? 0) + 1;
    }
  }
  final codes = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  return [for (final code in codes) ?Language.byCode(code)];
});

/// Kategorien einer Inhaltsart, die nach dem Länderfilter noch Einträge haben.
final filteredCategoriesProvider = Provider.family<List<Category>, ContentType>((ref, type) {
  final categories = ref.watch(catalogProvider(type)).value?.categories ?? const <Category>[];
  final counts = ref.watch(categoryCountsProvider(type));
  return [
    for (final c in categories)
      if ((counts[c.id] ?? 0) > 0) c,
  ];
});

/// Einträge nach Kategorie gruppiert, in Katalog-Reihenfolge (für die Reihen-Ansicht).
final channelsByCategoryProvider = Provider.family<AsyncValue<List<(Category, List<Channel>)>>, ContentType>((
  ref,
  type,
) {
  final filter = ref.watch(languageFilterProvider);
  final index = ref.watch(languageIndexProvider(type));

  return ref.watch(catalogProvider(type)).whenData((catalog) {
    final grouped = <String, List<Channel>>{};
    for (final channel in catalog.channels) {
      if (channel.isSeparator || !index.matches(channel, filter)) continue;
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
  home(null),
  live(ContentType.live),
  movies(ContentType.movie),
  series(ContentType.series),
  favorites(null);

  const AppSection(this.contentType);

  final ContentType? contentType;

  String get label => switch (this) {
    AppSection.home => 'Startseite',
    AppSection.favorites => 'Favoriten',
    _ => contentType!.label,
  };
}

class SectionNotifier extends Notifier<AppSection> {
  @override
  AppSection build() => AppSection.home;

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

final selectedCategoryProvider = NotifierProvider.family<SelectedCategoryNotifier, Category?, ContentType>(
  SelectedCategoryNotifier.new,
);

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
  final filter = ref.watch(languageFilterProvider);
  final index = ref.watch(languageIndexProvider(type));
  final imdb = type == ContentType.live ? null : ref.watch(imdbCatalogProvider).value;
  final imdbGenre = type == ContentType.movie ? ref.watch(imdbFilterProvider) : null;

  return catalog.whenData((c) {
    Iterable<Channel> result = c.channels;
    if (!keepSeparators) result = result.where((ch) => !ch.isSeparator);
    // Pro Sender prüfen: auch gemischte Kategorien zeigen nur das gewählte Land.
    if (filter != null) result = result.where((ch) => index.matches(ch, filter));
    if (category != null) result = result.where((ch) => ch.categoryId == category.id);
    if (query.isNotEmpty) {
      result = type == ContentType.live
          ? result.where((ch) => ch.name.toLowerCase().contains(query))
          : searchCatalog(result, query, imdb: imdb);
    }
    if (imdbGenre != null && imdb != null) result = imdb.ranked(result, genre: imdbGenre).map((row) => row.$1);
    return result.toList();
  });
});

/// Bewertete Filme der aktiven Playlist und Sprache, unabhängig vom Suchfilter.
final imdbRowsProvider = Provider<List<(Channel, ImdbMovie)>>((ref) {
  final imdb = ref.watch(imdbCatalogProvider).value;
  if (imdb == null) return const [];
  final channels = ref.watch(catalogProvider(ContentType.movie)).value?.channels ?? const <Channel>[];
  final language = ref.watch(languageFilterProvider);
  final index = ref.watch(languageIndexProvider(ContentType.movie));
  return imdb.ranked(channels.where((channel) => !channel.isSeparator && index.matches(channel, language)));
});

/// Anzahl echter Einträge (ohne Trennzeilen) je Kategorie-ID, Schlüssel `null` = alle.
final categoryCountsProvider = Provider.family<Map<String?, int>, ContentType>((ref, type) {
  final channels = ref.watch(catalogProvider(type)).value?.channels ?? const <Channel>[];
  final filter = ref.watch(languageFilterProvider);
  final index = ref.watch(languageIndexProvider(type));
  final counts = <String?, int>{null: 0};
  for (final channel in channels) {
    // Gezählt wird nur, was der Länderfilter zeigt.
    if (channel.isSeparator || !index.matches(channel, filter)) continue;
    counts[channel.categoryId] = (counts[channel.categoryId] ?? 0) + 1;
    counts[null] = counts[null]! + 1;
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
    return ref.watch(localStoreProvider).loadFavorites(playlist);
  }

  bool contains(Channel channel) => state.contains(channel);

  Future<void> toggle(Channel channel) async {
    final playlist = ref.read(activePlaylistProvider);
    if (playlist == null || channel.isSeparator) return;
    state = state.contains(channel) ? state.where((c) => c != channel).toList() : [...state, channel];
    await ref.read(localStoreProvider).saveFavorites(playlist, state);
  }
}

final favoritesProvider = NotifierProvider<FavoritesNotifier, List<Channel>>(FavoritesNotifier.new);

// ---------------------------------------------------------------------------
// Live-TV-Dashboard
// ---------------------------------------------------------------------------

/// Zuletzt gesehene Live-Sender, neueste zuerst, höchstens [max].
class RecentChannelsNotifier extends Notifier<List<Channel>> {
  static const max = 12;

  @override
  List<Channel> build() {
    final playlist = ref.watch(activePlaylistProvider);
    if (playlist == null) return const [];
    return ref.watch(localStoreProvider).loadRecents(playlist);
  }

  Future<void> add(Channel channel) async {
    final playlist = ref.read(activePlaylistProvider);
    if (playlist == null || channel.type != ContentType.live || channel.isSeparator) return;
    state = [channel, ...state.where((c) => c != channel)].take(max).toList();
    await ref.read(localStoreProvider).saveRecents(playlist, state);
  }
}

final recentChannelsProvider = NotifierProvider<RecentChannelsNotifier, List<Channel>>(RecentChannelsNotifier.new);

/// Personal rows are isolated per playlist and contain no stale stream URLs.
class PersonalLibraryNotifier extends Notifier<PersonalLibrary> {
  late LocalStore _store;
  String? _playlistId;

  @override
  PersonalLibrary build() {
    _store = ref.watch(localStoreProvider);
    _playlistId = ref.watch(activePlaylistProvider)?.id;
    // A successful catalog load may have established/updated the movie baseline.
    ref.watch(catalogProvider(ContentType.movie));
    return _playlistId == null ? const PersonalLibrary() : _store.loadPersonalLibrary(_playlistId!);
  }

  Future<void> addWatch(String playlistId, Channel channel, Duration watched) async {
    final write = _store.updatePersonalLibrary(
      playlistId,
      (library) => library.addWatch(channel, watched, DateTime.now()),
    );
    if (ref.mounted && _playlistId == playlistId) state = _store.loadPersonalLibrary(playlistId);
    await write;
  }

  Future<void> addVodWatch(
    String playlistId,
    Channel channel,
    Duration watched, {
    Duration duration = Duration.zero,
    bool reachedEnd = false,
    List<String>? capturedKeys,
  }) async {
    final keys = capturedKeys ?? recommendationKeys(channel, ref.read(imdbCatalogProvider).value);
    final write = _store.updatePersonalLibrary(
      playlistId,
      (library) => library.addVodWatch(
        keys,
        watched,
        DateTime.now(),
        duration: duration,
        reachedEnd: reachedEnd,
        isMovie: channel.type == ContentType.movie,
      ),
    );
    if (ref.mounted && _playlistId == playlistId) state = _store.loadPersonalLibrary(playlistId);
    await write;
  }

  Future<void> toggleFeedback(Channel channel, FeedbackChoice choice) async {
    final playlistId = _playlistId;
    if (playlistId == null || channel.type == ContentType.live) return;
    final keys = recommendationKeys(channel, ref.read(imdbCatalogProvider).value);
    final sources = [
      ...?ref.read(catalogProvider(ContentType.movie)).value?.channels,
      ...?ref.read(catalogProvider(ContentType.series)).value?.channels,
    ];
    final selected = reconcileRecommendationHistory(
      state,
      sources,
      ref.read(imdbCatalogProvider).value,
    ).feedbackFor(keys)?.choice;
    final write = _store.updatePersonalLibrary(
      playlistId,
      (library) => library.setFeedback(keys, selected == choice ? null : choice, DateTime.now()),
    );
    state = _store.loadPersonalLibrary(playlistId);
    await write;
  }
}

final personalLibraryProvider = NotifierProvider<PersonalLibraryNotifier, PersonalLibrary>(PersonalLibraryNotifier.new);

final mostWatchedChannelsProvider = Provider<List<Channel>>((ref) {
  final library = ref.watch(personalLibraryProvider);
  final catalog = ref.watch(catalogProvider(ContentType.live)).value;
  final language = ref.watch(languageFilterProvider);
  final index = ref.watch(languageIndexProvider(ContentType.live));
  return library.mostWatched(
    (catalog?.channels ?? const <Channel>[]).where(
      (channel) => !channel.isSeparator && index.matches(channel, language),
    ),
  );
});

final newMoviesProvider = Provider<List<Channel>>((ref) {
  final library = ref.watch(personalLibraryProvider);
  final catalog = ref.watch(catalogProvider(ContentType.movie)).value;
  final language = ref.watch(languageFilterProvider);
  final index = ref.watch(languageIndexProvider(ContentType.movie));
  return library.newMovies(
    (catalog?.channels ?? const <Channel>[]).where(
      (channel) => !channel.isSeparator && index.matches(channel, language),
    ),
    DateTime.now(),
  );
});

final recommendationHistoryProvider = Provider<PersonalLibrary>((ref) {
  final library = ref.watch(personalLibraryProvider);
  final imdb = ref.watch(imdbCatalogProvider).value;
  final sources = [
    ...?ref.watch(catalogProvider(ContentType.movie)).value?.channels,
    ...?ref.watch(catalogProvider(ContentType.series)).value?.channels,
  ];
  return reconcileRecommendationHistory(library, sources, imdb);
});

final recommendationFeedbackProvider = Provider.family<FeedbackChoice?, Channel>((ref, channel) {
  final library = ref.watch(recommendationHistoryProvider);
  final imdb = ref.watch(imdbCatalogProvider).value;
  final choice = library.feedbackFor(recommendationKeys(channel, imdb))?.choice;
  return choice == FeedbackChoice.none ? null : choice;
});

final recommendationsProvider = Provider<Recommendations>((ref) {
  final library = ref.watch(personalLibraryProvider);
  final imdb = ref.watch(imdbCatalogProvider).value;
  final language = ref.watch(languageFilterProvider);
  final sources = <Channel>[];
  final available = <Channel>[];
  for (final type in [ContentType.movie, ContentType.series]) {
    final channels = ref.watch(catalogProvider(type)).value?.channels ?? const <Channel>[];
    final index = ref.watch(languageIndexProvider(type));
    sources.addAll(channels);
    available.addAll(channels.where((channel) => index.matches(channel, language)));
  }
  return recommendTitles(
    available: available,
    sources: sources,
    library: library,
    imdb: imdb,
    favorites: ref.watch(favoritesProvider),
  );
});

/// Bekannte große Sender je Sprache, in der Reihenfolge der Senderplätze.
const _popularByLanguage = <String, List<String>>{
  'de': [
    'das erste',
    'zdf',
    'rtl',
    'sat.1',
    'sat 1',
    'prosieben',
    'pro7',
    'vox',
    'kabel eins',
    'kabel 1',
    'rtl zwei',
    'rtl2',
    'super rtl',
    'nitro',
    'n-tv',
    'ntv',
    'welt',
    'tagesschau24',
    'phoenix',
    '3sat',
    'arte',
    'zdfneo',
    'zdfinfo',
    'one',
    'kika',
    'sport1',
    'dmax',
    'tele 5',
    'sixx',
    'prosieben maxx',
    'eurosport',
    'comedy central',
    'nickelodeon',
    'br',
    'wdr',
    'ndr',
    'mdr',
    'swr',
    'hr',
    'rbb',
  ],
  'tr': [
    'trt 1',
    'show tv',
    'star tv',
    'atv',
    'kanal d',
    'now',
    'fox',
    'tv8',
    'kanal 7',
    'tv 100',
    'halk tv',
    'trt haber',
    'cnn türk',
    'cnn turk',
    'ntv',
    'haberturk',
    'habertürk',
    'a haber',
    'trt spor',
    'beyaz tv',
    'teve2',
  ],
  'sq': ['top channel', 'klan', 'vizion plus', 'rtsh', 'tv klan', 'news 24', 'abc news', 'top news', 'rtk', 'kanal 10'],
  'en': ['bbc one', 'bbc two', 'itv', 'channel 4', 'channel 5', 'sky news', 'bbc news', 'cnn', 'sky one', 'e4'],
};

/// Schnellwahl fürs Dashboard: bekannte Sender der gewählten Sprache, je Name
/// nur einmal (bevorzugt mit Logo und höherer Qualität); sonst die ersten Sender.
final popularLiveChannelsProvider = Provider<List<Channel>>((ref) {
  final channels = ref.watch(visibleChannelsProvider(ContentType.live)).value ?? const <Channel>[];
  final names = _popularByLanguage[ref.watch(languageFilterProvider) ?? 'de'] ?? _popularByLanguage['de']!;
  final best = <String, Channel>{};
  for (final channel in channels) {
    if (channel.isSeparator) continue;
    final title = channel.display.title.toLowerCase();
    // Längster Treffer gewinnt: „RTL ZWEI“ ist nicht „RTL“.
    final match = names
        .where((n) => title == n || title.startsWith('$n '))
        .fold<String?>(null, (best, n) => best == null || n.length > best.length ? n : best);
    if (match == null) continue;
    final current = best[match];
    int rank(Channel c) =>
        (c.logo != null ? 10 : 0) + (c.display.qualities.isEmpty ? 0 : 5 - c.display.qualities.first.index);
    if (current == null || rank(channel) > rank(current)) best[match] = channel;
  }
  final popular = [for (final n in names) ?best[n]];
  if (popular.length >= 6) return popular.take(24).toList();
  // Unbekannte Sprache oder kleine Liste: einfach die ersten Sender mit Logo.
  return [
    ...popular,
    ...channels.where((c) => !c.isSeparator && c.logo != null && !popular.contains(c)),
  ].take(24).toList();
});

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

// ---------------------------------------------------------------------------
// TMDB (Film-, Serien- und Darstellerinfos)
// ---------------------------------------------------------------------------

class TmdbKeyNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() => ref.watch(localStoreProvider).readTmdbKey();

  /// Prüft den Schlüssel bei TMDB und speichert ihn erst dann. Wirft bei Fehler.
  Future<void> save(String key) async {
    final trimmed = key.trim();
    await TmdbApi(trimmed, dio: ref.read(httpClientProvider)).verify();
    await ref.read(localStoreProvider).writeTmdbKey(trimmed);
    state = AsyncData(trimmed);
  }

  Future<void> remove() async {
    await ref.read(localStoreProvider).writeTmdbKey(null);
    state = const AsyncData(null);
  }
}

final tmdbKeyProvider = AsyncNotifierProvider<TmdbKeyNotifier, String?>(TmdbKeyNotifier.new);

final tmdbApiProvider = Provider<TmdbApi?>((ref) {
  final key = ref.watch(tmdbKeyProvider).value;
  return key == null || key.isEmpty ? null : TmdbApi(key, dio: ref.watch(httpClientProvider));
});

/// Ordnet einen Playlist-Eintrag TMDB zu: zuerst über die vom Anbieter
/// gelieferte TMDB-Nummer, sonst per Suche nach bereinigtem Titel und Jahr.
final tmdbMatchProvider = FutureProvider.family<TmdbRef?, Channel>((ref, channel) async {
  final api = ref.watch(tmdbApiProvider);
  if (api == null || channel.type == ContentType.live) return null;
  final type = channel.type == ContentType.series ? TmdbMediaType.tv : TmdbMediaType.movie;
  final known = (await ref.watch(mediaDetailsProvider(channel).future)).tmdbId;
  if (known != null && known > 0) return TmdbRef(id: known, type: type, title: channel.display.title);
  return api.search(channel.display.title, type, year: channel.releaseYear);
});

final tmdbTitleProvider = FutureProvider.family<TmdbTitle?, Channel>((ref, channel) async {
  final playlistId = ref.read(activePlaylistProvider)?.id;
  final match = await ref.watch(tmdbMatchProvider(channel).future);
  final api = ref.watch(tmdbApiProvider);
  if (match == null || api == null) return null;
  final title = await api.title(match.id, match.type);
  await _rememberRecommendationMetadata(
    ref,
    playlistId,
    channel,
    TitleMetadata(
      genres: title.genres,
      cast: title.cast.take(10).map((person) => person.name).toList(),
      director: title.directors.firstOrNull,
    ),
  );
  return title;
});

final tmdbCollectionProvider = FutureProvider.family<TmdbCollection, int>((ref, id) async {
  final api = ref.watch(tmdbApiProvider);
  if (api == null) throw const TmdbException('Kein TMDB-Schlüssel hinterlegt.');
  return api.collection(id);
});

final tmdbPersonProvider = FutureProvider.family<TmdbPerson, int>((ref, id) async {
  final api = ref.watch(tmdbApiProvider);
  if (api == null) throw const TmdbException('Kein TMDB-Schlüssel hinterlegt.');
  return api.person(id);
});

/// Sucht zu einem TMDB-Titel den passenden Eintrag in der Playlist.
class PlaylistTitleIndex {
  PlaylistTitleIndex(Iterable<Channel> channels) {
    for (final channel in channels) {
      if (channel.isSeparator) continue;
      _byTitle.putIfAbsent(catalogTitleKey(cleanCatalogTitle(channel.name).title), () => []).add(channel);
    }
  }

  final _byTitle = <String, List<Channel>>{};

  /// Match unique compatible titles; never pick an arbitrary remake when the
  /// playlist omits the year. Exact known years take precedence over ±1 years.
  Channel? find(TmdbRef ref) {
    int? yearOf(Channel channel) => channel.year ?? cleanCatalogTitle(channel.name).year;
    final wantedType = ref.type == TmdbMediaType.tv ? ContentType.series : ContentType.movie;
    final candidates = <String, Channel>{};
    for (final title in {ref.title, ?ref.originalTitle}) {
      for (final channel in _byTitle[catalogTitleKey(title)] ?? const <Channel>[]) {
        if (channel.type == wantedType) candidates.putIfAbsent(personalItemKey(channel), () => channel);
      }
    }
    final all = candidates.values.toList();
    if (ref.year == null) return all.length == 1 ? all.single : null;
    final exact = all.where((channel) => yearOf(channel) == ref.year).toList();
    if (exact.isNotEmpty) return exact.length == 1 ? exact.single : null;
    final compatible = all
        .where((channel) => yearOf(channel) == null || (yearOf(channel)! - ref.year!).abs() <= 1)
        .toList();
    return compatible.length == 1 ? compatible.single : null;
  }
}

final playlistTitleIndexProvider = Provider<PlaylistTitleIndex>((ref) {
  final movies = ref.watch(catalogProvider(ContentType.movie)).value?.channels ?? const <Channel>[];
  final series = ref.watch(catalogProvider(ContentType.series)).value?.channels ?? const <Channel>[];
  return PlaylistTitleIndex([...movies, ...series]);
});
