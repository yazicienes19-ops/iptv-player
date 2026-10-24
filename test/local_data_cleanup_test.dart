import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/services/local_data_cleanup.dart';

void main() {
  test('Daten löschen erhält fremde temporäre Dateien und Symlink-Ziele', () async {
    final root = await Directory.systemTemp.createTemp('ipflix-cleanup-test-');
    addTearDown(() => root.delete(recursive: true));
    final support = await Directory('${root.path}/support').create();
    final cache = await Directory('${root.path}/cache').create();
    final foreign = await Directory('${root.path}/other-app').create();
    final foreignFile = await File('${foreign.path}/important.txt').writeAsString('behalten');
    await File('${support.path}/playlist.m3u').writeAsString('Zugangsdaten');
    await Directory('${cache.path}/images').create();
    await File('${cache.path}/images/poster').writeAsString('Bild');
    if (!Platform.isWindows) await Link('${support.path}/external').create(foreign.path);

    await clearAppFiles(supportDirectory: () async => support, cacheDirectory: () async => cache);

    expect(await support.list().toList(), isEmpty);
    expect(await cache.list().toList(), isEmpty);
    expect(await foreignFile.readAsString(), 'behalten');
  });
}
