import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import '../models/catalog.dart';
import '../models/category.dart';
import '../models/channel.dart';
import '../models/content_type.dart';

/// Ergebnis einer M3U-Analyse, nach Inhaltsart getrennt.
class M3uPlaylist {
  const M3uPlaylist(this.catalogs);

  final Map<ContentType, Catalog> catalogs;

  Catalog operator [](ContentType type) => catalogs[type] ?? Catalog.empty;
}

class M3uParser {
  /// Dekodiert und parst die Rohdaten in einem eigenen Isolate, damit auch
  /// 50-MB-Listen die Oberfläche nicht blockieren. `Isolate.run` gibt das
  /// Ergebnis per `Isolate.exit` zurück, also ohne teure Kopie.
  static Future<M3uPlaylist> parseInBackground(Uint8List bytes) {
    return Isolate.run(() => parse(utf8.decode(bytes, allowMalformed: true)));
  }

  static final _attributePattern = RegExp(r'([\w-]+)="([^"]*)"');

  static M3uPlaylist parse(String content) {
    final channels = <ContentType, List<Channel>>{for (final t in ContentType.values) t: []};
    final categories = <ContentType, Map<String, Category>>{for (final t in ContentType.values) t: {}};

    Map<String, String>? attributes;
    String? title;
    String? extGroup;

    for (final rawLine in const LineSplitter().convert(content)) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF')) {
        attributes = {
          for (final m in _attributePattern.allMatches(line)) m.group(1)!.toLowerCase(): m.group(2)!.trim(),
        };
        title = _titleOf(line);
        extGroup = null;
      } else if (line.startsWith('#EXTGRP:')) {
        extGroup = line.substring(8).trim();
      } else if (line.startsWith('#')) {
        continue;
      } else if (attributes != null) {
        final url = line;
        final type = _guessType(url, attributes);
        final groupName = attributes['group-title']?.isNotEmpty == true
            ? attributes['group-title']!
            : (extGroup?.isNotEmpty == true ? extGroup! : 'Ohne Kategorie');
        final category = categories[type]!.putIfAbsent(
          groupName,
          () => Category(id: groupName, name: groupName, type: type),
        );
        final name = (title?.isNotEmpty == true ? title : attributes['tvg-name']) ?? url;
        final logo = attributes['tvg-logo'];

        channels[type]!.add(Channel(
          // Gleiche URLs kommen in manchen Listen mehrfach vor; der Index hält die ID eindeutig.
          id: '${channels[type]!.length}|$url',
          name: name,
          streamUrl: url,
          type: type,
          logo: logo?.isNotEmpty == true ? logo : null,
          categoryId: category.id,
          epgChannelId: attributes['tvg-id'],
        ));
        attributes = null;
        title = null;
      }
    }

    return M3uPlaylist({
      for (final type in ContentType.values)
        type: Catalog(categories: categories[type]!.values.toList(), channels: channels[type]!),
    });
  }

  /// Der Anzeigename beginnt nach dem ersten Komma außerhalb von
  /// Anführungszeichen und darf selbst Kommas enthalten („ZDF, HD“).
  static String _titleOf(String line) {
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') inQuotes = !inQuotes;
      if (char == ',' && !inQuotes) return line.substring(i + 1).trim();
    }
    return '';
  }

  static final _vodExtension = RegExp(r'\.(mp4|mkv|avi|mov|m4v|wmv|flv)(\?|$)');

  /// Gruppennamen wie „Movies“ allein reichen nicht: Viele Listen führen dort
  /// 24/7-Live-Sender. Filme/Serien erkennen wir an der URL-Struktur, an
  /// Videodatei-Endungen oder an „VOD“ im Gruppennamen.
  static ContentType _guessType(String url, Map<String, String> attributes) {
    final lower = url.toLowerCase();
    if (lower.contains('/series/')) return ContentType.series;
    if (lower.contains('/movie/')) return ContentType.movie;
    final group = (attributes['group-title'] ?? '').toLowerCase();
    final isOnDemand = _vodExtension.hasMatch(lower) || RegExp(r'\bvod\b').hasMatch(group);
    if (!isOnDemand) return ContentType.live;
    return group.contains('serie') ? ContentType.series : ContentType.movie;
  }

}
