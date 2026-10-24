import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/models/catalog.dart';
import 'package:iptv_player/models/category.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/models/content_type.dart';
import 'package:iptv_player/providers/app_providers.dart';
import 'package:iptv_player/ui/browse/browse_view.dart';
import 'package:iptv_player/ui/home/sidebar.dart';
import 'package:iptv_player/ui/theme.dart';

class TestFavorites extends FavoritesNotifier {
  @override
  List<Channel> build() => [];

  @override
  Future<void> toggle(Channel channel) async {
    state = state.contains(channel) ? [] : [channel];
  }
}

class TestLanguageFilter extends LanguageFilterNotifier {
  @override
  String? build() => null;
}

void main() {
  const channel = Channel(
    id: 'movie',
    name: 'A very long cinematic title for an evening of great entertainment (2026) 4K HDR',
    streamUrl: 'http://example.test/movie.mp4',
    type: ContentType.movie,
    categoryId: 'new',
  );
  for (final width in [320.0, 390.0, 800.0, 900.0, 1280.0]) {
    testWidgets('Hero actions and long metadata fit at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            favoritesProvider.overrideWith(TestFavorites.new),
            catalogProvider(ContentType.movie).overrideWith(
              (ref) async => const Catalog(
                categories: [
                  Category(
                    id: 'new',
                    name: 'Neuerscheinungen und ausgewählte Filme aus aller Welt',
                    type: ContentType.movie,
                  ),
                ],
                channels: [channel],
              ),
            ),
            mediaDetailsProvider(channel).overrideWith(
              (ref) async => const MediaDetails(
                year: '2026',
                rating: 8.8,
                plot: 'An unusually long plot description for this film that should wrap naturally across several lines, remaining readable without displacing the main actions or clipping the content of the banner.',
              ),
            ),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: HeroCarousel(
                  items: [channel],
                  compact: width < 800,
                  leftInset: width >= 800 ? 232 : 0,
                  horizontalPadding: width < 800 ? 16 : 40,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull);
      expect(find.text('Abspielen'), findsOneWidget);
      await tester.tap(find.text('Meine Liste'));
      await tester.pump();
      expect(find.text('In meiner Liste'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final height in [520.0, 720.0]) {
    testWidgets('Sidebar navigation remains usable in a $height px tall window', (tester) async {
      tester.view.physicalSize = Size(900, height);
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
            home: const Scaffold(body: GlassSidebar()),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Filme'));
      await tester.pump();
      final container = ProviderScope.containerOf(tester.element(find.byType(GlassSidebar)));
      expect(container.read(sectionProvider), AppSection.movies);
      expect(tester.takeException(), isNull);
    });
  }
}
