import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/models/catalog.dart';
import 'package:iptv_player/models/category.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/models/content_type.dart';
import 'package:iptv_player/providers/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Channel live(String name, {String? logo}) =>
    Channel(id: name, name: name, streamUrl: 'http://x/$name', type: ContentType.live, logo: logo, categoryId: 'de');

void main() {
  test('Beliebte Sender: richtige Reihenfolge, RTL ZWEI ist nicht RTL, beste Variante gewinnt', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        activePlaylistProvider.overrideWithValue(null),
        catalogProvider(ContentType.live).overrideWith(
          (ref) async => Catalog(
            categories: const [Category(id: 'de', name: 'Deutschland', type: ContentType.live, language: 'de')],
            channels: [
              live('DE | RTL ZWEI HD', logo: 'l'),
              live('DE | ZDF SD'),
              live('DE | ZDF FHD', logo: 'l'),
              live('DE | RTL HD', logo: 'l'),
              live('DE | DAS ERSTE HD', logo: 'l'),
              live('DE | Regional Lokal'),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(catalogProvider(ContentType.live).future);

    final popular = container.read(popularLiveChannelsProvider);
    expect(popular.map((c) => c.name), ['DE | DAS ERSTE HD', 'DE | ZDF FHD', 'DE | RTL HD', 'DE | RTL ZWEI HD']);
  });
}
