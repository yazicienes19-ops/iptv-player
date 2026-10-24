// Lokale Suche und echte IMDb-Daten. Kompatibel mit Chrome 53 / webOS 4.
'use strict';

(function (App) {
  const SOURCE = 'https://data.imdb.com/non-commercial-datasets/';
  const ATTRIBUTION = 'Information courtesy of IMDb (https://www.imdb.com). Used with permission.';
  let state = { available: false, source: SOURCE, attribution: ATTRIBUTION, generatedAt: null, minVotes: 25000, count: 0 };
  let byId = Object.create(null);
  let byTitleYear = Object.create(null);
  let byTitle = Object.create(null);
  let matchCache = new WeakMap();
  let featureCache = new WeakMap();
  let loading = null;

  function normalize(value) {
    let result = String(value || '').toLowerCase();
    if (result.normalize) result = result.normalize('NFD').replace(/[\u0300-\u036f]/g, '');
    return result.replace(/ß/g, 'ss').replace(/ı/g, 'i').replace(/&/g, ' and ')
      .replace(/[.,:;!?"'‘’“”()\[\]{}|/\\_–—-]/g, ' ').replace(/\s+/g, ' ').trim();
  }

  const COUNTRY_CODES = /^(?:de|deu|ger|at|ch|tr|tur|uk|gb|us|usa|en|eng|fr|fra|es|esp|it|ita|pt|por|nl|nld|al|alb|gr|grc|ru|rus|pl|pol|ar|ara|ro|rou|se|swe|no|nor|dk|dnk|fi|fin)$/i;
  const QUALITY_END = /(?:[\s._-]+|[([]\s*)(?:4k|uhd|fhd|fullhd|hd|sd|2160p|1440p|1080[pi]|720p|576p|480p|hevc|avc|h[.]?26[45]|x26[45]|hdr10[+]?|hdr|dolby[ .-]?vision|dv|aac|ac3|eac3|dts|web[ .-]?dl|webrip|bluray|brrip|dvdrip|50fps|60fps|multi[ -]?sub)[)\]]*\s*$/i;

  // Remove recognizable provider decoration, never an arbitrary bracketed word
  // or the last four digits: [REC], 1917 and Blade Runner 2049 are film titles.
  function cleanMetadataTitle(raw) {
    let title = String(raw || '').trim();
    for (let i = 0; i < 3; i++) {
      const prefix = title.match(/^\s*(?:\(\s*(?:[VS]\s*\|\s*)?([A-Za-z]{2,3})\s*-?\s*\)|\[([A-Za-z]{2,3})\]|\|([A-Za-z]{2,3})\||([A-Za-z]{2,3})\s*(?::|\|| - ))\s*/);
      if (prefix && COUNTRY_CODES.test(prefix[1] || prefix[2] || prefix[3] || prefix[4])) {
        title = title.slice(prefix[0].length);
        continue;
      }
      const quality = title.match(/^(?:[([](?:4k|uhd|fhd|hd|sd|2160p|1080p|720p|hevc)[)\]]|(?:4k|uhd|fhd|hd|sd|2160p|1080p|720p|hevc)\s*\|)\s*/i);
      if (!quality || quality[0].length === title.length) break;
      title = title.slice(quality[0].length);
    }
    let prior;
    do { prior = title; title = title.replace(QUALITY_END, '').trim(); } while (title && title !== prior);
    let year = null;
    const match = title.match(/\s*(?:[-–]\s*((?:18|19|20)\d{2})|[([]\s*((?:18|19|20)\d{2})\s*[)\]])\s*$/);
    if (match && match.index > 0) {
      year = Number(match[1] || match[2]);
      title = title.slice(0, match.index);
    }
    title = title.replace(/[\s|:–-]+$/, '').replace(/\s+/g, ' ').trim();
    return { title: title || String(raw || '').trim(), year: year };
  }

  function titleOf(item) {
    return cleanMetadataTitle(item.name || item.title || '').title;
  }

  // Common sequel suffixes may be Roman or Arabic in provider lists. Single
  // letters and standalone numeric titles are intentionally left untouched.
  function titleKey(title) {
    const roman = { ii: '2', iii: '3', iv: '4', vi: '6', vii: '7', viii: '8', ix: '9' };
    return normalize(title).replace(/\s+(ii|iii|iv|vi|vii|viii|ix)$/, (suffix, numeral) => ' ' + roman[numeral]);
  }

  function yearOf(item) {
    const explicit = String(item.year || item.releaseDate || item.release_date || '');
    const found = explicit.match(/^(?:18|19|20)\d{2}(?:$|[-/])/);
    return found ? Number(found[0].slice(0, 4)) : cleanMetadataTitle(item.name || item.title || '').year;
  }

  App.catalogTitle = cleanMetadataTitle;
  App.catalogNormalize = normalize;
  App.catalogTitleKey = titleKey;

  function imdbId(item) {
    const value = item.imdbId || item.imdb_id || item.imdb;
    if (value && typeof value === 'object') return value.id || null;
    const found = String(value || '').match(/(?:^|\/)(tt\d{7,12})(?:\/|$)/);
    return found ? found[1] : null;
  }

  function copyState() { return Object.assign({}, state); }

  function install(data) {
    if (!data || data.schemaVersion !== 1 || !Array.isArray(data.movies) || !data.generatedAt || !(data.minVotes > 0)) {
      throw new Error('Ungültiger IMDb-Katalog.');
    }
    const nextIds = Object.create(null);
    const nextTitles = Object.create(null);
    const nextPlainTitles = Object.create(null);
    data.movies.forEach((movie) => {
      if (!movie || !/^tt\d{7,12}$/.test(movie.id) || typeof movie.title !== 'string' || !movie.title ||
          !Number.isFinite(movie.rating) || movie.rating < 1 || movie.rating > 10 ||
          !Number.isFinite(movie.votes) || movie.votes < data.minVotes ||
          !Number.isFinite(movie.year) || !Array.isArray(movie.genres)) return;
      nextIds[movie.id] = movie;
      [movie.title, movie.originalTitle].concat(Array.isArray(movie.aliases) ? movie.aliases : []).forEach((title) => {
        if (typeof title !== 'string' || !title) return;
        const plain = titleKey(title);
        const plainList = nextPlainTitles[plain] || (nextPlainTitles[plain] = []);
        if (plainList.indexOf(movie) < 0) plainList.push(movie);
        const key = plain + ':' + movie.year;
        const list = nextTitles[key] || (nextTitles[key] = []);
        if (list.indexOf(movie) < 0) list.push(movie);
      });
    });
    byId = nextIds;
    byTitleYear = nextTitles;
    byTitle = nextPlainTitles;
    matchCache = new WeakMap();
    featureCache = new WeakMap();
    state = {
      available: true, source: SOURCE, attribution: ATTRIBUTION,
      generatedAt: data.generatedAt, minVotes: data.minVotes, count: Object.keys(byId).length,
    };
    return copyState();
  }

  function match(item) {
    if (!state.available || !item || item.kind && item.kind !== 'movie') return null;
    const id = imdbId(item);
    const year = yearOf(item);
    const signature = (id || '') + '|' + String(item.imdbId || item.imdb_id || item.imdb || '') + '|' + (year || '') + '|' + (item.name || item.title || '');
    const cached = matchCache.get(item);
    if (cached && cached.signature === signature) return cached.movie;
    let movie = null;
    if (id) movie = byId[id] || null;
    else if (!(item.imdbId || item.imdb_id || item.imdb)) {
      const title = titleOf(item);
      let candidates = year ? byTitleYear[titleKey(title) + ':' + year] || [] : byTitle[titleKey(title)] || [];
      // Try the full title before interpreting a bare trailing year. This
      // preserves numeric titles that are present in the metadata catalog.
      if (!year && !candidates.length) {
        const suffix = title.match(/^(.+)\s+((?:18|19|20)\d{2})$/);
        if (suffix && Number(suffix[2]) <= new Date().getFullYear() + 1) {
          candidates = byTitleYear[titleKey(suffix[1]) + ':' + suffix[2]] || [];
        }
      }
      if (candidates.length === 1) movie = candidates[0];
    }
    matchCache.set(item, { signature: signature, movie: movie });
    return movie;
  }

  App.imdbCatalog = {
    load: function (refresh) {
      if (loading && !refresh) return loading;
      loading = Promise.resolve().then(() => fetch('/data/imdb.json', { cache: 'no-cache' })).then((response) => {
        if (!response.ok) throw new Error('IMDb-Katalog nicht vorhanden.');
        return response.json();
      }).then(install).catch(() => {
        // Kein Ersatz durch Anbieter-/TMDb-Werte: IMDb ist eine eigene Quelle.
        loading = null;
        return copyState();
      });
      return loading;
    },
    status: copyState,
    match: match,
  };

  const GENRES = {
    krimi: 'crime', krimis: 'crime', kriminalfilm: 'crime', crime: 'crime',
    thriller: 'thriller', action: 'action', abenteuer: 'adventure', adventure: 'adventure',
    komodie: 'comedy', komodien: 'comedy', comedy: 'comedy', drama: 'drama', dramen: 'drama',
    horror: 'horror', sciencefiction: 'sci fi', scifi: 'sci fi', 'science fiction': 'sci fi', 'sci fi': 'sci fi',
    fantasie: 'fantasy', fantasy: 'fantasy', animation: 'animation', familie: 'family', family: 'family',
    romantik: 'romance', liebesfilm: 'romance', romance: 'romance', mysterium: 'mystery', mystery: 'mystery',
    dokumentation: 'documentary', dokumentarfilm: 'documentary', documentary: 'documentary',
    geschichte: 'history', history: 'history', krieg: 'war', war: 'war', western: 'western',
  };

  function canonicalGenre(value) {
    const key = normalize(value);
    return GENRES[key] || key;
  }

  function strings(value) {
    if (Array.isArray(value)) return value.map((entry) => entry == null ? '' : typeof entry === 'object' ? entry.name || '' : String(entry));
    return String(value || '').split(/[,/|]/);
  }

  function genresOf(item) {
    const movie = match(item);
    const supplied = strings(item.genres || item.genre).map(canonicalGenre).filter(Boolean);
    return supplied.length ? supplied : strings(movie && movie.genres).map(canonicalGenre).filter(Boolean);
  }

  App.catalogIdentity = function (item) {
    const movie = match(item);
    return movie ? 'imdb:' + movie.id : null;
  };

  App.catalogFeatures = function (item) {
    // Snapshot metadata rather than object identity alone: providers may enrich
    // the same item after its detail request has completed.
    const signature = JSON.stringify([item.name, item.title, item.year, item.releaseDate, item.release_date,
      imdbId(item), String(item.imdbId || item.imdb_id || item.imdb || ''), item.genres, item.genre, item.cast, item.director]);
    const cached = featureCache.get(item);
    if (cached && cached.signature === signature) return cached.features;
    const movie = match(item);
    const features = Object.freeze({
      identity: movie ? 'imdb:' + movie.id : null,
      title: titleOf(item), year: yearOf(item) || (movie && movie.year) || null,
      genres: Object.freeze(genresOf(item)), cast: Object.freeze(strings(item.cast).map(normalize).filter(Boolean)),
      director: Object.freeze(strings(item.director).map(normalize).filter(Boolean)),
    });
    featureCache.set(item, { signature: signature, features: features });
    return features;
  };

  App.rankedMovies = function (items, genre, options) {
    const seen = Object.create(null);
    const ranked = [];
    const required = genre ? canonicalGenre(genre) : null;
    (items || []).forEach((item) => {
      const movie = match(item);
      if (!movie || seen[movie.id] || required && movie.genres.map(canonicalGenre).indexOf(required) < 0) return;
      seen[movie.id] = true;
      ranked.push(Object.assign({}, item, { imdb: movie }));
    });
    ranked.sort((a, b) => b.imdb.rating - a.imdb.rating || b.imdb.votes - a.imdb.votes ||
      (a.imdb.id < b.imdb.id ? -1 : 1));
    return Object.assign(copyState(), {
      matchedCount: ranked.length,
      items: ranked.slice(0, options && options.limit > 0 ? options.limit : ranked.length),
    });
  };

  // Begrenzte Tippfehlerkorrektur (eine Einfügung/Löschung/Ersetzung oder
  // Vertauschung) hält die Suche bei großen Anbieterlisten überschaubar.
  function near(a, b) {
    if (a === b) return true;
    if (a.length < 4 || b.length < 4 || Math.abs(a.length - b.length) > 1) return false;
    if (a.length === b.length) {
      const wrong = [];
      for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) wrong.push(i);
      return wrong.length === 1 || wrong.length === 2 && wrong[1] === wrong[0] + 1 &&
        a[wrong[0]] === b[wrong[1]] && a[wrong[1]] === b[wrong[0]];
    }
    const short = a.length < b.length ? a : b;
    const long = a.length < b.length ? b : a;
    let skip = 0;
    for (let i = 0; i < short.length; i++) {
      if (short[i] !== long[i + skip]) {
        if (skip) return false;
        skip++;
        if (short[i] !== long[i + skip]) return false;
      }
    }
    return true;
  }

  function searchScore(item, query) {
    const title = titleKey(titleOf(item));
    if (!title) return 0;
    if (title === query) return 1000;
    if (title.indexOf(query) === 0) return 850;
    if (title.indexOf(query) >= 0) return 700;
    const genres = genresOf(item);
    if (genres.indexOf(canonicalGenre(query)) >= 0) return 600;
    const metadata = normalize(strings(item.cast).join(' ') + ' ' + strings(item.director).join(' ') + ' ' +
      genres.join(' ') + ' ' + (item.year || '') + ' ' + (item.categoryName || ''));
    if (metadata.indexOf(query) >= 0) return 500;
    const titleWords = title.split(' ');
    const words = titleWords.concat(metadata.split(' '));
    const parts = query.split(' ');
    let score = 0;
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i];
      const token = canonicalGenre(part);
      if (titleWords.indexOf(part) >= 0) score += 80;
      else if (words.indexOf(token) >= 0 || genres.indexOf(token) >= 0) score += 40;
      else if (words.some((word) => word.indexOf(part) === 0 && part.length >= 3)) score += 30;
      else if (titleWords.some((word) => near(word, part))) score += 20;
      else return 0;
    }
    return 200 + score / parts.length;
  }

  function similarity(item, seed) {
    if (item === seed || item.kind === seed.kind && item.id != null && item.id === seed.id ||
        titleKey(titleOf(item)) === titleKey(titleOf(seed))) return 0;
    if (seed.kind && item.kind && seed.kind !== item.kind) return 0;
    const seedGenres = genresOf(seed);
    const genres = genresOf(item);
    let score = genres.filter((genre) => seedGenres.indexOf(genre) >= 0).length * 30;
    const seedDirector = strings(seed.director).map(normalize).filter(Boolean);
    const seedCast = strings(seed.cast).map(normalize).filter(Boolean);
    score += strings(item.director).map(normalize).filter((name) => name && seedDirector.indexOf(name) >= 0).length * 60;
    score += strings(item.cast).map(normalize).filter((name) => name && seedCast.indexOf(name) >= 0).length * 20;
    // Kategorie ist ein schwächeres Signal und wird nur genutzt, wenn der
    // Anbieter Genre/Personen nicht liefert. Keine beliebigen Treffer auffüllen.
    if (!seedGenres.length && !genres.length && seed.catId != null && seed.catId === item.catId) score += 10;
    if (score && yearOf(seed) && yearOf(item) && Math.abs(yearOf(seed) - yearOf(item)) <= 10) score += 3;
    return score;
  }

  // Gemeinsamer Parser für Suchoberfläche und Katalog. Der Titel behält seine
  // Schreibweise; Umlaute und ausgeschriebene Umlaute gelten im Präfix gleich.
  App.parseSimilarQuery = function (rawQuery) {
    const query = String(rawQuery || '').replace(/\s+/g, ' ').trim();
    const found = query.match(/^(?:(?:filme?|serien?)\s+)?(?:(?:ähnlich|aehnlich|ahnlich)e?(?:\s+(?:filme?|serien?))?\s+(?:wie|zu)|wie|zu)\s+(.+)$/i);
    return found ? found[1] : null;
  };

  App.catalogSearch = function (items, rawQuery, options) {
    const settings = options || {};
    const all = items || [];
    const query = normalize(rawQuery);
    const similarQuery = App.parseSimilarQuery(rawQuery);
    let seed = settings.similarTo || null;
    if (!seed && similarQuery) {
      const candidates = all.map((item) => ({ item: item, score: searchScore(item, normalize(similarQuery)) }))
        .filter((entry) => entry.score >= 700).sort((a, b) => b.score - a.score);
      if (!candidates.length || candidates[1] && candidates[1].score === candidates[0].score &&
          titleKey(titleOf(candidates[1].item)) !== titleKey(titleOf(candidates[0].item))) return [];
      seed = candidates[0].item;
    }
    if (!query && !seed) return all.slice(0, settings.limit || all.length);
    return all.map((item, index) => ({ item: item, index: index, score: seed ? similarity(item, seed) : searchScore(item, query) }))
      .filter((entry) => entry.score > 0).sort((a, b) => b.score - a.score || a.index - b.index)
      .slice(0, settings.limit || all.length).map((entry) => entry.item);
  };
})(IpFlix);
