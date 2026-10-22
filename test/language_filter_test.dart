import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/models/catalog.dart';
import 'package:iptv_player/models/category.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/models/content_type.dart';
import 'package:iptv_player/providers/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Channel live(String name, String category) => Channel(
  id: '$category/$name',
  name: name,
  streamUrl: 'http://x/$name',
  type: ContentType.live,
  categoryId: category,
);

Category cat(String raw) => Category.cleaned(id: raw, rawName: raw, type: ContentType.live);

Future<ProviderContainer> containerWith(Catalog catalog, {String? filter = 'de'}) async {
  SharedPreferences.setMockInitialValues({'filter.language.v1': filter ?? 'all'});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      activePlaylistProvider.overrideWithValue(null),
      catalogProvider(ContentType.live).overrideWith((ref) async => catalog),
    ],
  );
  addTearDown(container.dispose);
  await container.read(catalogProvider(ContentType.live).future);
  return container;
}

List<String> visibleNames(ProviderContainer c) =>
    c.read(visibleChannelsProvider(ContentType.live)).value!.map((ch) => ch.name).toList();

void main() {
  final mixedPlaylist = Catalog(
    categories: [cat('DE | Vollprogramm'), cat('SPORTS'), cat('INTERNATIONAL'), cat('AL SPORTS'), cat('VIP')],
    channels: [
      live('ZDF', 'DE | Vollprogramm'),
      live('DE: Sky Sport 1', 'SPORTS'),
      live('DE: DAZN 1', 'SPORTS'),
      live('Sport Extra', 'SPORTS'),
      live('DE: Welt', 'INTERNATIONAL'),
      live('TR: TRT 1', 'INTERNATIONAL'),
      live('AL: Top Channel', 'INTERNATIONAL'),
      live('SuperSport 1', 'AL SPORTS'),
      live('Rätselkanal', 'VIP'),
    ],
  );

  test('Deutsch: nur deutsche Sender, auch aus gemischten und unbeschrifteten Kategorien', () async {
    final c = await containerWith(mixedPlaylist);

    // „SPORTS“ hat kein Kürzel, ist aber zu 2/3 deutsch → gilt als deutsch, auch „Sport Extra“.
    // „INTERNATIONAL“ ist gemischt → nur der deutsche Sender bleibt.
    // „AL SPORTS“ ist albanisch, „VIP“ unbekannt → ausgeblendet.
    expect(visibleNames(c), ['ZDF', 'DE: Sky Sport 1', 'DE: DAZN 1', 'Sport Extra', 'DE: Welt']);
    expect(c.read(categoryCountsProvider(ContentType.live))[null], 5);
    expect(c.read(filteredCategoriesProvider(ContentType.live)).map((x) => x.name), [
      'Vollprogramm',
      'SPORTS',
      'INTERNATIONAL',
    ]);
  });

  test('Shqip zeigt die albanischen Sender, „Alle“ zeigt alles', () async {
    final albanian = await containerWith(mixedPlaylist, filter: 'sq');
    expect(visibleNames(albanian), ['AL: Top Channel', 'SuperSport 1']);

    final all = await containerWith(mixedPlaylist, filter: null);
    expect(visibleNames(all).length, 9);
  });

  test('Playlist ganz ohne Länderangaben bleibt mit Filter vollständig sichtbar', () async {
    final c = await containerWith(
      Catalog(
        categories: [cat('General'), cat('News')],
        channels: [live('Das Erste', 'General'), live('tagesschau24', 'News')],
      ),
    );
    expect(visibleNames(c), ['Das Erste', 'tagesschau24']);
  });
}
