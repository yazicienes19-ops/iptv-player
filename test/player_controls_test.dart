import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/player_controller.dart';
import 'package:iptv_player/player/player_view.dart';
import 'package:media_kit/media_kit.dart';

class _SpyPlayer implements Player {
  var playPauseCalls = 0;
  bool isPlaying = true;
  final playingEvents = StreamController<bool>.broadcast();

  @override
  PlayerState get state => PlayerState(playing: isPlaying);

  @override
  PlayerStream get stream => _SpyStreams(playingEvents.stream);

  void emitPlaying(bool playing) {
    isPlaying = playing;
    playingEvents.add(playing);
  }

  @override
  Future<void> playOrPause() async => playPauseCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SpyStreams implements PlayerStream {
  _SpyStreams(this.playing);

  @override
  final Stream<bool> playing;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SpyController extends PlayerController {
  final spy = _SpyPlayer();
  var channelChanges = 0;

  @override
  PlaybackState build() {
    player = spy;
    ref.onDispose(spy.playingEvents.close);
    // No channel/video decoder is needed to verify input routing and lock.
    return const PlaybackState();
  }

  @override
  Future<void> next() async => channelChanges++;

  @override
  Future<void> previous() async => channelChanges++;
}

void main() {
  test('10-second jumps stay within the current title', () {
    expect(playbackSeekTarget(const Duration(seconds: 3), const Duration(minutes: 2), -10), Duration.zero);
    expect(
      playbackSeekTarget(const Duration(seconds: 115), const Duration(minutes: 2), 10),
      const Duration(minutes: 2),
    );
    expect(
      playbackSeekTarget(const Duration(seconds: 30), const Duration(minutes: 2), -10),
      const Duration(seconds: 20),
    );
    expect(playbackSeekTarget(const Duration(seconds: 30), Duration.zero, 10), const Duration(seconds: 40));
  });

  test('route Back first unlocks and a second Back exits', () {
    final lock = PlayerLockController();
    var exits = 0;
    lock.lock();
    lock.handleBack(() => exits++);
    expect(lock.isLocked, isFalse);
    expect(exits, 0);
    lock.handleBack(() => exits++);
    expect(exits, 1);
    lock.dispose();
  });

  testWidgets('lock blocks shortcuts and double taps; Escape unlocks before exit', (tester) async {
    final lock = PlayerLockController();
    final controller = _SpyController();
    var exits = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerControllerProvider.overrideWith(() => controller)],
        child: MaterialApp(
          home: Scaffold(
            body: PlayerView(isFullscreen: true, lockController: lock, onToggleFullscreen: () => exits++),
          ),
        ),
      ),
    );
    await tester.pump();
    lock.lock();
    await tester.pump();
    expect(find.text('Bildschirm entsperren'), findsOneWidget);
    for (final key in [LogicalKeyboardKey.mediaPlayPause, LogicalKeyboardKey.channelUp, LogicalKeyboardKey.keyF]) {
      await tester.sendKeyEvent(key);
    }
    await tester.tapAt(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 400));
    expect(lock.isLocked, isTrue);
    expect(controller.spy.playPauseCalls, 0);
    expect(controller.channelChanges, 0);
    expect(exits, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(lock.isLocked, isFalse);
    expect(exits, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(exits, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    lock.dispose();
  });

  testWidgets('visible unlock action works with remote Enter', (tester) async {
    final lock = PlayerLockController();
    final controller = _SpyController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerControllerProvider.overrideWith(() => controller)],
        child: MaterialApp(
          home: Scaffold(body: PlayerView(isFullscreen: true, lockController: lock)),
        ),
      ),
    );
    lock.lock();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(lock.isLocked, isFalse);
    expect(controller.spy.playPauseCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    lock.dispose();
  });

  testWidgets('pause reveals controls and stops auto-hide until playback resumes', (tester) async {
    final controller = _SpyController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerControllerProvider.overrideWith(() => controller)],
        child: const MaterialApp(home: Scaffold(body: PlayerView(isFullscreen: true))),
      ),
    );
    MouseCursor cursor() => tester.widget<MouseRegion>(find.byKey(const ValueKey('playback-surface'))).cursor;
    await tester.pump(const Duration(seconds: 4));
    expect(cursor(), SystemMouseCursors.none);

    controller.spy.emitPlaying(false);
    await tester.pump();
    await tester.pump();
    expect(cursor(), isNot(SystemMouseCursors.none));
    await tester.pump(const Duration(seconds: 4));
    expect(cursor(), isNot(SystemMouseCursors.none));
    // A tap on a paused movie must not take its controls away either.
    await tester.tapAt(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 400));
    expect(cursor(), isNot(SystemMouseCursors.none));

    controller.spy.emitPlaying(true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(cursor(), SystemMouseCursors.none);
    // A pause arriving while a fresh hide timer runs cancels that timer.
    await tester.tapAt(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 400));
    controller.spy.emitPlaying(false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(cursor(), isNot(SystemMouseCursors.none));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in [const Size(1280, 720), const Size(390, 844), const Size(320, 200)]) {
    testWidgets('transport and settings remain usable at ${size.width} × ${size.height}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final seeks = <int>[];
      var backs = 0;
      var locks = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaybackControls(
              title: 'Ein sehr langer Filmtitel, der auch in einem kleinen Fenster lesbar bleibt',
              isLive: false,
              isPlaying: true,
              isFullscreen: true,
              isFavorite: false,
              onPlayPause: () {},
              onSeek: seeks.add,
              onLock: () => locks++,
              onFavorite: () {},
              onBack: () => backs++,
              onToggleFullscreen: () {},
              onNext: () {},
              onQueue: () {},
              timeline: const SizedBox(height: 32, child: Text('00:30 ━━━━━ 01:40:00')),
              volume: IconButton(onPressed: () {}, icon: const Icon(Icons.volume_up), tooltip: 'Lautstärke'),
              tracks: IconButton(onPressed: () {}, icon: const Icon(Icons.subtitles), tooltip: 'Ton & Untertitel'),
              fitLabel: 'Original',
              onCycleFit: () {},
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('10 Sekunden zurück'));
      await tester.tap(find.byTooltip('10 Sekunden vor'));
      await tester.tap(find.byTooltip('Zurück'));
      await tester.tap(find.byTooltip('Bildschirm sperren'));
      expect(seeks, [-10, 10]);
      expect(backs, 1);
      expect(locks, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
