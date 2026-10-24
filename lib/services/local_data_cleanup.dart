import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Löscht ausschließlich app-eigene Dateien. Der allgemeine Temp-Ordner
/// gehört auf Desktop-Systemen auch anderen Programmen und bleibt unberührt.
Future<void> clearAppFiles({
  Future<Directory> Function() supportDirectory = getApplicationSupportDirectory,
  Future<Directory> Function() cacheDirectory = getApplicationCacheDirectory,
}) async {
  final directories = await Future.wait([supportDirectory(), cacheDirectory()]);
  for (final directory in directories) {
    if (!await directory.exists()) continue;
    await for (final entry in directory.list(followLinks: false)) {
      try {
        await entry.delete(recursive: true);
      } on FileSystemException {
        // Vom System gesperrte Einträge überspringen.
      }
    }
  }
}
