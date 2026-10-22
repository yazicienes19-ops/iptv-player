import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/catalog.dart';
import '../models/category.dart';
import '../models/channel.dart';
import '../models/channel_name.dart';
import '../models/content_type.dart';
import '../models/epg_item.dart';
import '../models/language.dart';
import '../models/playlist_credentials.dart';
import '../services/app_settings.dart';
import '../services/http_client.dart';
import '../services/local_store.dart';
import '../services/m3u_parser.dart';
import '../services/network_security.dart';
import '../services/playlist_loader.dart';
import '../services/xtream_api.dart';

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
  if (!killSwitch) return false;
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
  final api = ref.watch(xtreamApiProvider);
  if (api != null) return api.getCatalog(type);
  final m3u = await ref.watch(m3uPlaylistProvider.future);
  return m3u?[type] ?? Catalog.empty;
});

/// Detailinfos für Filme und Serien (bei Serien inklusive Staffeln).
final mediaDetailsProvider = FutureProvider.family<MediaDetails, Channel>((ref, channel) async {
  final api = ref.watch(xtreamApiProvider);
  if (api == null) {
    // M3U: Staffeln stammen aus der Zusammenfassung beim Einlesen.
    if (channel.type != ContentType.series) return MediaDetails.empty;
    final catalog = await ref.watch(catalogProvider(ContentType.series).future);
    return MediaDetails(seasons: catalog.seriesSeasons[channel.id] ?? const []);
  }
  if (channel.xtreamStreamId == null) return MediaDetails.empty;
  return switch (channel.type) {
    ContentType.movie => api.getVodDetails(channel),
    ContentType.series => api.getSeriesDetails(channel),
    ContentType.live => MediaDetails.empty,
  };
});

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

  return catalog.whenData((c) {
    Iterable<Channel> result = c.channels;
    if (!keepSeparators) result = result.where((ch) => !ch.isSeparator);
    // Pro Sender prüfen: auch gemischte Kategorien zeigen nur das gewählte Land.
    if (filter != null) result = result.where((ch) => index.matches(ch, filter));
    if (category != null) result = result.where((ch) => ch.categoryId == category.id);
    if (query.isNotEmpty) result = result.where((ch) => ch.name.toLowerCase().contains(query));
    return result.toList();
  });
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
