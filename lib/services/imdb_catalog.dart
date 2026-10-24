import 'dart:convert';

import '../models/channel.dart';
import '../models/channel_name.dart';
import '../models/content_type.dart';

class ImdbMovie {
  const ImdbMovie({
    required this.id,
    required this.title,
    required this.originalTitle,
    required this.year,
    required this.genres,
    required this.rating,
    required this.votes,
    this.aliases = const [],
  });
  final String id;
  final String title;
  final String originalTitle;
  final int year;
  final List<String> genres;
  final double rating;
  final int votes;
  final List<String> aliases;
}

/// Persönlicher, lokal importierter IMDb-Datensatz; keine Anbieterbewertung.
class ImdbCatalog {
  ImdbCatalog._(this.generatedAt, this.minVotes, this.movies) {
    for (final movie in movies) {
      _ids[movie.id] = movie;
      for (final title in {movie.title, movie.originalTitle, ...movie.aliases}.where((title) => title.isNotEmpty)) {
        final plain = catalogTitleKey(title);
        final plainMatches = _plainTitles.putIfAbsent(plain, () => []);
        if (!plainMatches.contains(movie)) plainMatches.add(movie);
        final key = '$plain:${movie.year}';
        final matches = _titles.putIfAbsent(key, () => []);
        if (!matches.contains(movie)) matches.add(movie);
      }
    }
  }

  static const source = 'https://data.imdb.com/non-commercial-datasets/';
  static const attribution = 'Information courtesy of IMDb (https://www.imdb.com). Used with permission.';
  final DateTime generatedAt;
  final int minVotes;
  final List<ImdbMovie> movies;
  final _ids = <String, ImdbMovie>{};
  final _titles = <String, List<ImdbMovie>>{};
  final _plainTitles = <String, List<ImdbMovie>>{};

  static ImdbCatalog parse(String text) {
    final data = jsonDecode(text);
    if (data is! Map ||
        data['schemaVersion'] != 1 ||
        data['movies'] is! List ||
        data['minVotes'] is! int ||
        (data['minVotes'] as int) <= 0 ||
        data['generatedAt'] is! String) {
      throw const FormatException('Keine gültige IMDb-Katalogdatei.');
    }
    final date = DateTime.tryParse(data['generatedAt'] as String);
    if (date == null) throw const FormatException('Der IMDb-Datenstand fehlt.');
    final minVotes = data['minVotes'] as int;
    final movies = <ImdbMovie>[];
    for (final row in data['movies'] as List) {
      if (row is! Map ||
          row['id'] is! String ||
          !RegExp(r'^tt\d{7,12}$').hasMatch(row['id'] as String) ||
          row['title'] is! String ||
          (row['title'] as String).isEmpty ||
          row['year'] is! int ||
          row['rating'] is! num ||
          row['votes'] is! int ||
          row['genres'] is! List) {
        continue;
      }
      final rating = (row['rating'] as num).toDouble();
      final votes = row['votes'] as int;
      if (!rating.isFinite || rating < 1 || rating > 10 || votes < minVotes) continue;
      movies.add(
        ImdbMovie(
          id: row['id'],
          title: row['title'],
          originalTitle: row['originalTitle'] is String ? row['originalTitle'] : '',
          year: row['year'],
          genres: (row['genres'] as List).whereType<String>().toList(),
          rating: rating,
          votes: votes,
          aliases: (row['aliases'] is List ? row['aliases'] as List : const []).whereType<String>().toList(),
        ),
      );
    }
    if (movies.isEmpty) throw const FormatException('Die Datei enthält keine passenden IMDb-Filme.');
    return ImdbCatalog._(date, minVotes, movies);
  }

  ImdbMovie? match(Channel channel) {
    if (channel.type != ContentType.movie) return null;
    final explicit = channel.imdbId;
    if (explicit != null && explicit.isNotEmpty) {
      final id = RegExp(r'(?:^|/)(tt\d{7,12})(?:/|$)').firstMatch(explicit)?.group(1);
      return id == null ? null : _ids[id];
    }
    final parsed = cleanCatalogTitle(channel.name);
    final year = channel.year ?? parsed.year;
    var candidates = year == null
        ? _plainTitles[catalogTitleKey(parsed.title)] ?? const <ImdbMovie>[]
        : _titles['${catalogTitleKey(parsed.title)}:$year'] ?? const <ImdbMovie>[];
    if (year == null && candidates.isEmpty) {
      final suffix = RegExp(r'^(.+)\s+((?:18|19|20)\d{2})$').firstMatch(parsed.title);
      if (suffix != null && int.parse(suffix.group(2)!) <= DateTime.now().year + 1) {
        candidates = _titles['${catalogTitleKey(suffix.group(1)!)}:${suffix.group(2)}'] ?? const <ImdbMovie>[];
      }
    }
    return candidates.length == 1 ? candidates.single : null;
  }

  List<(Channel, ImdbMovie)> ranked(Iterable<Channel> channels, {String? genre, int? limit}) {
    final seen = <String>{};
    final rows = <(Channel, ImdbMovie)>[];
    for (final channel in channels) {
      final movie = match(channel);
      if (movie == null ||
          seen.contains(movie.id) ||
          genre != null && genre.isNotEmpty && !movie.genres.map(canonicalGenre).contains(canonicalGenre(genre))) {
        continue;
      }
      seen.add(movie.id);
      rows.add((channel, movie));
    }
    rows.sort((a, b) {
      final rating = b.$2.rating.compareTo(a.$2.rating);
      if (rating != 0) return rating;
      final votes = b.$2.votes.compareTo(a.$2.votes);
      return votes != 0 ? votes : a.$2.id.compareTo(b.$2.id);
    });
    return limit == null ? rows : rows.take(limit).toList();
  }
}

final _metadataCountry = RegExp(
  r'^(de|deu|ger|at|ch|tr|tur|uk|gb|us|usa|en|eng|fr|fra|es|esp|it|ita|pt|por|nl|nld|al|alb|gr|grc|ru|rus|pl|pol|ar|ara|ro|rou|se|swe|no|nor|dk|dnk|fi|fin)$',
  caseSensitive: false,
);
final _metadataPrefix = RegExp(
  r'^\s*(?:\(\s*(?:[VS]\s*\|\s*)?([A-Za-z]{2,3})\s*-?\s*\)|\[([A-Za-z]{2,3})\]|\|([A-Za-z]{2,3})\||([A-Za-z]{2,3})\s*(?::|\|| - ))\s*',
);
final _metadataQuality = RegExp(
  r'(?:[\s._-]+|[([]\s*)(?:4k|uhd|fhd|fullhd|hd|sd|2160p|1440p|1080[pi]|720p|576p|480p|hevc|avc|h[.]?26[45]|x26[45]|hdr10[+]?|hdr|dolby[ .-]?vision|dv|aac|ac3|eac3|dts|web[ .-]?dl|webrip|bluray|brrip|dvdrip|50fps|60fps|multi[ -]?sub)[)\]]*\s*$',
  caseSensitive: false,
);

/// Conservative title cleanup shared by metadata lookup. Numbers that belong
/// to a title remain intact; a bare trailing year is interpreted only after
/// the catalog has ruled out an exact full-title match.
({String title, int? year}) cleanCatalogTitle(String raw) {
  var title = raw.trim();
  for (var i = 0; i < 3; i++) {
    final prefix = _metadataPrefix.firstMatch(title);
    if (prefix != null &&
        _metadataCountry.hasMatch(prefix.group(1) ?? prefix.group(2) ?? prefix.group(3) ?? prefix.group(4)!)) {
      title = title.substring(prefix.end);
      continue;
    }
    final quality = RegExp(
      r'^(?:[([](?:4k|uhd|fhd|hd|sd|2160p|1080p|720p|hevc)[)\]]|(?:4k|uhd|fhd|hd|sd|2160p|1080p|720p|hevc)\s*\|)\s*',
      caseSensitive: false,
    ).firstMatch(title);
    if (quality == null || quality.end == title.length) break;
    title = title.substring(quality.end);
  }
  String prior;
  do {
    prior = title;
    title = title.replaceFirst(_metadataQuality, '').trim();
  } while (title.isNotEmpty && title != prior);
  int? year;
  final match = RegExp(r'\s*(?:[-–]\s*((?:18|19|20)\d{2})|[([]\s*((?:18|19|20)\d{2})\s*[)\]])\s*$').firstMatch(title);
  if (match != null && match.start > 0) {
    year = int.parse(match.group(1) ?? match.group(2)!);
    title = title.substring(0, match.start);
  }
  title = title.replaceAll(RegExp(r'[\s|:–-]+$'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  return (title: title.isEmpty ? raw.trim() : title, year: year);
}

String normalizeCatalogText(String text) {
  var result = text.toLowerCase();
  const from = 'äáàâãåöóòôõüúùûéèêëíìîïçñğşı';
  const to = 'aaaaaaooooouuuueeeeiiiicngsi';
  for (var i = 0; i < from.length; i++) {
    result = result.replaceAll(from[i], to[i]);
  }
  return result
      .replaceAll('ß', 'ss')
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'''[.,:;!?"'‘’“”()\[\]{}|/\\_–—-]'''), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Match common sequel-number spellings without changing displayed titles.
/// Single letters and standalone Roman titles are not rewritten.
String catalogTitleKey(String title) {
  const roman = {'ii': '2', 'iii': '3', 'iv': '4', 'vi': '6', 'vii': '7', 'viii': '8', 'ix': '9'};
  return normalizeCatalogText(title)
      .replaceFirstMapped(RegExp(r'\s+(ii|iii|iv|vi|vii|viii|ix)$'), (match) => ' ${roman[match.group(1)]}');
}

String canonicalGenre(String value) {
  final key = normalizeCatalogText(value);
  return const {
        'krimi': 'crime',
        'krimis': 'crime',
        'komodie': 'comedy',
        'komodien': 'comedy',
        'abenteuer': 'adventure',
        'science fiction': 'sci fi',
        'scifi': 'sci fi',
        'familie': 'family',
        'romantik': 'romance',
        'liebesfilm': 'romance',
        'dokumentation': 'documentary',
        'dokumentarfilm': 'documentary',
        'krieg': 'war',
        'geschichte': 'history',
      }[key] ??
      key;
}

bool _near(String a, String b) {
  if (a == b) return true;
  if (a.length < 4 || b.length < 4 || (a.length - b.length).abs() > 1) return false;
  if (a.length == b.length) {
    final wrong = [
      for (var i = 0; i < a.length; i++)
        if (a[i] != b[i]) i,
    ];
    return wrong.length == 1 ||
        wrong.length == 2 && wrong[1] == wrong[0] + 1 && a[wrong[0]] == b[wrong[1]] && a[wrong[1]] == b[wrong[0]];
  }
  final short = a.length < b.length ? a : b;
  final long = a.length < b.length ? b : a;
  var skip = 0;
  for (var i = 0; i < short.length; i++) {
    if (short[i] != long[i + skip]) {
      if (skip != 0) return false;
      skip++;
      if (short[i] != long[i + skip]) return false;
    }
  }
  return true;
}

/// Gleiche Suchphrasen wie im Web-Katalog; der Bezugstitel behält seine Schreibweise.
String? parseSimilarQuery(String rawQuery) {
  final query = rawQuery.replaceAll(RegExp(r'\s+'), ' ').trim();
  return RegExp(
    r'^(?:(?:filme?|serien?)\s+)?(?:(?:ähnlich|aehnlich|ahnlich)e?(?:\s+(?:filme?|serien?))?\s+(?:wie|zu)|wie|zu)\s+(.+)$',
    caseSensitive: false,
  ).firstMatch(query)?.group(1);
}

/// Lokale, deterministische Suche; nur tatsächlich vorhandene Playlist-Inhalte.
List<Channel> searchCatalog(Iterable<Channel> channels, String rawQuery, {ImdbCatalog? imdb, Channel? similarTo}) {
  final all = channels.toList();
  final query = normalizeCatalogText(rawQuery);
  if (query.isEmpty && similarTo == null) return all;
  List<String> genres(Channel channel) =>
      (channel.genres.isNotEmpty ? channel.genres : imdb?.match(channel)?.genres ?? const <String>[])
          .map(canonicalGenre)
          .toList();
  int score(Channel channel, String query) {
    final title = normalizeCatalogText(channel.display.title);
    if (title == query) return 1000;
    if (title.startsWith(query)) return 850;
    if (title.contains(query)) return 700;
    final genre = genres(channel);
    if (genre.contains(canonicalGenre(query))) return 600;
    final metadata = normalizeCatalogText(
      '${channel.cast.join(' ')} ${channel.director ?? ''} ${genre.join(' ')} ${channel.year ?? channel.display.year ?? ''}',
    );
    if (metadata.contains(query)) return 500;
    final titleWords = title.split(' ');
    final words = [...titleWords, ...metadata.split(' ')];
    var result = 0;
    final parts = query.split(' ');
    for (final part in parts) {
      if (titleWords.contains(part)) {
        result += 80;
      } else if (words.contains(canonicalGenre(part)) || genre.contains(canonicalGenre(part))) {
        result += 40;
      } else if (part.length >= 3 && words.any((word) => word.startsWith(part))) {
        result += 30;
      } else if (titleWords.any((word) => _near(word, part))) {
        result += 20;
      } else {
        return 0;
      }
    }
    return 200 + result ~/ parts.length;
  }

  final similar = parseSimilarQuery(rawQuery);
  var seed = similarTo;
  if (seed == null && similar != null) {
    final candidates = [for (final channel in all) (channel, score(channel, normalizeCatalogText(similar)))]
      ..sort((a, b) => b.$2.compareTo(a.$2));
    if (candidates.isEmpty || candidates.first.$2 < 700) return [];
    if (candidates.length > 1 &&
        candidates[0].$2 == candidates[1].$2 &&
        candidates[0].$1.display.title != candidates[1].$1.display.title) {
      return [];
    }
    seed = candidates.first.$1;
  }
  final seedGenres = seed == null ? const <String>[] : genres(seed);
  final seedCast = seed?.cast.map(normalizeCatalogText).toSet() ?? {};
  int related(Channel channel) {
    if (seed == null || channel == seed || channel.type != seed.type || channel.display.title == seed.display.title) {
      return 0;
    }
    final otherGenres = genres(channel);
    var result = otherGenres.where(seedGenres.contains).length * 30;
    if (channel.director != null &&
        seed.director != null &&
        normalizeCatalogText(channel.director!) == normalizeCatalogText(seed.director!)) {
      result += 60;
    }
    result += channel.cast.map(normalizeCatalogText).where(seedCast.contains).length * 20;
    if (seedGenres.isEmpty &&
        otherGenres.isEmpty &&
        channel.categoryId != null &&
        channel.categoryId == seed.categoryId) {
      result += 10;
    }
    return result;
  }

  final scored = [
    for (var i = 0; i < all.length; i++) (all[i], seed == null ? score(all[i], query) : related(all[i]), i),
  ]..sort((a, b) => a.$2 == b.$2 ? a.$3.compareTo(b.$3) : b.$2.compareTo(a.$2));
  return scored.where((row) => row.$2 > 0).map((row) => row.$1).toList();
}
