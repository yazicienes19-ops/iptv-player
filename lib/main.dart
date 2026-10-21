import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wakelock_plus/wakelock_plus.dart';

import 'player/player_controller.dart';
import 'providers/app_providers.dart';
import 'services/device.dart';
import 'services/local_store.dart';
import 'services/secure_store.dart';
import 'ui/home/home_shell.dart';
import 'ui/onboarding/add_playlist_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // Keine Konsolenausgaben in Release-Builds: macOS/iOS schreiben sie sonst ins Systemprotokoll.
  if (kReleaseMode) debugPrint = (String? message, {int? wrapWidth}) {};
  final prefs = await SharedPreferences.getInstance();
  final store = await LocalStore.open(prefs, SecureStore());
  final isTelevision = await detectTelevision();

  runApp(
    ProviderScope(
      // Fehler (z. B. Server offline) sofort zeigen statt still im Hintergrund zu wiederholen.
      retry: (retryCount, error) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        localStoreProvider.overrideWithValue(store),
        isTelevisionProvider.overrideWithValue(isTelevision),
      ],
      child: const IptvApp(),
    ),
  );
}

class IptvApp extends ConsumerWidget {
  const IptvApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPlaylist = ref.watch(activePlaylistProvider) != null;
    // Bildschirm während der Wiedergabe nicht abschalten (Fernseher, Handy, Laptop).
    // Gestartete Live-Sender für „Weiterschauen“ merken.
    ref.listen(playerControllerProvider.select((s) => s.channel), (_, channel) {
      if (channel != null) ref.read(recentChannelsProvider.notifier).add(channel);
    });
    ref.listen(playerControllerProvider.select((s) => s.channel != null && !s.hasError), (_, playing) {
      WakelockPlus.toggle(enable: playing).ignore();
    });
    return MaterialApp(
      title: 'Pulse Media',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: hasPlaylist ? const HomeShell() : const AddPlaylistScreen(isOnboarding: true),
    );
  }
}
