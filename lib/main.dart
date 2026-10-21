import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/app_providers.dart';
import 'ui/home/home_shell.dart';
import 'ui/onboarding/add_playlist_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  runApp(ProviderScope(
    // Fehler (z. B. Server offline) sofort zeigen statt still im Hintergrund zu wiederholen.
    retry: (retryCount, error) => null,
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const IptvApp(),
  ));
}

class IptvApp extends ConsumerWidget {
  const IptvApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPlaylist = ref.watch(activePlaylistProvider) != null;
    return MaterialApp(
      title: 'IPTV Player',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: hasPlaylist ? const HomeShell() : const AddPlaylistScreen(isOnboarding: true),
    );
  }
}
