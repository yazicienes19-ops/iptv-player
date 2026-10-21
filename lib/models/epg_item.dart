import 'dart:convert';

class EpgItem {
  const EpgItem({required this.title, required this.start, required this.end, this.description});

  final String title;
  final String? description;
  final DateTime start;
  final DateTime end;

  bool isLiveAt(DateTime now) => !now.isBefore(start) && now.isBefore(end);

  /// 0.0 bis 1.0, wie weit die Sendung fortgeschritten ist.
  double progressAt(DateTime now) {
    final total = end.difference(start).inSeconds;
    if (total <= 0) return 0;
    return (now.difference(start).inSeconds / total).clamp(0.0, 1.0);
  }

  /// Xtream liefert Titel und Beschreibung Base64-kodiert und Zeiten als Unix-Sekunden.
  factory EpgItem.fromXtream(Map<String, dynamic> json) {
    return EpgItem(
      title: _decodeBase64(json['title']) ?? 'Unbekannte Sendung',
      description: _decodeBase64(json['description']),
      start: _parseTime(json['start_timestamp'], json['start']),
      end: _parseTime(json['stop_timestamp'], json['end'] ?? json['stop']),
    );
  }

  static String? _decodeBase64(Object? value) {
    if (value is! String || value.isEmpty) return null;
    try {
      return utf8.decode(base64.decode(base64.normalize(value)), allowMalformed: true).trim();
    } on FormatException {
      return value;
    }
  }

  static DateTime _parseTime(Object? timestamp, Object? fallback) {
    final seconds = int.tryParse('$timestamp');
    if (seconds != null) {
      return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    }
    return DateTime.tryParse('$fallback')?.toLocal() ?? DateTime.now();
  }
}
