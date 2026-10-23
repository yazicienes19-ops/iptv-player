// The Movie Database: Zusatzinfos, Darsteller, Filmreihen, „Mehr wie dieses“.
// Wie in der Mac-App (lib/services/tmdb_api.dart): Schlüssel v3 oder Lesetoken v4 (eyJ…),
// Zuordnung über die TMDB-Nummer des Anbieters, sonst Suche nach bereinigtem Titel + Jahr.
'use strict';

(function (App) {
  const BASE = 'https://api.themoviedb.org/3';
  const IMAGE = 'https://image.tmdb.org/t/p/';

  App.tmdbKey = function () {
    return App.load('tmdbKey', '') || '';
  };

  App.hasTmdb = function () {
    return !!App.tmdbKey();
  };

  App.tmdbImage = function (path, size) {
    return path ? IMAGE + (size || 'w342') + path : null;
  };

  const cache = {};

  function get(path, params, key) {
    key = (key || App.tmdbKey()).trim();
    const bearer = key.indexOf('eyJ') === 0;
    let url = BASE + path + '?language=de-DE' + (bearer ? '' : '&api_key=' + encodeURIComponent(key));
    Object.keys(params || {}).forEach((k) => {
      if (params[k] != null) url += '&' + k + '=' + encodeURIComponent(params[k]);
    });
    const cacheKey = url;
    if (cache[cacheKey]) return cache[cacheKey];
    const request = fetch(App.proxied(url), { headers: bearer ? { Authorization: 'Bearer ' + key } : {} }).then((r) => {
      if (r.status === 401) throw new Error('Der TMDB-Schlüssel ist ungültig.');
      if (r.status === 404) throw new Error('Bei TMDB nicht gefunden.');
      if (r.status === 429) throw new Error('TMDB: zu viele Anfragen, bitte kurz warten.');
      if (!r.ok) throw new Error('TMDB nicht erreichbar (' + r.status + ').');
      return r.json();
    });
    cache[cacheKey] = request;
    request.catch(() => delete cache[cacheKey]);
    return request;
  }

  /// Prüft einen neuen Schlüssel mit einer günstigen Anfrage.
  App.verifyTmdbKey = function (key) {
    return get('/configuration', null, key);
  };

  // ---------- Titel bereinigen und vergleichen ----------

  const PROVIDER_PREFIX = /^\s*\(\s*(?:[A-Z]{1,3}\s*\|\s*)?[A-Z]{2,4}\s*-?\s*\)\s*/;
  const COUNTRY_PREFIX = /^\s*(?:\[[A-Za-z]{2,3}\]|\|[A-Za-z]{2,3}\||[A-Z]{2,3}(?:-[A-Z]{2})?\s*(?::|\||\s-\s))\s*/;
  const TRAILING_YEAR = /\s*(?:[-–]\s*((?:19|20)\d{2})|\(\s*((?:19|20)\d{2})\s*\))\s*$/;
  const NOISE = /\[[^\]]*\]|\(?\b(?:2160|1440|1080|720|576|540|480|360)[pi]\b\)?|\b(?:4K|UHD|FHD|FULLHD|HD|SD|HEVC|H\.?265|50FPS|60FPS|RAW|MULTI[- ]?SUB)\b/gi;

  /// "DE - Der Pate (1972) 4K" → { title: "Der Pate", year: 1972 }
  App.cleanTitle = function (name) {
    let text = (name || '').replace(PROVIDER_PREFIX, '').replace(COUNTRY_PREFIX, '').replace(NOISE, ' ');
    text = text.replace(/\s+/g, ' ').trim();
    let year = null;
    const match = TRAILING_YEAR.exec(text);
    if (match) {
      year = parseInt(match[1] || match[2], 10);
      text = text.slice(0, match.index);
    }
    text = text.replace(/[\s\-|:–]+$/, '').trim();
    return { title: text || (name || '').trim(), year: year };
  };

  /// Klein, ohne Satzzeichen, Artikel und Umlaut-Varianten (wie normalizeTitle in Dart).
  App.normalizeTitle = function (title) {
    return (title || '')
      .toLowerCase()
      .replace(/ä/g, 'ae')
      .replace(/ö/g, 'oe')
      .replace(/ü/g, 'ue')
      .replace(/ß/g, 'ss')
      .replace(/&/g, 'und')
      .replace(/[^a-z0-9]+/g, ' ')
      .replace(/^(the|der|die|das|a|an) /, '')
      .replace(/ /g, '');
  };

  function ref(json, type) {
    const isTv = type === 'tv' || json.media_type === 'tv';
    const date = (isTv ? json.first_air_date : json.release_date) || '';
    return {
      id: json.id,
      type: isTv ? 'tv' : 'movie',
      title: json.title || json.name || '',
      originalTitle: json.original_title || json.original_name || null,
      year: parseInt(date.slice(0, 4), 10) || null,
      poster: App.tmdbImage(json.poster_path),
      role: json.character || json.job || null,
      popularity: json.popularity || 0,
    };
  }

  function bestMatch(results, title, year) {
    const wanted = App.normalizeTitle(title);
    const score = (r) => {
      let points = 0;
      if (App.normalizeTitle(r.title) === wanted || App.normalizeTitle(r.originalTitle) === wanted) points += 10;
      if (year && r.year) {
        const diff = Math.abs(r.year - year);
        if (diff === 0) points += 5;
        if (diff === 1) points += 3;
      }
      return points;
    };
    return results.slice().sort((a, b) => score(b) - score(a))[0];
  }

  function search(title, type, year) {
    const path = type === 'tv' ? '/search/tv' : '/search/movie';
    const yearParam = type === 'tv' ? 'first_air_date_year' : 'year';
    const run = (withYear) => {
      const params = { query: title, include_adult: 'false' };
      if (withYear) params[yearParam] = withYear;
      return get(path, params).then((data) => (data.results || []).map((r) => ref(r, type)));
    };
    // Jahresangaben in Playlists weichen oft um ein Jahr ab.
    return run(year)
      .then((results) => (results.length || !year ? results : run(null)))
      .then((results) => (results.length ? bestMatch(results, title, year) : null));
  }

  // ---------- Titel, Personen, Filmreihen ----------

  function certificationOf(json, isTv) {
    if (isTv) {
      const ratings = (json.content_ratings && json.content_ratings.results) || [];
      for (const country of ['DE', 'US']) {
        const entry = ratings.filter((r) => r.iso_3166_1 === country)[0];
        if (entry && entry.rating) return (country === 'DE' ? 'FSK ' : '') + entry.rating;
      }
      return null;
    }
    const releases = (json.release_dates && json.release_dates.results) || [];
    for (const country of ['DE', 'US']) {
      const entry = releases.filter((r) => r.iso_3166_1 === country)[0];
      const cert = entry && (entry.release_dates || []).map((d) => d.certification).filter(Boolean)[0];
      if (cert) return (country === 'DE' ? 'FSK ' : '') + cert;
    }
    return null;
  }

  function title(id, type) {
    const isTv = type === 'tv';
    const append = isTv ? 'aggregate_credits,recommendations,content_ratings' : 'credits,recommendations,release_dates';
    return get('/' + (isTv ? 'tv' : 'movie') + '/' + id, { append_to_response: append }).then((json) => {
      const credits = (isTv ? json.aggregate_credits : json.credits) || json.credits || {};
      const runtime = json.runtime || (json.episode_run_time || [])[0] || null;
      const result = {
        id: json.id,
        type: type,
        tagline: json.tagline || null,
        overview: json.overview || null,
        genres: (json.genres || []).map((g) => g.name),
        rating: json.vote_average || null,
        runtime: runtime ? (runtime >= 60 ? Math.floor(runtime / 60) + ' Std. ' + (runtime % 60) + ' Min.' : runtime + ' Min.') : null,
        certification: certificationOf(json, isTv),
        directors: isTv
          ? (json.created_by || []).map((c) => c.name)
          : (credits.crew || []).filter((c) => c.job === 'Director').map((c) => c.name),
        cast: (credits.cast || []).slice(0, 20).map((c) => ({
          id: c.id,
          name: c.name,
          character: (c.roles && c.roles[0] && c.roles[0].character) || c.character || null,
          photo: App.tmdbImage(c.profile_path, 'w185'),
        })),
        backdrop: App.tmdbImage(json.backdrop_path, 'w1280'),
        poster: App.tmdbImage(json.poster_path),
        collection: json.belongs_to_collection ? { id: json.belongs_to_collection.id, name: json.belongs_to_collection.name } : null,
        recommendations: ((json.recommendations && json.recommendations.results) || []).map((r) => ref(r, type)),
      };
      result.overviewGerman = !!result.overview;
      if (result.overview) return result;
      // Keine deutsche Beschreibung: englische nehmen.
      return get('/' + (isTv ? 'tv' : 'movie') + '/' + id, { language: 'en-US' }).then((en) => {
        result.overview = en.overview || null;
        return result;
      });
    });
  }

  /// TMDB-Daten zu einem Film oder einer Serie der Playlist (oder null ohne Schlüssel/Treffer).
  App.tmdbFor = function (item, details) {
    if (!App.hasTmdb() || (item.kind !== 'movie' && item.kind !== 'series')) return Promise.resolve(null);
    const type = item.kind === 'series' ? 'tv' : 'movie';
    if (details && details.tmdbId) return title(details.tmdbId, type);
    const clean = App.cleanTitle(item.name);
    return search(clean.title, type, clean.year || parseInt(item.year, 10) || null).then((match) => (match ? title(match.id, type) : null));
  };

  App.tmdbPerson = function (id) {
    return get('/person/' + id, { append_to_response: 'combined_credits' }).then((json) => {
      const credits = (json.combined_credits && json.combined_credits.cast) || [];
      const person = {
        name: json.name,
        photo: App.tmdbImage(json.profile_path, 'h632'),
        biography: json.biography || null,
        birthday: json.birthday || null,
        place: json.place_of_birth || null,
        department: json.known_for_department || null,
        credits: credits
          .filter((c) => c.media_type === 'movie' || c.media_type === 'tv')
          .map((c) => ref(c))
          .sort((a, b) => b.popularity - a.popularity),
      };
      if (person.biography) return person;
      return get('/person/' + id, { language: 'en-US' }).then((en) => {
        person.biography = en.biography || null;
        return person;
      });
    });
  };

  App.tmdbCollection = function (id) {
    return get('/collection/' + id).then((json) => ({
      name: json.name,
      overview: json.overview || null,
      backdrop: App.tmdbImage(json.backdrop_path, 'w1280'),
      parts: (json.parts || [])
        .map((p) => ref(p, 'movie'))
        .sort((a, b) => (a.year || 9999) - (b.year || 9999)),
    }));
  };

  // ---------- Was davon gibt es in der Playlist? ----------

  let index = null;

  /// Titelverzeichnis aus allen Filmen und Serien; wird einmal geladen.
  function playlistIndex() {
    if (!index) {
      index = Promise.all([App.provider.allItems('movie').catch(() => []), App.provider.allItems('series').catch(() => [])]).then(
        (lists) => {
          const byTitle = {};
          lists.forEach((list) =>
            list.forEach((item) => {
              const clean = App.cleanTitle(item.name);
              const key = App.normalizeTitle(clean.title);
              (byTitle[key] = byTitle[key] || []).push({ item: item, year: clean.year || parseInt(item.year, 10) || null });
            })
          );
          return byTitle;
        }
      );
      index.catch(() => (index = null));
    }
    return index;
  }

  App.resetTmdbIndex = function () {
    index = null;
  };

  /// Ordnet TMDB-Treffer Einträgen der Playlist zu; gleicher Titel, Jahr ±1.
  /// Fehlt dem Anbieter ein Poster, kommt das von TMDB dazu.
  App.findInPlaylist = function (refs) {
    return matchInPlaylist(refs).then((found) =>
      found.map((item, i) => (item && !item.logo && refs[i].poster ? Object.assign({}, item, { logo: refs[i].poster }) : item))
    );
  };

  function matchInPlaylist(refs) {
    return playlistIndex().then((byTitle) =>
      refs.map((r) => {
        const kind = r.type === 'tv' ? 'series' : 'movie';
        const titles = [r.title, r.originalTitle].filter(Boolean);
        for (let t = 0; t < titles.length; t++) {
          const candidates = (byTitle[App.normalizeTitle(titles[t])] || []).filter((c) => c.item.kind === kind);
          for (let i = 0; i < candidates.length; i++) {
            const c = candidates[i];
            if (!c.year || !r.year || Math.abs(c.year - r.year) <= 1) return c.item;
          }
        }
        return null;
      })
    );
  }
})(IpFlix);
