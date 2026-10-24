import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'imdb_catalog.dart';

class ImdbCatalogStore {
  const ImdbCatalogStore({this.directory = getApplicationSupportDirectory});
  final Future<Directory> Function() directory;
  static const maxBytes = 16 * 1024 * 1024;

  Future<File> _file() async => File('${(await directory()).path}/imdb-catalog.json');

  Future<ImdbCatalog?> load() async {
    if (kIsWeb) return null;
    final file = await _file();
    if (!await file.exists()) return null;
    return compute(ImdbCatalog.parse, await _read(file));
  }

  Future<String> _read(File file) async {
    if (await file.length() > maxBytes) throw const FormatException('Die IMDb-Datei darf höchstens 16 MB groß sein.');
    return file.readAsString();
  }

  Future<ImdbCatalog> importFile(String path) async {
    final text = await _read(File(path));
    final catalog = await compute(ImdbCatalog.parse, text);
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    try {
      await temporary.writeAsString(text, flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    return catalog;
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}
