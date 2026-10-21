import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../models/playlist_credentials.dart';
import 'm3u_parser.dart';

/// Lädt M3U-Quellen (URL oder importierte Datei) und parst sie im Hintergrund.
class PlaylistLoader {
  PlaylistLoader({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(minutes: 3),
              headers: {'User-Agent': 'IPTVPlayer/1.0 (libmpv)'},
            ));

  final Dio _dio;

  Future<M3uPlaylist> loadM3u(PlaylistCredentials playlist) async {
    final Uint8List bytes;
    if (playlist.kind == PlaylistKind.m3uFile) {
      bytes = await File(playlist.localFilePath!).readAsBytes();
    } else {
      try {
        final response = await _dio.get<List<int>>(
          playlist.m3uUrl!,
          options: Options(responseType: ResponseType.bytes),
        );
        bytes = Uint8List.fromList(response.data ?? const []);
      } on DioException catch (e) {
        throw Exception('M3U konnte nicht geladen werden: ${e.message ?? e.error}');
      }
    }
    final result = await M3uParser.parseInBackground(bytes);
    if (result.catalogs.values.every((c) => c.channels.isEmpty)) {
      throw Exception('Die Playlist enthält keine Einträge. Ist es wirklich eine M3U-Datei?');
    }
    return result;
  }

  /// Kopiert eine vom Nutzer gewählte Datei in den App-Ordner. Unter macOS
  /// gilt die Sandbox-Freigabe sonst nur bis zum nächsten Neustart.
  static Future<String> importFile(String sourcePath, String playlistId) async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/playlists');
    await dir.create(recursive: true);
    final target = '${dir.path}/$playlistId.m3u';
    await File(sourcePath).copy(target);
    return target;
  }

  static Future<void> deleteImportedFile(PlaylistCredentials playlist) async {
    final path = playlist.localFilePath;
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
