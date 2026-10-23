/// Daten aus The Movie Database (TMDB). Nur, was IpFlix anzeigt.
library;

enum TmdbMediaType { movie, tv }

String? tmdbImage(String? path, {String size = 'w500'}) =>
    path == null || path.isEmpty ? null : 'https://image.tmdb.org/t/p/$size$path';

int? _year(Object? date) {
  final text = date is String ? date : '';
  return text.length >= 4 ? int.tryParse(text.substring(0, 4)) : null;
}

String? _text(Object? value) => value is String && value.trim().isNotEmpty ? value.trim() : null;

/// Kurzer Verweis auf einen Film oder eine Serie (Empfehlungen, Filmografie, Reihen).
class TmdbRef {
  const TmdbRef({
    required this.id,
    required this.type,
    required this.title,
    this.originalTitle,
    this.year,
    this.posterPath,
    this.role,
    this.popularity = 0,
  });

  final int id;
  final TmdbMediaType type;
  final String title;
  final String? originalTitle;
  final int? year;
  final String? posterPath;

  /// Bei Filmografien: Rolle bzw. Aufgabe der Person.
  final String? role;
  final double popularity;

  String? get poster => tmdbImage(posterPath, size: 'w342');

  factory TmdbRef.fromJson(Map<String, dynamic> json, {TmdbMediaType? type}) {
    final mediaType = type ?? (json['media_type'] == 'tv' ? TmdbMediaType.tv : TmdbMediaType.movie);
    final isTv = mediaType == TmdbMediaType.tv;
    return TmdbRef(
      id: json['id'] as int,
      type: mediaType,
      title: _text(isTv ? json['name'] : json['title']) ?? '',
      originalTitle: _text(isTv ? json['original_name'] : json['original_title']),
      year: _year(isTv ? json['first_air_date'] : json['release_date']),
      posterPath: _text(json['poster_path']),
      role: _text(json['character']) ?? _text(json['job']),
      popularity: (json['popularity'] as num?)?.toDouble() ?? 0,
    );
  }
}

class TmdbCast {
  const TmdbCast({required this.id, required this.name, this.character, this.profilePath});

  final int id;
  final String name;
  final String? character;
  final String? profilePath;

  String? get photo => tmdbImage(profilePath, size: 'w185');

  factory TmdbCast.fromJson(Map<String, dynamic> json) {
    // Serien liefern über aggregate_credits mehrere Rollen.
    final roles = json['roles'];
    final character = roles is List && roles.isNotEmpty ? (roles.first as Map)['character'] : json['character'];
    return TmdbCast(
      id: json['id'] as int,
      name: _text(json['name']) ?? '',
      character: _text(character),
      profilePath: _text(json['profile_path']),
    );
  }
}

/// Ausführliche Infos zu einem Film oder einer Serie.
class TmdbTitle {
  const TmdbTitle({
    required this.id,
    required this.type,
    required this.title,
    this.originalTitle,
    this.tagline,
    this.overview,
    this.year,
    this.endYear,
    this.runtimeMinutes,
    this.rating,
    this.voteCount = 0,
    this.genres = const [],
    this.certification,
    this.directors = const [],
    this.cast = const [],
    this.trailerYoutubeKey,
    this.posterPath,
    this.backdropPath,
    this.collectionId,
    this.collectionName,
    this.recommendations = const [],
    this.seasonCount,
    this.episodeCount,
    this.overviewIsGerman = true,
  });

  final int id;
  final TmdbMediaType type;
  final String title;
  final String? originalTitle;
  final String? tagline;
  final String? overview;
  final int? year;

  /// Nur Serien: Jahr der letzten Folge.
  final int? endYear;
  final int? runtimeMinutes;
  final double? rating;
  final int voteCount;
  final List<String> genres;

  /// Deutsche Altersfreigabe (FSK), sonst die US-Freigabe.
  final String? certification;

  /// Regie bzw. bei Serien die Erfinder.
  final List<String> directors;
  final List<TmdbCast> cast;
  final String? trailerYoutubeKey;
  final String? posterPath;
  final String? backdropPath;
  final int? collectionId;
  final String? collectionName;
  final List<TmdbRef> recommendations;
  final int? seasonCount;
  final int? episodeCount;

  /// `false`, wenn TMDB keine deutsche Handlung hatte und [overview] englisch ist.
  final bool overviewIsGerman;

  String? get poster => tmdbImage(posterPath, size: 'w500');
  String? get backdrop => tmdbImage(backdropPath, size: 'w1280');

  /// „2 Std. 32 Min.“
  String? get runtimeLabel {
    final minutes = runtimeMinutes;
    if (minutes == null || minutes <= 0) return null;
    return minutes >= 60 ? '${minutes ~/ 60} Std. ${minutes % 60} Min.' : '$minutes Min.';
  }

  factory TmdbTitle.fromJson(Map<String, dynamic> json, TmdbMediaType type) {
    final isTv = type == TmdbMediaType.tv;
    final credits = (json[isTv ? 'aggregate_credits' : 'credits'] ?? json['credits']) as Map<String, dynamic>? ?? {};
    final crew = (credits['crew'] as List? ?? const []).cast<Map<String, dynamic>>();
    final videos = ((json['videos'] as Map?)?['results'] as List? ?? const []).cast<Map<String, dynamic>>();
    final trailer =
        videos.where((v) => v['site'] == 'YouTube' && v['type'] == 'Trailer').firstOrNull ??
        videos.where((v) => v['site'] == 'YouTube').firstOrNull;
    final collection = json['belongs_to_collection'] as Map<String, dynamic>?;
    final runtimes = json['episode_run_time'];

    return TmdbTitle(
      id: json['id'] as int,
      type: type,
      title: _text(isTv ? json['name'] : json['title']) ?? '',
      originalTitle: _text(isTv ? json['original_name'] : json['original_title']),
      tagline: _text(json['tagline']),
      overview: _text(json['overview']),
      year: _year(isTv ? json['first_air_date'] : json['release_date']),
      endYear: isTv ? _year(json['last_air_date']) : null,
      runtimeMinutes: isTv
          ? (runtimes is List && runtimes.isNotEmpty ? runtimes.first as int? : null)
          : json['runtime'] as int?,
      rating: (json['vote_average'] as num?)?.toDouble(),
      voteCount: json['vote_count'] as int? ?? 0,
      genres: [for (final g in (json['genres'] as List? ?? const [])) (g as Map)['name'] as String],
      certification: isTv ? _tvCertification(json) : _movieCertification(json),
      directors: isTv
          ? [for (final c in (json['created_by'] as List? ?? const [])) (c as Map)['name'] as String]
          : [
              for (final c in crew)
                if (c['job'] == 'Director') c['name'] as String,
            ],
      cast: [
        for (final c in (credits['cast'] as List? ?? const []).take(20)) TmdbCast.fromJson(c as Map<String, dynamic>),
      ],
      trailerYoutubeKey: trailer?['key'] as String?,
      posterPath: _text(json['poster_path']),
      backdropPath: _text(json['backdrop_path']),
      collectionId: collection?['id'] as int?,
      collectionName: _text(collection?['name']),
      recommendations: [
        for (final r in ((json['recommendations'] as Map?)?['results'] as List? ?? const []))
          TmdbRef.fromJson(r as Map<String, dynamic>, type: type),
      ],
      seasonCount: json['number_of_seasons'] as int?,
      episodeCount: json['number_of_episodes'] as int?,
      overviewIsGerman: json['_overviewFallback'] != true,
    );
  }

  static String? _movieCertification(Map<String, dynamic> json) {
    final results = ((json['release_dates'] as Map?)?['results'] as List? ?? const []).cast<Map>();
    for (final country in ['DE', 'US']) {
      final entry = results.where((r) => r['iso_3166_1'] == country).firstOrNull;
      for (final date in (entry?['release_dates'] as List? ?? const []).cast<Map>()) {
        final cert = _text(date['certification']);
        if (cert != null) return country == 'DE' ? 'FSK $cert' : cert;
      }
    }
    return null;
  }

  static String? _tvCertification(Map<String, dynamic> json) {
    final results = ((json['content_ratings'] as Map?)?['results'] as List? ?? const []).cast<Map>();
    for (final country in ['DE', 'US']) {
      final cert = _text(results.where((r) => r['iso_3166_1'] == country).firstOrNull?['rating']);
      if (cert != null) return country == 'DE' ? 'FSK $cert' : cert;
    }
    return null;
  }
}

/// Eine Filmreihe, z. B. „Harry Potter – Filmreihe“.
class TmdbCollection {
  const TmdbCollection({
    required this.id,
    required this.name,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.parts = const [],
  });

  final int id;
  final String name;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;

  /// Nach Erscheinungsjahr sortiert; Teile ohne Datum (angekündigt) am Ende.
  final List<TmdbRef> parts;

  String? get backdrop => tmdbImage(backdropPath, size: 'w1280');

  factory TmdbCollection.fromJson(Map<String, dynamic> json) {
    final parts = [
      for (final p in (json['parts'] as List? ?? const []))
        TmdbRef.fromJson(p as Map<String, dynamic>, type: TmdbMediaType.movie),
    ]..sort((a, b) => (a.year ?? 9999).compareTo(b.year ?? 9999));
    return TmdbCollection(
      id: json['id'] as int,
      name: _text(json['name']) ?? '',
      overview: _text(json['overview']),
      posterPath: _text(json['poster_path']),
      backdropPath: _text(json['backdrop_path']),
      parts: parts,
    );
  }
}

class TmdbPerson {
  const TmdbPerson({
    required this.id,
    required this.name,
    this.biography,
    this.profilePath,
    this.birthday,
    this.deathday,
    this.placeOfBirth,
    this.knownFor,
    this.credits = const [],
  });

  final int id;
  final String name;
  final String? biography;
  final String? profilePath;
  final DateTime? birthday;
  final DateTime? deathday;
  final String? placeOfBirth;
  final String? knownFor;

  /// Filme und Serien, nach Beliebtheit sortiert, ohne Doppelte.
  final List<TmdbRef> credits;

  String? get photo => tmdbImage(profilePath, size: 'h632');

  int? get age {
    final born = birthday;
    if (born == null) return null;
    final end = deathday ?? DateTime.now();
    var years = end.year - born.year;
    if (end.month < born.month || (end.month == born.month && end.day < born.day)) years--;
    return years;
  }

  factory TmdbPerson.fromJson(Map<String, dynamic> json) {
    final combined = json['combined_credits'] as Map<String, dynamic>? ?? {};
    final seen = <String>{};
    final credits =
        <TmdbRef>[
            for (final c in [...(combined['cast'] as List? ?? const []), ...(combined['crew'] as List? ?? const [])])
              TmdbRef.fromJson(c as Map<String, dynamic>),
          ].where((c) => c.title.isNotEmpty && seen.add('${c.type.name}:${c.id}')).toList()
          ..sort((a, b) => b.popularity.compareTo(a.popularity));
    return TmdbPerson(
      id: json['id'] as int,
      name: _text(json['name']) ?? '',
      biography: _text(json['biography']),
      profilePath: _text(json['profile_path']),
      birthday: DateTime.tryParse('${json['birthday']}'),
      deathday: DateTime.tryParse('${json['deathday']}'),
      placeOfBirth: _text(json['place_of_birth']),
      knownFor: switch (json['known_for_department']) {
        'Acting' => 'Schauspiel',
        'Directing' => 'Regie',
        'Writing' => 'Drehbuch',
        'Production' => 'Produktion',
        final Object? other => _text(other),
      },
      credits: credits,
    );
  }
}
