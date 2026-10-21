import 'dart:async';

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

  /// Dauer der macOS-Vollbild-Animation (Fenster-Zoom).
  static const _windowAnimation = Duration(milliseconds: 700);

  bool _nativeFullscreen = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(playerControllerProvider.notifier);
    // Seitenübergang und Fenster-Zoom nicht gleichzeitig laufen lassen: Diese
    // Überlagerung hat in langen Sitzungen Impeller zum Absturz gebracht.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final animation = ModalRoute.of(context)?.animation;
      if (animation == null || animation.isCompleted) {
        _enterNativeFullscreen();
      } else {
        void listener(AnimationStatus status) {
          if (status != AnimationStatus.completed) return;
          animation.removeStatusListener(listener);
          _enterNativeFullscreen();
        }

        animation.addStatusListener(listener);
      }
    });
  }

  void _enterNativeFullscreen() {
    if (!mounted || _closing) return;
    setState(() => _nativeFullscreen = true);
    unawaited(defaultEnterNativeFullscreen());
  }

  /// Erst das Fenster aus dem Vollbild holen, dann die Seite schließen.
  Future<void> _close() async {
    if (_closing) return;
    final wasNative = _nativeFullscreen;
    setState(() {
      _closing = true;
      _nativeFullscreen = false;
    });
    if (wasNative) {
      // Nicht auf die Antwort warten: media_kit meldet das Verlassen des
      // Vollbilds nicht immer zurück. Stattdessen die Fenster-Animation abwarten.
      unawaited(defaultExitNativeFullscreen());
      await Future<void>.delayed(_windowAnimation);
    }
    // Einen Frame abwarten, damit PopScope das Schließen schon erlaubt.
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    if (_nativeFullscreen) defaultExitNativeFullscreen();
    // Wie bei Netflix: Filme und Folgen enden mit dem Schließen, Live läuft eingebettet weiter.
    _controller.stopIfOnDemand();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _closing || !_nativeFullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: PlayerView(isFullscreen: true, onToggleFullscreen: _close),
      ),
    );
  }
}
