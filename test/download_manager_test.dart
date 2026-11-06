import 'dart:async';
import 'dart:convert';
import 'dart:io' hide ContentType;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/models/content_type.dart';
import 'package:iptv_player/services/download_manager.dart';

/// Kleiner Anbieter-Ersatz: liefert eine Datei mit Range-Unterstützung, optional gedrosselt.
class _FakeProvider {
  _FakeProvider(this.body);

  final Uint8List body;
  late HttpServer server;
  final ranges = <String?>[];
  bool throttle = false;
  int throttleMs = 20;
  bool htmlError = false;

  /// Gleichzeitig offene Verbindungen; über [connectionLimit] gibt es 403 wie bei echten Anbietern.
  int open = 0;
  int maxOpen = 0;
  int? connectionLimit;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final res = req.response;
      ranges.add(req.headers.value('range'));
      if (connectionLimit != null && open >= connectionLimit!) {
        res.statusCode = 403;
        await res.close();
        return;
      }
      open++;
      if (open > maxOpen) maxOpen = open;
      if (htmlError) {
        res.headers.set('content-type', 'text/html');
        res.write('<html>Konto gesperrt</html>');
        await res.close();
        return;
      }
      var start = 0;
      var end = body.length - 1;
      final range = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(req.headers.value('range') ?? '');
      if (range != null) {
        start = int.parse(range.group(1)!);
        if (range.group(2)!.isNotEmpty) end = int.parse(range.group(2)!);
        res.statusCode = 206;
        res.headers.set('content-range', 'bytes $start-$end/${body.length}');
      }
      res.headers.set('content-type', 'video/mp4');
      res.contentLength = end - start + 1;
      const chunk = 16 * 1024;
      try {
        for (var i = start; i <= end; i += chunk) {
          res.add(body.sublist(i, (i + chunk).clamp(0, end + 1)));
          if (throttle) await Future<void>.delayed(Duration(milliseconds: throttleMs));
          await res.flush();
        }
        await res.close();
      } catch (_) {
        // Client hat abgebrochen.
      } finally {
        open--;
      }
    });
  }

  String url(String name) => 'http://127.0.0.1:${server.port}/movie/u/p/$name';
}

Future<void> _until(bool Function() condition, {Duration timeout = const Duration(seconds: 10)}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('Bedingung nicht erreicht');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late Directory dir;
  late _FakeProvider provider;
  late MemoryDownloadIndexStore store;
  final body = Uint8List.fromList(List.generate(600 * 1024, (i) => i % 251));

  DownloadEngine engine() => DownloadEngine(dio: Dio(), directory: () async => dir, store: store, onChange: (_) {});

  Channel movie(String id, {String? url}) =>
      Channel(id: id, name: 'Film $id', streamUrl: url ?? provider.url('$id.mkv'), type: ContentType.movie);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ipflix-downloads');
    provider = _FakeProvider(body);
    await provider.start();
    store = MemoryDownloadIndexStore();
  });

  tearDown(() async {
    await provider.server.close(force: true);
    await dir.delete(recursive: true);
  });

  test('lädt eine Datei vollständig und behält die Endung', () async {
    final e = engine();
    await e.enqueue(movie('1'), playlistId: 'a', title: 'Spider-Man: No Way Home', subtitle: '2021');
    await _until(() => e.items.single.isDone);
    final item = e.items.single;
    expect(item.fileName, endsWith('.mkv'));
    expect(item.fileName, startsWith('Spider-Man No Way Home - 2021'));
    expect(await (await e.fileOf(item)).readAsBytes(), body);
    expect(item.received, body.length);
    // Das Verzeichnis liegt im (hier simulierten) Schlüsselbund.
    expect(jsonDecode(store.value!) as List, hasLength(1));
  });

  test('Pause und Weiterladen setzen per Range an derselben Stelle fort', () async {
    provider.throttle = true;
    final e = engine();
    await e.enqueue(movie('2'), playlistId: 'a', title: 'Langsam');
    await _until(() => e.items.single.received > 64 * 1024);
    await e.pause(e.items.single.id);
    await _until(() => e.items.single.status == DownloadStatus.paused);
    final partial = e.items.single.received;
    expect(partial, lessThan(body.length));

    provider.throttle = false;
    await e.resume(e.items.single.id);
    await _until(() => e.items.single.isDone);
    expect(provider.ranges.last, startsWith('bytes='));
    expect(int.parse(RegExp(r'\d+').firstMatch(provider.ranges.last!)!.group(0)!), greaterThan(0));
    expect(await (await e.fileOf(e.items.single)).readAsBytes(), body);
  });

  test('Fehlerseite des Anbieters statt Video: verständlicher Fehler, keine Datei', () async {
    provider.htmlError = true;
    final e = engine();
    await e.enqueue(movie('3'), playlistId: 'a', title: 'Gesperrt');
    await _until(() => e.items.single.status == DownloadStatus.failed);
    expect(e.items.single.error, contains('Fehlerseite'));
    expect(await (await e.fileOf(e.items.single)).exists(), isFalse);
  });

  test('nacheinander statt gleichzeitig (eine Verbindung)', () async {
    provider.throttle = true;
    final e = engine();
    await e.enqueue(movie('4'), playlistId: 'a', title: 'Eins');
    await e.enqueue(movie('5'), playlistId: 'a', title: 'Zwei');
    await _until(() => e.items.first.isActive);
    expect(e.items.last.status, DownloadStatus.queued);
    provider.throttle = false;
    await _until(() => e.items.every((i) => i.isDone));
  });

  test('Löschen entfernt Eintrag und Datei', () async {
    final e = engine();
    await e.enqueue(movie('6'), playlistId: 'a', title: 'Weg');
    await _until(() => e.items.single.isDone);
    final file = await e.fileOf(e.items.single);
    await e.remove(e.items.single.id);
    expect(e.items, isEmpty);
    expect(await file.exists(), isFalse);
  });

  test('nach Neustart: unterbrochene Downloads laden weiter', () async {
    final first = engine();
    provider.throttle = true;
    await first.enqueue(movie('7'), playlistId: 'a', title: 'Neustart');
    await _until(() => first.items.single.received > 32 * 1024);
    // App „hart“ beendet: Verzeichnis sagt noch „downloading“.
    final raw = (jsonDecode(store.value!) as List).cast<Map<String, dynamic>>();
    expect(raw.single['status'], 'downloading');
    await first.pause(first.items.single.id);
    await _until(() => first.items.single.status == DownloadStatus.paused);
    store.value = jsonEncode([
      {...first.items.single.toJson(), 'status': 'downloading'},
    ]);

    provider.throttle = false;
    final second = engine();
    await second.load();
    await _until(() => second.items.single.isDone);
    expect(await (await second.fileOf(second.items.single)).readAsBytes(), body);
  });

  test('HLS-Listen und Live-Sender sind nicht herunterladbar', () {
    expect(isDownloadable(movie('8', url: 'https://x.test/movie/a.m3u8')), isFalse);
    expect(
      isDownloadable(const Channel(id: 'l', name: 'ARD', streamUrl: 'https://x.test/l.ts', type: ContentType.live)),
      isFalse,
    );
    expect(isDownloadable(movie('9', url: 'https://x.test/movie/u/p/9.mp4?token=1')), isTrue);
    expect(downloadExtension('https://x.test/movie/u/p/9.avi?x=1'), 'avi');
    expect(downloadExtension('https://x.test/play/9'), 'mp4');
    expect(safeFileName('a/b:c*?', 'id', 'mp4'), startsWith('a b c'));
  });

  test('Aufnahme: leere wird verworfen, gefüllte bleibt mit Dauer', () async {
    var now = DateTime(2026, 11, 6, 20, 15);
    final e = DownloadEngine(dio: Dio(), directory: () async => dir, store: store, onChange: (_) {}, clock: () => now);
    const live = Channel(id: 'ard', name: 'Das Erste HD', streamUrl: 'https://x.test/ard.m3u8', type: ContentType.live);
    final (emptyId, _) = await e.beginRecording(live, playlistId: 'a');
    await e.finishRecording(emptyId);
    expect(e.byId(emptyId), isNull);

    final (id, path) = await e.beginRecording(live, playlistId: 'a');
    expect(path, endsWith('.mkv'));
    await File(path).writeAsBytes(List.filled(2048, 1));
    now = now.add(const Duration(minutes: 42));
    await e.finishRecording(id);
    final item = e.byId(id)!;
    expect(item.isDone, isTrue);
    expect(item.recordedFor, const Duration(minutes: 42));
    expect(item.received, 2048);
    expect(item.subtitle, contains('20:15'));
  });

  group('mehrere Verbindungen', () {
    DownloadEngine parallel(int budget) => DownloadEngine(
      dio: Dio(),
      directory: () async => dir,
      store: store,
      onChange: (_) {},
      connectionBudget: () async => budget,
      minSegmentedSize: 64 * 1024,
    );

    test('lädt in 3 Teilen gleichzeitig und setzt die Datei richtig zusammen', () async {
      provider.throttle = true;
      final e = parallel(3);
      await e.enqueue(movie('p1'), playlistId: 'a', title: 'Parallel');
      await _until(() => e.items.single.isDone, timeout: const Duration(seconds: 20));
      expect(e.items.single.segments, 3);
      expect(provider.maxOpen, 3);
      expect(await (await e.fileOf(e.items.single)).readAsBytes(), body);
      // Keine Teildateien bleiben liegen.
      expect(dir.listSync().map((f) => f.path.split('/').last), [e.items.single.fileName]);
    });

    test('Budget 1 oder kleine Datei: wie bisher eine Verbindung', () async {
      final e = parallel(1);
      await e.enqueue(movie('p2'), playlistId: 'a', title: 'Einzeln');
      await _until(() => e.items.single.isDone);
      expect(e.items.single.segments, isNull);
      expect(provider.maxOpen, 1);
    });

    test('Anbieter lehnt weitere Verbindungen ab: Teile werden nacheinander geladen', () async {
      provider.connectionLimit = 1;
      final e = parallel(4);
      await e.enqueue(movie('p3'), playlistId: 'a', title: 'Limit');
      await _until(
        () => e.items.single.isDone || e.items.single.status == DownloadStatus.failed,
        timeout: const Duration(seconds: 20),
      );
      expect(e.items.single.status, DownloadStatus.done, reason: e.items.single.error);
      expect(await (await e.fileOf(e.items.single)).readAsBytes(), body);
    });

    test('Pause und Weiterladen: jedes Teil macht an seiner Stelle weiter', () async {
      provider.throttle = true;
      provider.throttleMs = 120; // langsamer als die Fortschrittsmeldung (alle 0,4 s)
      final e = parallel(3);
      await e.enqueue(movie('p4'), playlistId: 'a', title: 'Pause');
      await _until(() => e.items.single.received > 96 * 1024);
      await e.pause(e.items.single.id);
      await _until(() => e.items.single.status == DownloadStatus.paused);
      final before = provider.ranges.length;
      provider.throttle = false;
      await e.resume(e.items.single.id);
      await _until(() => e.items.single.isDone, timeout: const Duration(seconds: 20));
      final resumed = provider.ranges.skip(before).toList();
      // Fortsetzen ab der jeweiligen Stelle, nicht ab Teilanfang.
      expect(resumed.where((r) => r != null && !r.startsWith('bytes=0-')), isNotEmpty);
      expect(await (await e.fileOf(e.items.single)).readAsBytes(), body);
    });
  });
}
