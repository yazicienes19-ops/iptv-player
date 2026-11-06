import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iptv_player/models/catalog.dart';
import 'package:iptv_player/models/category.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/models/content_type.dart';
import 'package:iptv_player/models/tmdb.dart';
import 'package:iptv_player/providers/app_providers.dart';
import 'package:iptv_player/providers/imdb_providers.dart';
import 'package:iptv_player/services/local_store.dart';
import 'package:iptv_player/ui/detail/detail_page.dart';
import 'package:iptv_player/ui/theme.dart';

import 'personal_library_test.dart' show PersonalSecureStore, playlistA;
import 'recommendations_test.dart' show NoImdb;

final _series = Channel(
  id: 'got',
  name: 'DE - Game of Thrones (2011)',
  streamUrl: '',
  type: ContentType.series,
  categoryId: 'de',
);

const _plot =
    'Die Handlung ist in einer fiktiven Welt angesiedelt und spielt auf den Kontinenten Westeros und Essos. '
    'In dieser Welt ist die Länge der Sommer und Winter unvorhersehbar und variabel; eine Jahreszeit kann Jahre '
    'oder sogar Jahrzehnte dauern. Der Handlungsort auf dem Kontinent Westeros ähnelt dabei stark dem '
    'mittelalterlichen Europa. Die Geschichte spielt am Ende eines langen Sommers und wird in drei '
    'Handlungssträngen weitgehend parallel erzählt.';

MediaDetails _seriesDetails() => MediaDetails(
  plot: _plot,
  genre: 'Sci-Fi & Fantasy, Drama, Action & Adventure',
  year: '2011',
  seasons: [
    for (final s in [1, 2])
      Season(
        number: s,
        episodes: [
          for (final e in [1, 2, 3])
            Episode(
              number: e,
              plot:
                  'Jon Arryn, die Hand des Königs, ist tot. König Robert Baratheon plant, seinen ältesten Freund '
                  'zu bitten, sein Nachfolger zu werden.',
              duration: '62 Min.',
              airDate: DateTime(2011, 4, 10 + e * 7),
              channel: Channel(
                id: 'ep-$s-$e',
                name: e == 1 ? 'Der Winter naht' : 'Folge $e',
                streamUrl: 'https://example.test/ep-$s-$e.mkv',
                type: ContentType.series,
                seriesId: 'got',
              ),
            ),
        ],
      ),
  ],
);

TmdbTitle _tmdb() => TmdbTitle.fromJson({
  'id': 1399,
  'name': 'Game of Thrones',
  'first_air_date': '2011-04-17',
  'last_air_date': '2019-05-19',
  'vote_average': 8.46,
  'vote_count': 24500,
  'genres': [
    {'name': 'Drama'},
  ],
  'aggregate_credits': {
    'cast': [
      for (final (n, r) in [
        ('Peter Dinklage', 'Tyrion Lannister'),
        ('Kit Harington', 'Jon Snow'),
        ('Lena Headey', 'Cersei Lannister'),
        ('Emilia Clarke', 'Daenerys Targaryen'),
      ])
        {
          'id': n.length,
          'name': n,
          'roles': [
            {'character': r},
          ],
        },
    ],
  },
  'videos': {
    'results': [
      {'site': 'YouTube', 'type': 'Featurette', 'key': 'f1', 'name': 'Inside Game of Thrones'},
      {'site': 'YouTube', 'type': 'Trailer', 'key': 't1', 'name': 'Official Series Trailer'},
      {'site': 'Vimeo', 'type': 'Trailer', 'key': 'v1', 'name': 'Nicht YouTube'},
      {'site': 'YouTube', 'type': 'Opening Credits', 'key': 'o1', 'name': 'Opening Credits'},
    ],
  },
  'images': {
    'logos': [
      {'iso_639_1': 'en', 'file_path': '/en.png'},
      {'iso_639_1': 'de', 'file_path': '/de.png'},
    ],
  },
}, TmdbMediaType.tv);

Future<void> _loadRealFont() async {
  // Für lesbare Prüfbilder echte Schrift statt Test-Kästchen laden (nur, wenn vorhanden).
  final file = File('/System/Library/Fonts/Supplemental/Arial.ttf');
  if (!file.existsSync()) return;
  final bytes = file.readAsBytesSync();
  final loader = FontLoader('Roboto')..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

void main() {
  test('TMDB: deutsches Logo bevorzugt, nur YouTube-Videos, Trailer zuerst', () {
    final tmdb = _tmdb();
    expect(tmdb.logo, 'https://image.tmdb.org/t/p/w500/de.png');
    expect(tmdb.videos.map((v) => v.key), ['t1', 'f1', 'o1']);
    expect(tmdb.videos.last.typeLabel, 'Vorspann');
    expect(tmdb.videos.first.thumbnail, 'https://img.youtube.com/vi/t1/hqdefault.jpg');
  });

  for (final size in [const Size(1280, 800), const Size(390, 844)]) {
    testWidgets('Serien-Detailseite ohne Fehler bei ${size.width.toInt()} px', (tester) async {
      await _loadRealFont();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = await LocalStore.open(prefs, PersonalSecureStore());
      await store.savePlaylists([playlistA]);
      await store.saveActivePlaylistId('a');
      final alt = Channel(
        id: 'got-en',
        name: 'EN - Game of Thrones (2011)',
        streamUrl: '',
        type: ContentType.series,
        categoryId: 'en',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            localStoreProvider.overrideWithValue(store),
            imdbCatalogProvider.overrideWith(NoImdb.new),
            tmdbApiProvider.overrideWithValue(null),
            tmdbTitleProvider(_series).overrideWith((ref) async => _tmdb()),
            mediaDetailsProvider(_series).overrideWith((ref) async => _seriesDetails()),
            catalogProvider(ContentType.series).overrideWith(
              (ref) async => Catalog(
                categories: const [
                  Category(id: 'de', name: 'Deutsche Serien', type: ContentType.series),
                  Category(id: 'en', name: 'Englische Serien', type: ContentType.series),
                ],
                channels: [_series, alt],
              ),
            ),
            catalogProvider(ContentType.movie).overrideWith((ref) async => Catalog.empty),
            // In der App im Hintergrund-Isolate berechnet; im Test direkt.
            catalogTitleKeysProvider(ContentType.series)
                .overrideWith((ref) async => CatalogTitleKeys.of([_series, alt])),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            home: DetailPage(channel: _series, queue: [_series]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Startet immer ganz oben mit dem großen Titelbild.
      final scroll = tester.widget<CustomScrollView>(find.byType(CustomScrollView)).controller!;
      expect(scroll.offset, 0);
      // Abschnitte entstehen erst beim Hinscrollen.
      for (final label in ['BEWERTUNGEN', 'BESETZUNG', 'FOLGEN', 'S01E01', 'VIDEOS']) {
        await tester.scrollUntilVisible(find.text(label), 200, scrollable: find.byType(Scrollable).first);
      }
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 4000));
      await tester.pumpAndSettle();

      if (Platform.environment['DETAIL_SHOTS'] != null) {
        await expectLater(find.byType(DetailPage), matchesGoldenFile('shots/detail_${size.width.toInt()}_top.png'));
        await tester.drag(find.byType(CustomScrollView), Offset(0, -size.height * 0.85));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(DetailPage),
          matchesGoldenFile('shots/detail_${size.width.toInt()}_scrolled.png'),
        );
      }

      // Staffel komplett herunterladen lässt sich anbieten.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('season-download')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Staffel 1 herunterladen (3 Folgen)'), findsOneWidget);
      // Staffel wechseln.
      await tester.scrollUntilVisible(find.text('Staffel 2'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Staffel 2'));
      await tester.pumpAndSettle();
      expect(find.text('S02E01'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
