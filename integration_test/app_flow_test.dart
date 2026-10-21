// Ende-zu-Ende-Test mit echtem libmpv und echten Streams.
//
// Erwartet eine M3U unter http://127.0.0.1:8765/test.m3u (siehe README).
// Ausgaben mit `SHOT:` markieren Momente für externe Fensterfotos.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:iptv_player/main.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/models/content_type.dart';
import 'package:iptv_player/models/playlist_credentials.dart';
import 'package:iptv_player/player/player_controller.dart';
import 'package:iptv_player/providers/app_providers.dart';
import 'package:iptv_player/services/app_settings.dart';
import 'package:iptv_player/services/local_store.dart';
import 'package:iptv_player/services/secure_store.dart';
import 'package:iptv_player/ui/home/home_shell.dart';
import 'package:iptv_player/ui/widgets/channel_views.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

const playlistUrl = 'http://127.0.0.1:8765/test.m3u';

Future<void> wait(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<void> shot(WidgetTester tester, String name) async {
  await wait(tester, const Duration(milliseconds: 1500));
  // ignore: avoid_print
  print('SHOT:$name');
  await wait(tester, const Duration(milliseconds: 2500));
}

/// Wartet, bis der Stream Bild/Ton liefert oder endgültig fehlschlägt.
Future<String> awaitPlayback(WidgetTester tester, ProviderContainer container, {int maxSeconds = 30}) async {
  final controller = container.read(playerControllerProvider.notifier);
  final start = DateTime.now();
  while (DateTime.now().difference(start).inSeconds < maxSeconds) {
    await wait(tester, const Duration(milliseconds: 250));
    final state = container.read(playerControllerProvider);
    if (state.hasError && state.retryCountdown == null) return 'FEHLER: ${state.error}';
    if (!state.isLoading && !state.hasError) {
      final p = controller.player.state;
      final secs = DateTime.now().difference(start).inMilliseconds / 1000;
      return 'OK nach ${secs.toStringAsFixed(1)} s, ${p.width ?? 0}x${p.height ?? 0}, '
          'Ton ${p.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').length}, '
          'UT ${p.tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').length}';
    }
  }
  return 'ZEITÜBERSCHREITUNG im Test';
}

Finder fieldWithHint(String hint) =>
    find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == hint);

void pop(WidgetTester tester) => tester.state<NavigatorState>(find.byType(Navigator).first).pop();

void report(String name, String result) {
  // ignore: avoid_print
  print('PLAYBACK | $name | $result');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Wiedergabe und Oberfläche mit echten Streams', (tester) async {
    MediaKit.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    final secure = SecureStore();
    await secure.deleteAll();
    final store = await LocalStore.open(prefs, secure);
    await store.savePlaylists([
      const PlaylistCredentials(id: 'demo', name: 'Demo (öffentliche Sender)', kind: PlaylistKind.m3uUrl, m3uUrl: playlistUrl),
    ]);
    await store.saveActivePlaylistId('demo');

    // Gleicher Widget-Baum für beide Größen, damit Player und Zustand erhalten bleiben.
    final phone = ValueNotifier(false);
    await tester.pumpWidget(ValueListenableBuilder(
      valueListenable: phone,
      builder: (context, isPhone, child) => ColoredBox(
        color: const Color(0xFF000000),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: isPhone ? BoxConstraints.tight(const Size(393, 852)) : const BoxConstraints(),
            child: child,
          ),
        ),
      ),
      child: ProviderScope(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          localStoreProvider.overrideWithValue(store),
        ],
        child: const IptvApp(),
      ),
    ));
    await wait(tester, const Duration(seconds: 4));
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    final controller = container.read(playerControllerProvider.notifier);

    final live = (await container.read(catalogProvider(ContentType.live).future)).channels;
    final movies = (await container.read(catalogProvider(ContentType.movie).future)).channels;
    final series = (await container.read(catalogProvider(ContentType.series).future)).channels;
    // ignore: avoid_print
    print('KATALOG | Live ${live.length} | Filme ${movies.length} | Serien ${series.length}');
    expect(live.length, greaterThan(200));

    await shot(tester, '01_live_liste');

    // --- Live über die Oberfläche antippen ---
    await tester.enterText(fieldWithHint('Live TV durchsuchen'), 'Das Erste');
    await wait(tester, const Duration(milliseconds: 800));
    await shot(tester, '01b_live_suche');
    await tester.tap(find.descendant(of: find.byType(ChannelTile), matching: find.text('Das Erste')).first);
    report('Das Erste HD (UI-Tap)', await awaitPlayback(tester, container));
    await shot(tester, '02_live_laeuft');

    // Unordentliche Namen, Trennzeilen und Qualitäts-Badges
    await tester.tap(find.descendant(of: fieldWithHint('Live TV durchsuchen'), matching: find.byIcon(Icons.close)));
    final formatting = (await container.read(catalogProvider(ContentType.live).future))
        .categories
        .firstWhere((c) => c.name == 'DE | Formatierung');
    container.read(selectedCategoryProvider(ContentType.live).notifier).select(formatting);
    await wait(tester, const Duration(seconds: 1));
    await tester.tap(find.descendant(of: find.byType(ChannelTile), matching: find.text('DAS ERSTE')).first);
    report('Bereinigter Name antippen', await awaitPlayback(tester, container));
    await wait(tester, const Duration(seconds: 3));
    await shot(tester, '02b_formatierung');
    await tester.enterText(fieldWithHint('Kategorie suchen …'), 'de |');
    await shot(tester, '02c_kategorie_filter');
    await tester.enterText(fieldWithHint('Kategorie suchen …'), '');
    container.read(selectedCategoryProvider(ContentType.live).notifier).select(null);

    Channel byName(List<Channel> list, String name) => list.firstWhere((c) => c.name.startsWith(name));

    // --- Weitere Live-Sender direkt über den Controller ---
    for (final name in ['tagesschau24', 'ARD-alpha', 'KiKA HD', 'ZDF', '3sat']) {
      final channel = byName(live, name);
      await controller.play(channel, queue: live);
      report(channel.name, await awaitPlayback(tester, container));
    }

    // --- Senderwechsel per Tastatur-Logik (nächster Sender in der Liste) ---
    await controller.play(byName(live, 'tagesschau24'), queue: live);
    await awaitPlayback(tester, container);
    await controller.next();
    report('Kanalwechsel → ${container.read(playerControllerProvider).channel?.name}',
        await awaitPlayback(tester, container));

    // --- Filme / VOD inkl. MOV, AVI, HLS ---
    for (final channel in movies) {
      await controller.play(channel, queue: movies);
      report(channel.name, await awaitPlayback(tester, container, maxSeconds: 40));
    }

    // Spulen in einem Film
    final tos = byName(movies, 'Tears of Steel');
    await controller.play(tos, queue: movies);
    await awaitPlayback(tester, container, maxSeconds: 40);
    await controller.player.seek(const Duration(minutes: 5));
    await wait(tester, const Duration(seconds: 4));
    report('Spulen auf 5:00', 'Position ${controller.player.state.position.inSeconds} s');

    // Tonspurwechsel bei Das Erste (Deutsch, Klare Sprache, Audiodeskription)
    await controller.play(byName(live, 'Das Erste HD'), queue: live);
    await awaitPlayback(tester, container);
    await wait(tester, const Duration(seconds: 2));
    final audio = controller.player.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
    report('Tonspuren Das Erste', audio.map((t) => t.title ?? t.id).join(', '));
    if (audio.length > 1) {
      await controller.player.setAudioTrack(audio[1]);
      await wait(tester, const Duration(seconds: 2));
      report('Tonspur wechseln', 'aktiv: ${controller.player.state.track.audio.title ?? controller.player.state.track.audio.id}');
    }
    await controller.stop();

    // --- Fehlerfall mit automatischer Wiederholung ---
    final offline = byName(live, 'Offline-Sender');
    await controller.play(offline, queue: movies);
    await wait(tester, const Duration(seconds: 2));
    final retryState = container.read(playerControllerProvider);
    report('Offline: Auto-Retry aktiv', 'Versuch ${retryState.retryAttempt}, Countdown ${retryState.retryCountdown}');
    // Bis zum endgültigen Fehler nach 3 Versuchen (3 + 6 + 9 s plus Öffnen).
    report('Offline: nach allen Versuchen', await awaitPlayback(tester, container, maxSeconds: 40));
    await controller.stop();

    // --- Oberfläche: Filme im Netflix-Stil ---
    container.read(sectionProvider.notifier).select(AppSection.movies);
    await wait(tester, const Duration(seconds: 3));
    await shot(tester, '03_filme_uebersicht');

    await tester.tap(find.text('Mehr Infos'));
    await wait(tester, const Duration(seconds: 2));
    await shot(tester, '04_film_details');
    await tester.drag(find.byType(CustomScrollView).last, const Offset(0, -400));
    await shot(tester, '04b_film_details_unten');

    await tester.tap(find.text('Abspielen').last);
    await awaitPlayback(tester, container, maxSeconds: 40);
    await shot(tester, '05_film_vollbild');
    await tester.state<NavigatorState>(find.byType(Navigator).first).maybePop();
    await wait(tester, const Duration(seconds: 2));
    report('Vollbild schließen stoppt Film', 'Kanal danach: ${container.read(playerControllerProvider).channel?.name}');
    pop(tester);

    container.read(sectionProvider.notifier).select(AppSection.series);
    await wait(tester, const Duration(seconds: 3));
    await shot(tester, '06_serien_uebersicht');

    // Favoriten füllen und anzeigen
    final favorites = container.read(favoritesProvider.notifier);
    for (final c in [byName(live, 'Das Erste'), byName(live, 'tagesschau24'), byName(live, 'KiKA HD'), tos, byName(movies, 'Sintel')]) {
      await favorites.toggle(c);
    }
    container.read(sectionProvider.notifier).select(AppSection.favorites);
    await wait(tester, const Duration(seconds: 2));
    await shot(tester, '07_favoriten');

    // --- Handy-Layout (iPhone-Größe) ---
    // --- Datenschutz: Schlüsselbund, User-Agent, Kill-Switch ---
    final secret = await secure.read('playlist.demo');
    final prefsDump = prefs.getKeys().map((k) => '$k=${prefs.get(k)}').join('\n');
    report('Schlüsselbund enthält Playlist', '${secret != null && secret.contains('test.m3u')}');
    report('Prefs ohne M3U-URL/Passwort', '${!prefsDump.contains('127.0.0.1:8765/test.m3u')}');

    final probe = byName(live, 'UA-Probe');
    container.read(settingsProvider.notifier).update((s) => s.copyWith(userAgentPreset: UserAgentPreset.appleTv));
    await controller.play(probe, queue: live);
    await wait(tester, const Duration(seconds: 3));
    await controller.stop();
    final uaLog = (await HttpClient().getUrl(Uri.parse('http://127.0.0.1:8765/ua-log')).then((r) => r.close()))
        .transform(utf8.decoder)
        .join();
    final seen = (jsonDecode(await uaLog) as List).cast<Map<String, dynamic>>();
    String agentsFor(String path) => seen.where((e) => (e['path'] as String).startsWith(path)).map((e) => e['ua']).toSet().join(' | ');
    report('User-Agent beim M3U-Abruf', agentsFor('/test.m3u'));
    report('User-Agent von libmpv', agentsFor('/ua-probe'));

    container.read(settingsProvider.notifier).update((s) => s.copyWith(killSwitch: true));
    await wait(tester, const Duration(seconds: 4));
    await controller.play(byName(live, 'tagesschau24'), queue: live);
    await wait(tester, const Duration(seconds: 2));
    report('Kill-Switch ohne VPN', container.read(playerControllerProvider).error ?? 'NICHT blockiert!');
    await shot(tester, '12_killswitch');
    container.read(settingsProvider.notifier).update((s) => s.copyWith(killSwitch: false, userAgentPreset: UserAgentPreset.vlc));
    await controller.stop();

    container.read(searchQueryProvider(AppSection.live).notifier).set('');
    container.read(sectionProvider.notifier).select(AppSection.live);
    await controller.play(byName(live, 'tagesschau24'), queue: live);
    phone.value = true;
    await awaitPlayback(tester, container);
    await shot(tester, '08_handy_live');
    container.read(sectionProvider.notifier).select(AppSection.movies);
    await wait(tester, const Duration(seconds: 2));
    await shot(tester, '09_handy_filme');
    await tester.tap(find.text('Mehr Infos'));
    await wait(tester, const Duration(seconds: 2));
    await shot(tester, '10_handy_details');
    pop(tester);
    phone.value = false;
    await wait(tester, const Duration(seconds: 1));

    // --- Panik-Knopf über die Oberfläche ---
    await tester.tap(find.text('Einstellungen'));
    await wait(tester, const Duration(seconds: 1));
    await shot(tester, '13_einstellungen');
    await tester.scrollUntilVisible(find.text('Alle lokalen Daten & Cache sofort löschen'), 300);
    await tester.tap(find.text('Alle lokalen Daten & Cache sofort löschen'));
    await wait(tester, const Duration(seconds: 1));
    await tester.tap(find.text('Alles löschen'));
    await wait(tester, const Duration(seconds: 3));
    report('Nach Panik: Schlüsselbund leer', '${await secure.read('playlist.demo') == null}');
    report('Nach Panik: Einstellungen leer', '${prefs.getKeys().isEmpty} (${prefs.getKeys().join(', ')})');
    report('Nach Panik: Startbildschirm', '${find.text('Willkommen').evaluate().isNotEmpty}');
    await shot(tester, '14_nach_panik');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
