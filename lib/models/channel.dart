import 'content_type.dart';

/// Ein abspielbarer Eintrag: Live-Sender, Film, Serie oder Serienfolge.
///
/// Bei Serien ist [streamUrl] leer, abgespielt werden erst die Folgen.
class Channel {
  const Channel({
    required this.id,
    required this.name,
    required this.streamUrl,
    required this.type,
    this.logo,
    this.categoryId,
    this.epgChannelId,
    this.xtreamStreamId,
  });

  /// Innerhalb einer Playlist eindeutig (Xtream-ID oder Stream-URL).
  final String id;
  final String name;
  final String streamUrl;
  final ContentType type;
  final String? logo;
  final String? categoryId;

  /// `tvg-id` aus M3U bzw. `epg_channel_id` aus Xtream.
  final String? epgChannelId;

  /// Nur bei Xtream gesetzt; nötig für die Kurz-EPG-Abfrage.
  final int? xtreamStreamId;

  bool get isPlayable => streamUrl.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'streamUrl': streamUrl,
    'type': type.name,
    'logo': logo,
    'categoryId': categoryId,
    'epgChannelId': epgChannelId,
    'xtreamStreamId': xtreamStreamId,
  };

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
    id: json['id'] as String,
    name: json['name'] as String,
    streamUrl: json['streamUrl'] as String,
    type: ContentType.fromName(json['type'] as String?),
    logo: json['logo'] as String?,
    categoryId: json['categoryId'] as String?,
    epgChannelId: json['epgChannelId'] as String?,
    xtreamStreamId: json['xtreamStreamId'] as int?,
  );

  @override
  bool operator ==(Object other) => other is Channel && other.id == id && other.type == type;

  @override
  int get hashCode => Object.hash(id, type);
}
