import 'channel.dart';

/// Qualitätsangaben, die aus Sendernamen als farbige Badges herausgelöst werden.
enum QualityTag {
  uhd('4K'),
  fhd('FHD'),
  hd('HD'),
  sd('SD'),
  hevc('HEVC'),
  fps50('50FPS'),
  raw('RAW');

  const QualityTag(this.label);

  final String label;
}

/// Aufbereiteter Sendername: sauberer Titel, Länder-Tag, Qualitäts-Badges.
class ChannelName {
  const ChannelName({
    required this.title,
    this.country,
    this.qualities = const [],
    this.notes = const [],
    this.isSeparator = false,
  });

  /// Anzeigename ohne Präfix und Qualitätsangaben.
  final String title;

  /// z. B. `DE`, `AL`, `UK` aus `DE | …`, `AL: …`, `UK - …`.
  final String? country;
  final List<QualityTag> qualities;

  /// Hinweise aus eckigen Klammern, z. B. „Geo-blocked“.
  final List<String> notes;

  /// Unechter Eintrag wie `AL: ----- SPORT -----`, dient nur als Überschrift.
  final bool isSeparator;

  static final _cache = Expando<ChannelName>('ChannelName');

  /// Zwischengespeichert pro [Channel], damit lange Listen flüssig scrollen.
  static ChannelName of(Channel channel) => _cache[channel] ??= parse(channel.name);

  static final _separatorPattern = RegExp(r'(-{3,}|={3,}|\*{3,}|#{3,}|_{3,}|~{3,}|•{3,})');
  static final _countryPattern = RegExp(
    r'^\s*(?:\[([A-Za-z]{2,3})\]|\|([A-Za-z]{2,3})\||([A-Z]{2,3}(?:-[A-Z]{2})?)\s*(?::|\||\s-\s))\s*',
  );
  static final _bracketNote = RegExp(r'\[([^\]]+)\]');
  static final _resolution = RegExp(
    r'\(?\b(2160|1440|1080|720|576|540|480|360|270|240)[pi]\b\)?',
    caseSensitive: false,
  );

  static const _qualityTokens = <String, QualityTag>{
    '4K': QualityTag.uhd,
    'UHD': QualityTag.uhd,
    '2160P': QualityTag.uhd,
    'FHD': QualityTag.fhd,
    'FULLHD': QualityTag.fhd,
    '1080P': QualityTag.fhd,
    '1080I': QualityTag.fhd,
    'HD': QualityTag.hd,
    '720P': QualityTag.hd,
    'SD': QualityTag.sd,
    '576P': QualityTag.sd,
    '480P': QualityTag.sd,
    'HEVC': QualityTag.hevc,
    'H265': QualityTag.hevc,
    'H.265': QualityTag.hevc,
    '50FPS': QualityTag.fps50,
    '60FPS': QualityTag.fps50,
    'RAW': QualityTag.raw,
  };

  static ChannelName parse(String raw) {
    var text = raw.trim();

    String? country;
    final countryMatch = _countryPattern.firstMatch(text);
    if (countryMatch != null) {
      country = (countryMatch.group(1) ?? countryMatch.group(2) ?? countryMatch.group(3))!.toUpperCase();
      text = text.substring(countryMatch.end);
    }

    if (_separatorPattern.hasMatch(text)) {
      final heading = text.replaceAll(_separatorPattern, ' ').replaceAll(RegExp(r'[|:]+'), ' ');
      return ChannelName(title: _squash(heading).toUpperCase(), country: country, isSeparator: true);
    }

    final notes = [for (final m in _bracketNote.allMatches(text)) m.group(1)!.trim()];
    text = text.replaceAll(_bracketNote, ' ');

    final qualities = <QualityTag>{};
    text = text.replaceAllMapped(_resolution, (m) {
      final tag = _qualityTokens['${m.group(1)}P'];
      if (tag != null) qualities.add(tag);
      return ' ';
    });

    final kept = <String>[];
    for (final word in text.split(RegExp(r'\s+'))) {
      final token = word.replaceAll(RegExp(r'^[(\[]+|[)\],]+$'), '').toUpperCase();
      final tag = _qualityTokens[token];
      // Nur am Wortende entfernen, damit „HD Plus“ oder „SD Sport“ als Name bleiben,
      // wenn das Wort am Anfang steht.
      if (tag != null && kept.isNotEmpty) {
        qualities.add(tag);
      } else if (word.isNotEmpty) {
        kept.add(word);
      }
    }

    var title = _squash(kept.join(' ')).replaceAll(RegExp(r'^[\s|:\-–]+|[\s|:\-–]+$'), '');
    if (title.isEmpty) title = raw.trim();

    final sorted = qualities.toList()..sort((a, b) => a.index.compareTo(b.index));
    // „FHD“ und „HD“ zusammen sind doppelt; die höhere Stufe genügt.
    if (sorted.contains(QualityTag.uhd)) sorted.removeWhere((q) => q == QualityTag.fhd || q == QualityTag.hd);
    if (sorted.contains(QualityTag.fhd)) sorted.remove(QualityTag.hd);

    return ChannelName(title: title, country: country, qualities: sorted, notes: notes);
  }

  static String _squash(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

extension ChannelNameX on Channel {
  ChannelName get display => ChannelName.of(this);

  bool get isSeparator => display.isSeparator;
}
