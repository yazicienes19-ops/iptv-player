import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/providers/app_providers.dart';
import 'package:iptv_player/ui/home/sidebar.dart';
import 'package:iptv_player/ui/theme.dart';

import 'browse_layout_test.dart' show TestLanguageFilter;

void main() {
  testWidgets('Einklappbare Seitenleiste: schmal, mit Maus offen, Klick wählt Bereich', (tester) async {
    if (Platform.environment['DETAIL_SHOTS'] != null) {
      final font = File('/System/Library/Fonts/Supplemental/Arial.ttf').readAsBytesSync();
      await (FontLoader('Roboto')..addFont(Future.value(ByteData.view(font.buffer)))).load();
    }
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          languageFilterProvider.overrideWith(TestLanguageFilter.new),
          availableLanguagesProvider.overrideWithValue([]),
          activePlaylistProvider.overrideWithValue(null),
          networkBlockedProvider.overrideWithValue(false),
          vpnStatusProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          debugShowCheckedModeBanner: false,
          home: const Scaffold(
            body: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: Color(0xFF223344))),
                Positioned(left: 0, top: 0, bottom: 0, child: GlassSidebar(collapsible: true)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(GlassSidebar)).width, GlassSidebar.collapsedWidth);
    final shots = Platform.environment['DETAIL_SHOTS'] != null;
    if (shots) await expectLater(find.byType(Scaffold), matchesGoldenFile('shots/sidebar_collapsed.png'));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(400, 300));
    await mouse.moveTo(const Offset(30, 300));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(GlassSidebar)).width, GlassSidebar.width);
    if (shots) await expectLater(find.byType(Scaffold), matchesGoldenFile('shots/sidebar_open.png'));

    await tester.tap(find.text('Serien'));
    await tester.pump();
    final container = ProviderScope.containerOf(tester.element(find.byType(GlassSidebar)));
    expect(container.read(sectionProvider), AppSection.series);

    await mouse.moveTo(const Offset(600, 300));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(GlassSidebar)).width, GlassSidebar.collapsedWidth);
    expect(tester.takeException(), isNull);
  });
}
