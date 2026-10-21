import 'category.dart';
import 'channel.dart';

/// Kategorien und Einträge einer Inhaltsart (z. B. alle Live-Sender).
class Catalog {
  const Catalog({required this.categories, required this.channels});

  static const empty = Catalog(categories: [], channels: []);

  final List<Category> categories;
  final List<Channel> channels;
}

/// Eine Serienfolge; [channel] ist der abspielbare Stream.
class Episode {
  const Episode({required this.channel, required this.number, this.plot, this.duration});

  final Channel channel;
  final int number;
  final String? plot;
  final String? duration;
}

class Season {
  const Season({required this.number, required this.episodes});

  final int number;
  final List<Episode> episodes;

  List<Channel> get channels => [for (final e in episodes) e.channel];
}

/// Zusatzinfos für die Detailseite (nur Xtream liefert sie).
class MediaDetails {
  const MediaDetails({
    this.plot,
    this.genre,
    this.year,
    this.rating,
    this.duration,
    this.backdrop,
    this.cast,
    this.seasons = const [],
  });

  static const empty = MediaDetails();

  final String? plot;
  final String? genre;
  final String? year;
  final double? rating;
  final String? duration;
  final String? backdrop;
  final String? cast;
  final List<Season> seasons;

  /// Kurze Metazeile wie „2024 · Drama · 1 Std. 52 Min.“
  List<String> get metaParts => [?year, ?genre, ?duration];
}
