import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'player_controller.dart';
import 'player_view.dart';

/// Vollbild-Ansicht. Teilt sich den laufenden Player mit der eingebetteten Ansicht.
class FullscreenPlayerPage extends ConsumerStatefulWidget {
  const FullscreenPlayerPage({super.key});

  static Route<void> route() => PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, _, _) => const FullscreenPlayerPage(),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
      );

  @override
  ConsumerState<FullscreenPlayerPage> createState() => _FullscreenPlayerPageState();
}

class _FullscreenPlayerPageState extends ConsumerState<FullscreenPlayerPage> {
  // In initState holen: in dispose() ist `ref` nicht mehr benutzbar.
  late final PlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(playerControllerProvider.notifier);
    defaultEnterNativeFullscreen();
  }

  @override
  void dispose() {
    defaultExitNativeFullscreen();
    // Wie bei Netflix: Filme und Folgen enden mit dem Schließen, Live läuft eingebettet weiter.
    _controller.stopIfOnDemand();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PlayerView(
        isFullscreen: true,
        onToggleFullscreen: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}
