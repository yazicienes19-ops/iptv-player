import '../models/catalog.dart';
import '../models/channel.dart';
import '../models/channel_name.dart';
import '../models/content_type.dart';

/// Ergebnis der Zusammenfassung: eine Karte pro Serie, Folgen nach Staffeln.
class AggregatedSeries {
  const AggregatedSeries(this.series, this.seasons);

  /// Nicht abspielbare Serien-Einträge (streamUrl leer), einer pro Serie.
  final List<Channel> series;

  /// Serien-ID → Staffeln mit Folgen.
  final Map<String, List<Season>> seasons;
}

/// Fasst M3U-Einträge wie `(DE-) 4 Blocks S01 E01` zu einer Serie zusammen.
///
/// M3U-Listen führen jede Folge als eigenen Eintrag; ohne Gruppierung zeigt
/// der Serien-Tab zehntausende Karten.
class SeriesAggregator {
  static final _patterns = [
    // S01 E01, S01E01, s1.e2, S01 - E01
    RegExp(r'\b[Ss]\s?(\d{1,2})\s*[-._]?\s*[Ee][Pp]?\s?(\d{1,4})\b'),
    // Staffel 1 Folge 2 / Season 1 Episode 2
    RegExp(
      r'\b(?:Staffel|Season|Sezon|Sezona)\s*(\d{1,2})\s*[-,.:]?\s*(?:Folge|Episode|Ep\.?|Bölüm|Epizoda)\s*(\d{1,4})\b',
      caseSensitive: false,
    ),
    // 1x02
    RegExp(r'\b(\d{1,2})x(\d{2,3})\b'),
  ];

  /// Nur „Staffel 2“ ohne Folgennummer, z. B. bei kompletten Staffel-Paketen.
  static final _seasonOnly = RegExp(r'\b(?:Staffel|Season|S)\s*(\d{1,2})\b\s*$', caseSensitive: false);

  static ({String show, int season, int episode, String rest})? match(String title) {
    for (final pattern in _patterns) {
      final m = pattern.firstMatch(title);
      if (m == null) continue;
      final show = title.substring(0, m.start).replaceAll(RegExp(r'[\s\-–|:._(]+$'), '').trim();
      if (show.isEmpty) continue;
      final rest = title.substring(m.end).replaceAll(RegExp(r'^[\s\-–|:._)]+'), '').trim();
      return (show: show, season: int.parse(m.group(1)!), episode: int.parse(m.group(2)!), rest: rest);
    }
    final seasonOnly = _seasonOnly.firstMatch(title);
    if (seasonOnly != null && seasonOnly.start > 0) {
      final show = title.substring(0, seasonOnly.start).replaceAll(RegExp(r'[\s\-–|:._(]+$'), '').trim();
      if (show.isNotEmpty) return (show: show, season: int.parse(seasonOnly.group(1)!), episode: 0, rest: '');
    }
    return null;
  }

  /// [entries] sind die Serien-Einträge einer Playlist in Listenreihenfolge.
  static AggregatedSeries aggregate(List<Channel> entries) {
    final order = <String>[];
    final firstEntry = <String, Channel>{};
    final showTitle = <String, String>{};
    final bySeason = <String, Map<int, List<Episode>>>{};
    final singles = <Channel>[];

    for (final entry in entries) {
      final name = ChannelName.parse(entry.name);
      final m = match(name.title);
      if (m == null || !entry.isPlayable) {
        singles.add(entry);
        continue;
      }
      // Schlüssel aus Sprache + normalisiertem Titel: „4 Blocks“ DE und EN bleiben getrennt.
      final normalized = m.show.toLowerCase().replaceAll(RegExp(r'[^a-z0-9äöüßçğışéèàáíóúñ]+'), '');
      final key = '${name.country ?? ''}|$normalized';
      if (!firstEntry.containsKey(key)) {
        order.add(key);
        firstEntry[key] = entry;
        showTitle[key] = '${name.country != null ? '(${name.country}) ' : ''}${m.show}';
      }
      final episodes = bySeason.putIfAbsent(key, () => {}).putIfAbsent(m.season, () => []);
      final number = m.episode > 0 ? m.episode : episodes.length + 1;
      episodes.add(
        Episode(
          number: number,
          channel: Channel(
            id: entry.id,
            name: m.rest.isNotEmpty ? m.rest : 'Folge $number',
            streamUrl: entry.streamUrl,
            type: ContentType.series,
            logo: entry.logo,
            categoryId: entry.categoryId,
          ),
        ),
      );
    }

    final series = <Channel>[];
    final seasons = <String, List<Season>>{};
    for (final key in order) {
      final first = firstEntry[key]!;
      final id = 'series:$key';
      series.add(
        Channel(
          id: id,
          // Mit Länder-Präfix, damit der Titel-Cleaner die Sprache wieder erkennt.
          name: showTitle[key]!,
          streamUrl: '',
          type: ContentType.series,
          logo: first.logo,
          categoryId: first.categoryId,
        ),
      );
      seasons[id] = [
        for (final entry in (bySeason[key]!.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
          Season(number: entry.key, episodes: entry.value..sort((a, b) => a.number.compareTo(b.number))),
      ];
    }
    // Einträge ohne Folgen-Muster (z. B. Mini-Serien als ein Stream) bleiben einzeln abspielbar.
    return AggregatedSeries([...series, ...singles], seasons);
  }
}
