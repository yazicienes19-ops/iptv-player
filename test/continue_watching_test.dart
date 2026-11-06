import 'dart:io' hide ContentType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/models/catalog.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/models/content_type.dart';
import 'package:iptv_player/providers/app_providers.dart';
import 'package:iptv_player/services/personal_library.dart';
import 'package:iptv_player/ui/home/continue_watching.dart';
import 'package:iptv_player/ui/theme.dart';

const _movieA = Channel(
  id: '1',
  name: 'DE - Dune: Part Two (2024)',
  streamUrl: 'https://x.test/movie/u/p/1.mkv',
  type: ContentType.movie,
  xtreamStreamId: 1,
);
const _movieB = Channel(
  id: '2',
  name: 'DE - Oppenheimer (2023)',
  streamUrl: 'https://x.test/movie/u/p/2.mkv',
  type: ContentType.movie,
  xtreamStreamId: 2,
);
const _show = Channel(
  id: 'got',
  name: 'DE - Game of Thrones',
  streamUrl: '',
  type: ContentType.series,
  xtreamStreamId: 9,
);

Channel _episode(int s, int e) => Channel(
  id: 'ep-$s-$e',
  name: e == 6 ? 'Alte und neue Götter' : 'Folge $e',
  streamUrl: 'https://x.test/series/u/p/$s$e.mkv',
  type: ContentType.series,
  seriesId: 'got',
);

PersonalLibrary _library() {
  var lib = const PersonalLibrary();
  final t = DateTime(2026, 11, 6, 20);
  lib = lib.saveResume(_movieA, const Duration(minutes: 40), const Duration(minutes: 166), t);
  lib = lib.saveResume(
    _movieB,
    const Duration(minutes: 179),
    const Duration(minutes: 180),
    t.add(const Duration(minutes: 1)),
  );
  lib = lib.saveResume(
    _episode(2, 5),
    const Duration(minutes: 50),
    const Duration(minutes: 52),
    t.add(const Duration(minutes: 2)),
  );
  lib = lib.saveResume(
    _episode(2, 6),
    const Duration(minutes: 12),
    const Duration(minutes: 55),
    t.add(const Duration(minutes: 3)),
  );
  return lib;
}

class _FixedLibrary extends PersonalLibraryNotifier {
  @override
  PersonalLibrary build() => _library();
}

void main() {
  test('zuletzt geschaut zuerst, eine Karte je Serie, fertige Filme fallen raus', () {
    final items = continueWatching(_library(), [_movieA, _movieB], [_show]);
    expect(items.map((i) => i.title.id), ['got', '1']);
    expect(items.first.point.seriesId, 'got');
  });

  test('Serien-Zuordnung übersteht Speichern und Laden', () {
    final restored = PersonalLibrary.fromJson(_library().toJson());
    expect(continueWatching(restored, [_movieA], [_show]).map((i) => i.title.id), ['got', '1']);
  });

  test('alte Folgen-Punkte ohne Serie werden ignoriert statt falsch zugeordnet', () {
    final old = PersonalLibrary.fromJson({
      'resume': {
        'series:https://x.test/series/u/p/11.mkv': {'pos': 60000, 'dur': 3000000, 'at': 5},
      },
    });
    expect(continueWatching(old, [_movieA], [_show]), isEmpty);
  });

  testWidgets('Karten zeigen „S2 F6 …“ und Restzeit', (tester) async {
    if (Platform.environment['DETAIL_SHOTS'] != null) {
      final font = File('/System/Library/Fonts/Supplemental/Arial.ttf').readAsBytesSync();
      await (FontLoader('Roboto')..addFont(Future.value(ByteData.view(font.buffer)))).load();
    }
    tester.view.physicalSize = const Size(1000, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personalLibraryProvider.overrideWith(_FixedLibrary.new),
          catalogProvider(ContentType.movie)
              .overrideWith((ref) async => const Catalog(categories: [], channels: [_movieA, _movieB])),
          catalogProvider(ContentType.series)
              .overrideWith((ref) async => const Catalog(categories: [], channels: [_show])),
          tmdbApiProvider.overrideWithValue(null),
          tmdbTitleProvider(_show).overrideWith((ref) async => null),
          tmdbTitleProvider(_movieA).overrideWith((ref) async => null),
          mediaDetailsProvider(_movieA).overrideWith((ref) async => MediaDetails.empty),
          mediaDetailsProvider(_show).overrideWith(
            (ref) async => MediaDetails(
              seasons: [
                Season(
                  number: 2,
                  episodes: [
                    for (final e in [5, 6, 7]) Episode(channel: _episode(2, e), number: e),
                  ],
                ),
              ],
            ),
          ),
          networkBlockedProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          debugShowCheckedModeBanner: false,
          home: const Scaffold(body: ContinueWatchingRow(horizontalPadding: 40)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Weiterschauen'), findsOneWidget);
    expect(find.text('S2 F6 Alte und neue Götter'), findsOneWidget);
    expect(find.text('noch 2 Std. 6 Min.'), findsOneWidget);
    if (Platform.environment['DETAIL_SHOTS'] != null) {
      await expectLater(find.byType(Scaffold), matchesGoldenFile('shots/continue.png'));
    }
  });
}
