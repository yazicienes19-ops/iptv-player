import 'dart:math' as math;

import '../models/catalog.dart';
import '../models/channel.dart';
import '../models/content_type.dart';

/// M3U display IDs contain a row number; a playlist reorder must not create
/// new films or move a channel's viewing history to another channel.
String personalItemKey(Channel channel) =>
    '${channel.type.name}:${channel.xtreamStreamId != null
        ? channel.id
        : channel.streamUrl.isNotEmpty
        ? channel.streamUrl
        : channel.id}';

/// Provider upload time, never the film's release year. Accept common Xtream
/// epoch seconds/milliseconds and ISO dates, but reject invalid/future values.
DateTime? parseAddedAt(Object? raw, {DateTime? now}) {
  if (raw == null) return null;
  final text = '$raw'.trim();
  final numeric = num.tryParse(text);
  DateTime? value;
  if (numeric != null) {
    if (!numeric.isFinite || numeric <= 0) return null;
    final millis = numeric < 100000000000 ? numeric * 1000 : numeric;
    if (millis > 8640000000000000) return null;
    value = DateTime.fromMillisecondsSinceEpoch(millis.round(), isUtc: true);
  } else if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(text)) {
    final parts = text.substring(0, 10).split('-').map(int.parse).toList();
    final calendar = DateTime.utc(parts[0], parts[1], parts[2]);
    if (calendar.year != parts[0] || calendar.month != parts[1] || calendar.day != parts[2]) return null;
    value = DateTime.tryParse(text)?.toUtc();
  }
  final current = (now ?? DateTime.now()).toUtc();
  if (value == null || value.isBefore(DateTime.utc(2000)) || value.isAfter(current)) return null;
  return value;
}

class ChannelViewing {
  const ChannelViewing({required this.milliseconds, required this.lastWatched});
  final int milliseconds;
  final int lastWatched;

  Map<String, int> toJson() => {'milliseconds': milliseconds, 'lastWatched': lastWatched};
}

enum FeedbackChoice { like, hide, none }

class TitleFeedback {
  const TitleFeedback(this.choice, this.at);
  final FeedbackChoice choice;
  final int at;
  Map<String, dynamic> toJson() => {'choice': choice.name, 'at': at};
}

class TitleMetadata {
  const TitleMetadata({this.genres = const [], this.cast = const [], this.director});
  final List<String> genres;
  final List<String> cast;
  final String? director;
  bool get isEmpty => genres.isEmpty && cast.isEmpty && director == null;
  factory TitleMetadata.fromJson(Map data) => TitleMetadata(
    genres: (data['genres'] is List ? data['genres'] as List : const []).whereType<String>().take(12).toList(),
    cast: (data['cast'] is List ? data['cast'] as List : const []).whereType<String>().take(10).toList(),
    director: data['director'] is String ? data['director'] as String : null,
  );
  Map<String, dynamic> toJson() => {'genres': genres, 'cast': cast, 'director': director};
}

class VodViewing {
  const VodViewing({
    required this.milliseconds,
    required this.lastWatched,
    this.meaningful = false,
    this.completed = false,
  });
  final int milliseconds;
  final int lastWatched;
  final bool meaningful;
  final bool completed;
  Map<String, dynamic> toJson() => {
    'milliseconds': milliseconds,
    'at': lastWatched,
    'meaningful': meaningful,
    'completed': completed,
  };
}

/// Where a film or episode was left off. Finished titles keep a `done` marker
/// so the series page can continue with the next episode.
class ResumePoint {
  const ResumePoint({required this.positionMs, required this.durationMs, required this.at, this.done = false});
  final int positionMs;
  final int durationMs;
  final int at;
  final bool done;

  Duration get position => Duration(milliseconds: positionMs);
  Duration get remaining => Duration(milliseconds: math.max(0, durationMs - positionMs));
  double get fraction => done
      ? 1
      : durationMs <= 0
      ? 0
      : (positionMs / durationMs).clamp(0, 1).toDouble();

  Map<String, dynamic> toJson() => {'pos': positionMs, 'dur': durationMs, 'at': at, if (done) 'done': true};
}

/// Personal timestamps, feedback and a bounded cache of structured film metadata.
/// Display titles and playback URLs always come from the current catalog.
/// This entire object is stored in SecureStore.
class PersonalLibrary {
  const PersonalLibrary({
    this.hasMovieBaseline = false,
    this.firstSeen = const {},
    this.viewing = const {},
    this.feedback = const {},
    this.vodViewing = const {},
    this.metadata = const {},
    this.resume = const {},
  });

  /// Höchstens so viele Fortsetzungspunkte; die ältesten fallen heraus.
  static const maxResumePoints = 400;

  final bool hasMovieBaseline;
  final Map<String, int?> firstSeen;
  final Map<String, ChannelViewing> viewing;
  final Map<String, TitleFeedback> feedback;
  final Map<String, VodViewing> vodViewing;
  final Map<String, TitleMetadata> metadata;
  final Map<String, ResumePoint> resume;

  PersonalLibrary copyWith({
    bool? hasMovieBaseline,
    Map<String, int?>? firstSeen,
    Map<String, ChannelViewing>? viewing,
    Map<String, TitleFeedback>? feedback,
    Map<String, VodViewing>? vodViewing,
    Map<String, TitleMetadata>? metadata,
    Map<String, ResumePoint>? resume,
  }) => PersonalLibrary(
    hasMovieBaseline: hasMovieBaseline ?? this.hasMovieBaseline,
    firstSeen: firstSeen ?? this.firstSeen,
    viewing: viewing ?? this.viewing,
    feedback: feedback ?? this.feedback,
    vodViewing: vodViewing ?? this.vodViewing,
    metadata: metadata ?? this.metadata,
    resume: resume ?? this.resume,
  );

  factory PersonalLibrary.fromJson(Map<String, dynamic> json) {
    final seen = <String, int?>{};
    if (json['firstSeen'] case final Map raw) {
      for (final entry in raw.entries) {
        if (entry.key is String && (entry.value == null || entry.value is int)) {
          seen[entry.key as String] = entry.value as int?;
        }
      }
    }
    final viewing = <String, ChannelViewing>{};
    if (json['viewing'] case final Map raw) {
      for (final entry in raw.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        final data = entry.value as Map;
        if (data['milliseconds'] is! int || data['lastWatched'] is! int || (data['milliseconds'] as int) <= 0) continue;
        viewing[entry.key as String] = ChannelViewing(
          milliseconds: data['milliseconds'] as int,
          lastWatched: data['lastWatched'] as int,
        );
      }
    }
    final metadata = <String, TitleMetadata>{};
    if (json['metadata'] case final Map raw) {
      for (final entry in raw.entries.take(200)) {
        if (entry.key is String && entry.value is Map) {
          metadata[entry.key as String] = TitleMetadata.fromJson(entry.value as Map);
        }
      }
    }
    final feedback = <String, TitleFeedback>{};
    if (json['feedback'] case final Map raw) {
      for (final entry in raw.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        final data = entry.value as Map;
        final choice = data['choice'];
        if ((choice != 'like' && choice != 'hide' && choice != 'none') || data['at'] is! int) continue;
        feedback[entry.key as String] = TitleFeedback(
          FeedbackChoice.values.byName(choice as String),
          data['at'] as int,
        );
      }
    }
    final vodViewing = <String, VodViewing>{};
    if (json['vodViewing'] case final Map raw) {
      for (final entry in raw.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        final data = entry.value as Map;
        if (data['milliseconds'] is! int || (data['milliseconds'] as int) <= 0 || data['at'] is! int) continue;
        vodViewing[entry.key as String] = VodViewing(
          milliseconds: data['milliseconds'] as int,
          lastWatched: data['at'] as int,
          meaningful: data['meaningful'] == true,
          completed: data['completed'] == true,
        );
      }
    }
    final resume = <String, ResumePoint>{};
    if (json['resume'] case final Map raw) {
      for (final entry in raw.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        final data = entry.value as Map;
        if (data['pos'] is! int || data['dur'] is! int || data['at'] is! int) continue;
        resume[entry.key as String] = ResumePoint(
          positionMs: data['pos'] as int,
          durationMs: data['dur'] as int,
          at: data['at'] as int,
          done: data['done'] == true,
        );
      }
    }
    return PersonalLibrary(
      hasMovieBaseline: json['hasMovieBaseline'] == true,
      firstSeen: seen,
      viewing: viewing,
      feedback: feedback,
      vodViewing: vodViewing,
      metadata: metadata,
      resume: resume,
    );
  }

  Map<String, dynamic> toJson() => {
    'hasMovieBaseline': hasMovieBaseline,
    'firstSeen': firstSeen,
    'viewing': {for (final entry in viewing.entries) entry.key: entry.value.toJson()},
    'feedback': {for (final entry in feedback.entries) entry.key: entry.value.toJson()},
    'metadata': {for (final entry in metadata.entries) entry.key: entry.value.toJson()},
    'vodViewing': {for (final entry in vodViewing.entries) entry.key: entry.value.toJson()},
    'resume': {for (final entry in resume.entries) entry.key: entry.value.toJson()},
  };

  ResumePoint? resumeFor(Channel channel) => resume[personalItemKey(channel)];

  /// Unter 30 s bleibt ein alter Punkt stehen (kurz reingeschaut). Kurz vor dem
  /// Ende gilt der Titel als gesehen, damit der Abspann nicht als Stelle zählt.
  PersonalLibrary saveResume(Channel channel, Duration position, Duration duration, DateTime now) {
    if (channel.type == ContentType.live || !channel.isPlayable || duration <= Duration.zero) return this;
    final pos = position.inMilliseconds.clamp(0, duration.inMilliseconds);
    final dur = duration.inMilliseconds;
    final finished = pos >= dur * 0.95 || dur > 1200000 && dur - pos < 120000;
    if (!finished && pos < 30000) return this;
    final key = personalItemKey(channel);
    final old = resume[key];
    if (old != null && !finished && !old.done && (old.positionMs - pos).abs() < 1000) return this;
    final updated = Map<String, ResumePoint>.of(resume)..remove(key);
    updated[key] = ResumePoint(
      positionMs: finished ? dur : pos,
      durationMs: dur,
      at: now.millisecondsSinceEpoch,
      done: finished,
    );
    while (updated.length > maxResumePoints) {
      updated.remove(updated.keys.first);
    }
    return copyWith(resume: updated);
  }

  PersonalLibrary clearResume(Channel channel) {
    final key = personalItemKey(channel);
    if (!resume.containsKey(key)) return this;
    return copyWith(resume: Map<String, ResumePoint>.of(resume)..remove(key));
  }

  /// Call only after a successful full movie-catalog load, before filtering.
  /// Unknown-date entries on the first import form a baseline, not a new row.
  PersonalLibrary observeMovies(Iterable<Channel> movies, DateTime now) {
    final updated = Map<String, int?>.of(firstSeen);
    var changed = !hasMovieBaseline;
    for (final channel in movies) {
      if (channel.type != ContentType.movie || !channel.isPlayable) continue;
      final key = personalItemKey(channel);
      if (!updated.containsKey(key)) {
        updated[key] = hasMovieBaseline ? now.millisecondsSinceEpoch : null;
        changed = true;
      }
    }
    return changed ? copyWith(hasMovieBaseline: true, firstSeen: updated) : this;
  }

  PersonalLibrary addWatch(Channel channel, Duration watched, DateTime now) {
    if (channel.type != ContentType.live || !channel.isPlayable || watched.inMilliseconds <= 0) return this;
    final key = personalItemKey(channel);
    final updated = Map<String, ChannelViewing>.of(viewing);
    updated[key] = ChannelViewing(
      milliseconds: (updated[key]?.milliseconds ?? 0) + watched.inMilliseconds,
      lastWatched: now.millisecondsSinceEpoch,
    );
    return copyWith(viewing: updated);
  }

  PersonalLibrary rememberMetadata(Channel channel, TitleMetadata incoming) {
    if (channel.type == ContentType.live || incoming.isEmpty) return this;
    final key = personalItemKey(channel);
    final old = metadata[key];
    final merged = TitleMetadata(
      genres: incoming.genres.isNotEmpty ? incoming.genres : old?.genres ?? const [],
      cast: incoming.cast.isNotEmpty ? incoming.cast : old?.cast ?? const [],
      director: incoming.director ?? old?.director,
    );
    if (old != null && old.toJson().toString() == merged.toJson().toString()) return this;
    final updated = Map<String, TitleMetadata>.of(metadata)..remove(key);
    updated[key] = merged;
    while (updated.length > 200) {
      updated.remove(updated.keys.first);
    }
    return copyWith(metadata: updated);
  }

  TitleFeedback? feedbackFor(Iterable<String> keys) {
    TitleFeedback? latest;
    for (final key in keys) {
      final value = feedback[key];
      if (value != null && (latest == null || value.at > latest.at)) latest = value;
    }
    return latest;
  }

  /// Both canonical and playlist identities are retained: metadata may become
  /// available later, and an uncertain title must never merge two remakes.
  PersonalLibrary setFeedback(Iterable<String> keys, FeedbackChoice? choice, DateTime now) {
    final updated = Map<String, TitleFeedback>.of(feedback);
    for (final key in keys) {
      // A neutral tombstone also resets old quality-variant aliases. Removing
      // only the canonical entry could otherwise resurrect an earlier like.
      updated[key] = TitleFeedback(choice ?? FeedbackChoice.none, now.millisecondsSinceEpoch);
    }
    return copyWith(feedback: updated);
  }

  VodViewing? vodFor(Iterable<String> keys) {
    VodViewing? latest;
    for (final key in keys) {
      final value = vodViewing[key];
      if (value != null &&
          (latest == null ||
              value.lastWatched > latest.lastWatched ||
              value.lastWatched == latest.lastWatched && value.milliseconds > latest.milliseconds)) {
        latest = value;
      }
    }
    return latest;
  }

  PersonalLibrary addVodWatch(
    Iterable<String> keys,
    Duration watched,
    DateTime now, {
    Duration duration = Duration.zero,
    bool reachedEnd = false,
    bool isMovie = true,
  }) {
    if (watched < Duration.zero || watched == Duration.zero && !reachedEnd) return this;
    final identities = keys.toSet();
    if (identities.isEmpty) return this;
    final old = vodFor(identities);
    final milliseconds = (old?.milliseconds ?? 0) + watched.inMilliseconds;
    final meaningfulAt = duration > Duration.zero
        ? math.max(30000, math.min(600000, duration.inMilliseconds ~/ 5))
        : 600000;
    final value = VodViewing(
      milliseconds: milliseconds,
      lastWatched: now.millisecondsSinceEpoch,
      meaningful: old?.meaningful == true || milliseconds >= meaningfulAt,
      // Seeking straight to the credits cannot mark a title as watched.
      completed:
          old?.completed == true ||
          isMovie && reachedEnd && duration > Duration.zero && milliseconds >= duration.inMilliseconds * 0.8,
    );
    final updated = Map<String, VodViewing>.of(vodViewing);
    for (final key in identities) {
      updated[key] = value;
    }
    return copyWith(vodViewing: updated);
  }

  List<Channel> mostWatched(Iterable<Channel> available, {int limit = 20}) {
    final unique = <String, Channel>{};
    for (final channel in available) {
      final key = personalItemKey(channel);
      if (channel.type == ContentType.live && channel.isPlayable && (viewing[key]?.milliseconds ?? 0) >= 30000) {
        unique.putIfAbsent(key, () => channel);
      }
    }
    return (unique.values.toList()..sort((a, b) {
          final first = viewing[personalItemKey(a)]!;
          final second = viewing[personalItemKey(b)]!;
          final duration = second.milliseconds.compareTo(first.milliseconds);
          return duration != 0 ? duration : second.lastWatched.compareTo(first.lastWatched);
        }))
        .take(limit)
        .toList();
  }

  DateTime? movieAddedAt(Channel channel, DateTime now) {
    final uploaded = parseAddedAt(channel.addedAt, now: now);
    if (uploaded != null) return uploaded;
    final seen = firstSeen[personalItemKey(channel)];
    return seen == null ? null : DateTime.fromMillisecondsSinceEpoch(seen, isUtc: true);
  }

  List<Channel> newMovies(Iterable<Channel> available, DateTime now, {int limit = 20}) {
    final cutoff = now.subtract(const Duration(days: 30));
    final dates = <String, DateTime>{};
    final unique = <String, Channel>{};
    for (final channel in available) {
      if (channel.type != ContentType.movie || !channel.isPlayable) continue;
      final key = personalItemKey(channel);
      final date = movieAddedAt(channel, now);
      if (date == null || date.isBefore(cutoff) || date.isAfter(now)) continue;
      dates[key] = date;
      unique.putIfAbsent(key, () => channel);
    }
    return (unique.values.toList()..sort((a, b) {
          final order = dates[personalItemKey(b)]!.compareTo(dates[personalItemKey(a)]!);
          return order != 0 ? order : a.name.compareTo(b.name);
        }))
        .take(limit)
        .toList();
  }
}

/// Wie es mit einer Serie weitergeht: die zuletzt angefangene Folge, sonst die
/// Folge nach der zuletzt beendeten. `null`, wenn noch nichts gesehen wurde.
({Season season, Episode episode, ResumePoint? point})? continueEpisode(PersonalLibrary library, List<Season> seasons) {
  final order = [
    for (final season in seasons)
      for (final episode in season.episodes) (season: season, episode: episode),
  ];
  var latest = -1;
  ResumePoint? latestPoint;
  for (final (i, item) in order.indexed) {
    final point = library.resumeFor(item.episode.channel);
    if (point != null && (latestPoint == null || point.at > latestPoint.at)) {
      latest = i;
      latestPoint = point;
    }
  }
  if (latestPoint == null) return null;
  if (!latestPoint.done) return (season: order[latest].season, episode: order[latest].episode, point: latestPoint);
  if (latest + 1 >= order.length) return null;
  final next = order[latest + 1];
  final nextPoint = library.resumeFor(next.episode.channel);
  return (season: next.season, episode: next.episode, point: nextPoint?.done == true ? null : nextPoint);
}

/// „noch 1 Std. 5 Min.“ bzw. „noch 42 Min.“
String remainingLabel(Duration remaining) {
  final minutes = math.max(1, (remaining.inSeconds / 60).round());
  if (minutes < 60) return 'noch $minutes Min.';
  final rest = minutes % 60;
  return rest == 0 ? 'noch ${minutes ~/ 60} Std.' : 'noch ${minutes ~/ 60} Std. $rest Min.';
}

/// Counts advancing playback against a monotonic clock. Pauses, buffering,
/// retries, backward seeks, large seek jumps and suspended-app gaps add no time.
class LiveWatchAccumulator {
  int? _lastPosition;
  int? _lastElapsed;
  int _pending = 0;

  void resetSample() {
    _lastPosition = null;
    _lastElapsed = null;
  }

  void sample({required Duration position, required Duration elapsed, required bool eligible, double rate = 1}) {
    if (!eligible || !rate.isFinite || rate <= 0) {
      resetSample();
      return;
    }
    final pos = position.inMilliseconds;
    final time = elapsed.inMilliseconds;
    if (_lastPosition != null && _lastElapsed != null) {
      final wall = time - _lastElapsed!;
      final advance = pos - _lastPosition!;
      if (wall > 0 && wall <= 5000 && advance > 0 && advance <= wall * rate + 2000) {
        _pending += math.min(wall, (advance / rate).round());
      }
    }
    _lastPosition = pos;
    _lastElapsed = time;
  }

  Duration take() {
    final value = Duration(milliseconds: _pending);
    _pending = 0;
    return value;
  }
}
