enum PlaylistKind { xtream, m3uUrl, m3uFile }

/// Eine gespeicherte Playlist: entweder Xtream-Codes-Zugang oder M3U-Quelle.
class PlaylistCredentials {
  const PlaylistCredentials({
    required this.id,
    required this.name,
    required this.kind,
    this.serverUrl,
    this.username,
    this.password,
    this.m3uUrl,
    this.localFilePath,
  });

  final String id;
  final String name;
  final PlaylistKind kind;

  // Xtream Codes
  final String? serverUrl;
  final String? username;
  final String? password;

  // M3U
  final String? m3uUrl;

  /// Kopie der importierten Datei im App-Support-Ordner (Sandbox-sicher).
  final String? localFilePath;

  bool get isXtream => kind == PlaylistKind.xtream;

  /// Server-URL ohne abschließenden Schrägstrich, mit Schema.
  String get normalizedServer {
    var url = (serverUrl ?? '').trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) url = 'http://$url';
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  String get subtitle => switch (kind) {
        PlaylistKind.xtream => '$username @ ${Uri.tryParse(normalizedServer)?.host ?? serverUrl}',
        PlaylistKind.m3uUrl => m3uUrl ?? '',
        PlaylistKind.m3uFile => 'Lokale Datei',
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'serverUrl': serverUrl,
        'username': username,
        'password': password,
        'm3uUrl': m3uUrl,
        'localFilePath': localFilePath,
      };

  factory PlaylistCredentials.fromJson(Map<String, dynamic> json) => PlaylistCredentials(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: PlaylistKind.values.byName(json['kind'] as String),
        serverUrl: json['serverUrl'] as String?,
        username: json['username'] as String?,
        password: json['password'] as String?,
        m3uUrl: json['m3uUrl'] as String?,
        localFilePath: json['localFilePath'] as String?,
      );
}
