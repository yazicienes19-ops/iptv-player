// Belastungstest: Film starten + natives Vollbild, mehrfach hintereinander.
// Reproduziert einen Impeller-Absturz beim Vollbild-Übergang (siehe README).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/models/content_type.dart';
import 'package:iptv_player/player/fullscreen_player_page.dart';
import 'package:iptv_player/player/player_controller.dart';
import 'package:iptv_player/providers/app_providers.dart';
import 'package:iptv_player/services/local_store.dart';
import 'package:iptv_player/services/secure_store.dart';
import 'package:iptv_player/ui/theme.dart';
import 'package:iptv_player/ui/widgets/media_image.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> wait(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 16));
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
}

const rounds = int.fromEnvironment('ROUNDS', defaultValue: 10);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Vollbild-Übergang $rounds×', (tester) async {
    MediaKit.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    final store = await LocalStore.open(prefs, SecureStore());
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        localStoreProvider.overrideWithValue(store),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        theme: buildAppTheme(),
        // Wie die Detailseite: weichgezeichneter Hintergrund unter dem Vollbild.
        home: const Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              BackdropImage(
                backdrop: null,
                poster: 'https://upload.wikimedia.org/wikipedia/commons/8/8f/Sintel_poster.jpg',
              ),
              Center(child: Text('Start')),
            ],
          ),
        ),
      ),
    ));
    final container = ProviderScope.containerOf(tester.element(find.text('Start')));
    final controller = container.read(playerControllerProvider.notifier);

    const movies = [
      'https://download.blender.org/durian/trailer/sintel_trailer-720p.mp4',
      'https://download.blender.org/demo/movies/ToS/tears_of_steel_720p.mov',
    ];
    for (var i = 0; i < rounds; i++) {
      final channel = Channel(id: 'm$i', name: 'Film $i', streamUrl: movies[i % movies.length], type: ContentType.movie);
      controller.play(channel, queue: [channel]);
      navigatorKey.currentState!.push(FullscreenPlayerPage.route());
      await wait(tester, const Duration(milliseconds: 2500));
      navigatorKey.currentState!.pop();
      await wait(tester, const Duration(milliseconds: 1500));
      // ignore: avoid_print
      print('RUNDE ${i + 1}/$rounds ok');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
