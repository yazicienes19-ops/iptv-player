import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/models/content_type.dart';
import 'package:iptv_player/player/player_controller.dart';
import 'package:iptv_player/providers/app_providers.dart';
import 'package:iptv_player/ui/browse/poster_card.dart';
import 'package:iptv_player/ui/widgets/channel_views.dart';

/// Ersetzt den echten Player (libmpv gibt es im Test nicht) und merkt sich Aufrufe.
class FakePlayerController extends PlayerController {
  final played = <Channel>[];

  @override
  PlaybackState build() => const PlaybackState();

  @override
  Future<void> play(Channel channel, {List<Channel>? queue}) async {
    played.add(channel);
    state = PlaybackState(channel: channel, queue: queue ?? const []);
  }
}

class FakeFavorites extends FavoritesNotifier {
  @override
  List<Channel> build() => const [];

  @override
  Future<void> toggle(Channel channel) async {
    state = state.contains(channel) ? state.where((c) => c != channel).toList() : [...state, channel];
  }
}

Channel live(int i) => Channel(id: 'l$i', name: 'Sender $i', streamUrl: 'http://x/$i.ts', type: ContentType.live);
Channel movie(int i) => Channel(id: 'm$i', name: 'Film $i', streamUrl: 'http://x/$i.mp4', type: ContentType.movie);

Future<ProviderContainer> pump(WidgetTester tester, Widget child) async {
  final player = FakePlayerController();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerControllerProvider.overrideWith(() => player),
        favoritesProvider.overrideWith(FakeFavorites.new),
        networkBlockedProvider.overrideWithValue(false),
        userAgentProvider.overrideWithValue('Test'),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  // Wie eine Fernbedienung: Tastatur-Modus, damit Fokusrahmen erscheinen.
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  return ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
}

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  // Kein pumpAndSettle: Der LIVE-Equalizer animiert endlos.
  await tester.pump(const Duration(milliseconds: 300));
}

String? focusedChannel(WidgetTester tester) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return null;
  final tile = focused.findAncestorWidgetOfExactType<ChannelTile>();
  final poster = focused.findAncestorWidgetOfExactType<PosterCard>();
  return tile?.channel.name ?? poster?.channel.name;
}

void main() {
  testWidgets('Senderliste: Pfeil runter wandert, OK startet den fokussierten Sender', (tester) async {
    final channels = [for (var i = 1; i <= 5; i++) live(i)];
    final container = await pump(tester, ChannelList(channels: channels));

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedChannel(tester), 'Sender 1');
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedChannel(tester), 'Sender 3');
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focusedChannel(tester), 'Sender 2');

    await press(tester, LogicalKeyboardKey.select);
    final player = container.read(playerControllerProvider.notifier) as FakePlayerController;
    expect(player.played.map((c) => c.name), ['Sender 2']);
  });

  testWidgets('Der Favoriten-Stern ist kein Fokusziel, die Menü-Taste schaltet den Favoriten', (tester) async {
    final channels = [live(1), live(2)];
    final container = await pump(tester, ChannelList(channels: channels));

    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    // Ohne ausgeschlossenen Stern landete der zweite Druck auf dessen Knopf.
    expect(focusedChannel(tester), 'Sender 2');

    await press(tester, LogicalKeyboardKey.contextMenu);
    expect(container.read(favoritesProvider).map((c) => c.name), ['Sender 2']);
  });

  testWidgets('Poster-Reihe: Pfeil rechts wandert, OK öffnet den Film', (tester) async {
    final movies = [for (var i = 1; i <= 4; i++) movie(i)];
    final opened = <String>[];
    await pump(
      tester,
      SizedBox(
        height: 300,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final m in movies) PosterCard(channel: m, queue: movies, width: 120, onTap: () => opened.add(m.name)),
          ],
        ),
      ),
    );

    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedChannel(tester), 'Film 1');
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedChannel(tester), 'Film 3');

    await press(tester, LogicalKeyboardKey.enter);
    expect(opened, ['Film 3']);
  });
}
