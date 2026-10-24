import 'dart:math' as math;

import '../models/channel.dart';
import '../models/channel_name.dart';
import '../models/content_type.dart';
import 'imdb_catalog.dart';
import 'personal_library.dart';

/// Canonical IDs are used only after a confident catalog match. Without one,
/// keep the playlist identity instead of guessing from a potentially ambiguous title.
List<String> recommendationKeys(Channel channel, ImdbCatalog? imdb) {
  final movie = imdb?.match(channel);
  return [if (movie != null) 'imdb:${movie.id}', personalItemKey(channel)];
}

/// Reconcile all current variants before deduplicating the catalog. A user
/// can rate a title before importing metadata; the later canonical ID must
/// inherit that choice even when a different quality variant appears first.
PersonalLibrary reconcileRecommendationHistory(PersonalLibrary library, Iterable<Channel> sources, ImdbCatalog? imdb) {
  if (imdb == null) return library;
  final feedback = Map<String, TitleFeedback>.of(library.feedback);
  final viewing = Map<String, VodViewing>.of(library.vodViewing);
  var changed = false;
  for (final channel in sources) {
    final keys = recommendationKeys(channel, imdb);
    if (keys.length < 2) continue;
    final identity = keys.first;
    final rating = library.feedbackFor(keys);
    if (rating != null && (feedback[identity] == null || rating.at > feedback[identity]!.at)) {
      feedback[identity] = rating;
      changed = true;
    }
    final watched = library.vodFor(keys);
    if (watched != null &&
        (viewing[identity] == null ||
            watched.lastWatched > viewing[identity]!.lastWatched ||
            watched.lastWatched == viewing[identity]!.lastWatched &&
                watched.milliseconds > viewing[identity]!.milliseconds)) {
      viewing[identity] = watched;
      changed = true;
    }
  }
  return changed ? library.copyWith(feedback: feedback, vodViewing: viewing) : library;
}

class Recommendations {
  const Recommendations(this.channels, {this.personalized = false, this.hasSignals = false});
  final List<Channel> channels;
  final bool personalized;
  final bool hasSignals;

  String get explanation => personalized
      ? 'Passend zu deinen Likes, deiner Liste und angesehenen Titeln.'
      : hasSignals
      ? 'Weitere Titel zum Entdecken. Mit mehr Filminformationen werden Vorschläge genauer.'
      : 'Zum Entdecken. Mit „Gefällt mir“ werden deine Vorschläge persönlicher.';
}

class _Features {
  _Features(this.channel, ImdbCatalog? imdb, PersonalLibrary library) {
    final movie = imdb?.match(channel);
    final saved = library.metadata[personalItemKey(channel)];
    key = movie == null ? personalItemKey(channel) : 'imdb:${movie.id}';
    genres = (channel.genres.isNotEmpty ? channel.genres : movie?.genres ?? saved?.genres ?? const <String>[])
        .map(canonicalGenre)
        .where((value) => value.isNotEmpty)
        .toSet();
    people = {
      for (final person in (channel.cast.isNotEmpty ? channel.cast : saved?.cast ?? const <String>[]).take(5))
        if (normalizeCatalogText(person).isNotEmpty) 'cast:${normalizeCatalogText(person)}',
      if ((channel.director ?? saved?.director)?.trim().isNotEmpty == true)
        'director:${normalizeCatalogText((channel.director ?? saved?.director)!)}',
    };
    quality = movie == null ? 0 : math.max(0.0, (movie.rating - 6) / 4);
  }
  final Channel channel;
  late final String key;
  late final Set<String> genres;
  late final Set<String> people;
  late final double quality;
}

/// Local content-based ranking. No inferred genre from title words, no user
/// data server, no invented match percentages. Available contains only titles
/// in the active playlist/language; sources may include other language variants.
Recommendations recommendTitles({
  required Iterable<Channel> available,
  required Iterable<Channel> sources,
  required PersonalLibrary library,
  Iterable<Channel> favorites = const [],
  ImdbCatalog? imdb,
  DateTime? now,
  int limit = 20,
}) {
  if (limit <= 0) return const Recommendations([]);
  final current = now ?? DateTime.now();
  library = reconcileRecommendationHistory(library, sources, imdb);
  final all = <String, _Features>{};
  for (final channel in sources) {
    if (channel.type == ContentType.live || channel.isSeparator || channel.seriesId != null) continue;
    final features = _Features(channel, imdb, library);
    all.putIfAbsent(features.key, () => features);
  }
  final favoriteKeys = {
    for (final channel in favorites.where((c) => c.type != ContentType.live)) ...recommendationKeys(channel, imdb),
  };
  final genreProfile = <String, double>{};
  final peopleProfile = <String, double>{};
  var hasSignals = false;
  for (final source in all.values) {
    final keys = [source.key, personalItemKey(source.channel)];
    final feedback = library.feedbackFor(keys)?.choice;
    if (feedback == FeedbackChoice.hide) continue;
    final viewed = library.vodFor(keys);
    var weight = feedback == FeedbackChoice.like ? 4.0 : 0.0;
    if (keys.any(favoriteKeys.contains)) weight += 2;
    if (viewed?.meaningful == true) {
      final age = math.max(0, current.millisecondsSinceEpoch - viewed!.lastWatched);
      weight += age < const Duration(days: 90).inMilliseconds ? 1.5 : 0.5;
    }
    if (weight <= 0) continue;
    hasSignals = true;
    for (final genre in source.genres) {
      genreProfile.update(
        genre,
        (v) => v + weight / source.genres.length,
        ifAbsent: () => weight / source.genres.length,
      );
    }
    for (final person in source.people) {
      peopleProfile.update(person, (v) => v + weight, ifAbsent: () => weight);
    }
  }
  final genreTotal = genreProfile.values.fold(0.0, (a, b) => a + b);
  final peopleTotal = peopleProfile.values.fold(0.0, (a, b) => a + b);
  final candidates = <({_Features features, double score, bool related})>[];
  final seen = <String>{};
  for (final channel in available) {
    if (channel.type == ContentType.live || channel.isSeparator || channel.seriesId != null) continue;
    final features = _Features(channel, imdb, library);
    if (!seen.add(features.key)) continue;
    final keys = [features.key, personalItemKey(channel)];
    final choice = library.feedbackFor(keys)?.choice;
    final viewed = library.vodFor(keys);
    if (choice == FeedbackChoice.hide ||
        choice == FeedbackChoice.like ||
        channel.type == ContentType.movie && viewed?.completed == true) {
      continue;
    }
    var affinity = 0.0;
    if (genreTotal > 0) {
      for (final genre in features.genres) {
        affinity += (genreProfile[genre] ?? 0) / genreTotal;
      }
      affinity /= math.sqrt(math.max(1, features.genres.length));
    }
    if (peopleTotal > 0) {
      for (final person in features.people) {
        affinity += (peopleProfile[person] ?? 0) / peopleTotal;
      }
    }
    final watchedPenalty = viewed?.meaningful == true ? 0.6 : 1.0;
    candidates.add((
      features: features,
      score: affinity * 10 * watchedPenalty + features.quality * 0.5,
      related: affinity > 0,
    ));
  }
  candidates.sort((a, b) {
    final order = b.score.compareTo(a.score);
    return order != 0 ? order : a.features.key.compareTo(b.features.key);
  });
  // Bound the diversity pass even for very large IPTV lists.
  final pool = candidates.take(math.max(limit * 8, 160)).toList();
  final selected = <Channel>[];
  final selectedGenres = <String, int>{};
  final selectedTypes = <ContentType, int>{};
  var personalized = false;
  while (selected.length < limit && pool.isNotEmpty) {
    var best = 0;
    var bestScore = double.negativeInfinity;
    for (var i = 0; i < pool.length; i++) {
      final row = pool[i];
      final repeated = row.features.genres.fold(0, (a, g) => math.max(a, selectedGenres[g] ?? 0));
      final value = row.score - repeated * 0.4 - (selectedTypes[row.features.channel.type] ?? 0) * 0.2;
      if (value > bestScore) {
        best = i;
        bestScore = value;
      }
    }
    final row = pool.removeAt(best);
    selected.add(row.features.channel);
    selectedTypes.update(row.features.channel.type, (v) => v + 1, ifAbsent: () => 1);
    personalized = personalized || row.related;
    for (final genre in row.features.genres) {
      selectedGenres.update(genre, (v) => v + 1, ifAbsent: () => 1);
    }
  }
  return Recommendations(selected, personalized: personalized, hasSignals: hasSignals);
}
