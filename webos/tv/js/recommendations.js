// Persönliche Empfehlungen: lokal, pro Playlist und ohne geratenen Filminhalt.
'use strict';

(function (App) {
  const states = Object.create(null);

  function state(scope) {
    const key = scope || App.libraryScope();
    if (!states[key]) {
      const feedback = App.load('feedback.' + key, {});
      const viewing = App.load('vod-watch.' + key, {});
      states[key] = {
        feedback: feedback && typeof feedback === 'object' && !Array.isArray(feedback) ? feedback : {},
        viewing: viewing && typeof viewing === 'object' && !Array.isArray(viewing) ? viewing : {},
      };
    }
    return states[key];
  }

  function identity(item) {
    return App.catalogIdentity ? App.catalogIdentity(item) : null;
  }

  function keyOf(item) { return App.libraryItemKey(item); }
  function isVod(item) { return item && (item.kind === 'movie' || item.kind === 'series' || item.kind === 'episode'); }
  function titleSnapshot(item) {
    const result = { kind: item.kind, name: item.name || item.title || '' };
    ['year', 'imdbId', 'imdb_id'].forEach((name) => { if (item[name] != null) result[name] = item[name]; });
    return result;
  }
  function entryIdentity(entry) {
    return entry && (entry.identity || entry.item && identity(entry.item)) || null;
  }
  function same(entry, key, canonical, ownKey) {
    return ownKey === key || !!canonical && entryIdentity(entry) === canonical;
  }

  function feedbackIndex(records) {
    const result = Object.create(null);
    Object.keys(records).forEach((key) => {
      const entry = records[key];
      if (!entry || entry.value !== 'like' && entry.value !== 'dislike') return;
      result[key] = entry;
      const canonical = entryIdentity(entry);
      if (canonical && (!result[canonical] || entry.at >= result[canonical].at)) result[canonical] = entry;
    });
    return result;
  }

  function findFeedback(index, key, canonical) {
    const direct = index[key];
    const matched = canonical && index[canonical];
    return matched && (!direct || matched.at >= direct.at) ? matched : direct;
  }

  App.feedbackOf = function (item, scope) {
    if (!isVod(item)) return null;
    const feedback = state(scope).feedback;
    const key = keyOf(item);
    const canonical = identity(item);
    let latest = null;
    Object.keys(feedback).forEach((storedKey) => {
      const entry = feedback[storedKey];
      if (entry && (entry.value === 'like' || entry.value === 'dislike') && same(entry, key, canonical, storedKey) &&
          (!latest || entry.at >= latest.at)) latest = entry;
    });
    return latest ? latest.value : null;
  };

  // Setting a selected choice to null explicitly undoes it. UI controls decide
  // when a repeated click should toggle; this API always sets the given value.
  App.setFeedback = function (item, value, scope) {
    if (!isVod(item) || value != null && value !== 'like' && value !== 'dislike') return App.feedbackOf(item, scope);
    const feedback = state(scope).feedback;
    const key = keyOf(item);
    const canonical = identity(item);
    Object.keys(feedback).forEach((storedKey) => {
      if (same(feedback[storedKey], key, canonical, storedKey)) delete feedback[storedKey];
    });
    if (value) feedback[key] = {
      value: value, identity: canonical, item: titleSnapshot(item), features: features(item), at: Date.now(),
    };
    App.save('feedback.' + (scope || App.libraryScope()), feedback);
    return value || null;
  };

  // A like/play/favorite may precede the asynchronous detail response. Keep
  // those known facts after reload, without creating or renewing a preference.
  App.rememberRecommendationMetadata = function (item, scope) {
    if (!isVod(item)) return;
    const data = state(scope);
    const key = keyOf(item);
    const canonical = identity(item);
    const details = features(item);
    const snapshot = titleSnapshot(item);
    [['feedback', 'feedback.'], ['viewing', 'vod-watch.']].forEach((pair) => {
      const entries = data[pair[0]];
      let changed = false;
      Object.keys(entries).forEach((storedKey) => {
        const entry = entries[storedKey];
        if (!entry || !same(entry, key, canonical, storedKey)) return;
        const before = JSON.stringify(entry);
        const merged = Object.assign({}, entry.features || {});
        ['genres', 'cast', 'director'].forEach((name) => {
          if (details[name].length) merged[name] = details[name];
        });
        if (details.identity) merged.identity = details.identity;
        if (details.year) merged.year = details.year;
        if (details.title) merged.title = details.title;
        entry.features = merged;
        entry.item = Object.assign({}, entry.item || {}, snapshot);
        if (canonical) entry.identity = canonical;
        if (JSON.stringify(entry) !== before) changed = true;
      });
      if (changed) App.save(pair[1] + (scope || App.libraryScope()), entries);
    });
    if (App.rememberFavoriteMetadata) App.rememberFavoriteMetadata(item, scope);
  };

  function addViewing(viewing, item, seconds, duration, position, series) {
    const key = keyOf(item);
    const old = viewing[key] || {};
    const total = Math.max(0, Number(old.seconds) || 0) + seconds;
    const length = Number.isFinite(duration) && duration > 0 ? duration : Number(old.duration) || 0;
    viewing[key] = {
      seconds: total, duration: length, at: Date.now(), identity: identity(item), item: titleSnapshot(item),
      features: features(item),
      completed: !series && (!!old.completed || length > 0 && total >= length * 0.8 && position >= length * 0.9),
    };
  }

  // Only the player supplies elapsed, advancing playback. Position alone (or
  // a seek to the credits) can never become a positive recommendation signal.
  App.recordVodWatch = function (item, seconds, duration, position, scope) {
    if (!isVod(item) || item.kind === 'series' || !Number.isFinite(seconds) || seconds <= 0) return;
    const viewing = state(scope).viewing;
    addViewing(viewing, item, seconds, duration, position, false);
    if (item.kind === 'episode' && item.seriesId != null) {
      addViewing(viewing, { kind: 'series', id: item.seriesId, name: item.seriesName || '' }, seconds, 0, 0, true);
    }
    App.save('vod-watch.' + (scope || App.libraryScope()), viewing);
  };

  App.vodWatchOf = function (item, scope) {
    const viewing = state(scope).viewing;
    const key = keyOf(item);
    const canonical = identity(item);
    const total = { seconds: 0, duration: 0, completed: false, at: 0 };
    Object.keys(viewing).forEach((storedKey) => {
      const entry = viewing[storedKey];
      if (!entry || !same(entry, key, canonical, storedKey)) return;
      total.seconds += Math.max(0, Number(entry.seconds) || 0);
      total.duration = Math.max(total.duration, Number(entry.duration) || 0);
      total.completed = total.completed || !!entry.completed;
      total.at = Math.max(total.at, Number(entry.at) || 0);
    });
    return total;
  };

  function viewingIndex(records) {
    const result = Object.create(null);
    Object.keys(records).forEach((key) => {
      const entry = records[key];
      if (!entry) return;
      result[key] = entry;
      const canonical = entryIdentity(entry);
      if (canonical) {
        const total = result[canonical] || { seconds: 0, duration: 0, completed: false, at: 0 };
        total.seconds += Math.max(0, Number(entry.seconds) || 0);
        total.duration = Math.max(total.duration, Number(entry.duration) || 0);
        total.completed = total.completed || !!entry.completed;
        total.at = Math.max(total.at, Number(entry.at) || 0);
        if (entry.features) total.features = entry.features;
        result[canonical] = total;
      }
    });
    return result;
  }

  function features(item) {
    const found = App.catalogFeatures ? App.catalogFeatures(item) : {};
    return {
      identity: found.identity || null,
      genres: found.genres || [], cast: found.cast || [], director: found.director || [],
      year: found.year || null, title: found.title || item.name || '',
    };
  }

  function addWeights(target, values, weight) {
    values.forEach((value) => { if (value) target[value] = (target[value] || 0) + weight / values.length; });
  }

  function affinity(values, profile) {
    if (!values.length) return 0;
    return values.reduce((sum, value) => sum + (profile[value] || 0), 0) / Math.sqrt(values.length);
  }

  App.recommendations = function (available, options) {
    const settings = options || {};
    const scope = settings.scope || App.libraryScope();
    const limit = Math.max(0, settings.limit == null ? 20 : settings.limit);
    const seen = Object.create(null);
    const rows = [];
    const data = state(scope);
    const feedbackByKey = feedbackIndex(data.feedback);
    const viewedByKey = viewingIndex(data.viewing);
    const favorites = Object.create(null);
    ['movie', 'series'].forEach((kind) => App.favorites(kind, scope).forEach((item) => {
      favorites[keyOf(item)] = features(item);
      const canonical = identity(item);
      if (canonical) favorites[canonical] = favorites[keyOf(item)];
    }));
    const profile = { genres: Object.create(null), cast: Object.create(null), director: Object.create(null) };
    let seedCount = 0;
    let signalCount = 0;
    (available || []).forEach((item, index) => {
      if (!item || item.kind !== 'movie' && item.kind !== 'series') return;
      const info = features(item);
      const itemKey = keyOf(item);
      const key = info.identity || itemKey;
      if (seen[key]) return;
      seen[key] = true;
      const response = findFeedback(feedbackByKey, itemKey, info.identity);
      const feedback = response ? response.value : null;
      const viewed = viewedByKey[key] || viewedByKey[itemKey] || { seconds: 0, duration: 0, completed: false };
      const favoriteFeatures = favorites[itemKey] || favorites[key];
      [response && response.features, viewed.features, favoriteFeatures].forEach((snapshot) => {
        if (!snapshot) return;
        ['genres', 'cast', 'director'].forEach((name) => {
          if (!info[name].length && Array.isArray(snapshot[name])) info[name] = snapshot[name];
        });
      });
      const favorite = !!favoriteFeatures;
      const enough = viewed.seconds >= Math.min(600, Math.max(30, viewed.duration * 0.2));
      const weight = feedback === 'dislike' ? 0 : feedback === 'like' ? 6 : favorite ? 3 : enough ? 2 : 0;
      if (weight) {
        signalCount++;
        if (info.genres.length || info.cast.length || info.director.length) {
          seedCount++;
          addWeights(profile.genres, info.genres, weight);
          addWeights(profile.cast, info.cast, weight);
          addWeights(profile.director, info.director, weight);
        }
      }
      if (feedback !== 'dislike' && !weight && !viewed.completed) {
        rows.push({ item: item, info: info, index: index, viewed: viewed, score: 0 });
      }
    });
    rows.forEach((row) => {
      row.score = affinity(row.info.genres, profile.genres) * 30 + affinity(row.info.cast, profile.cast) * 20 +
        affinity(row.info.director, profile.director) * 60;
      // Titles already sampled stay available but lose some priority.
      if (row.viewed.seconds >= 30) row.score *= 0.5;
    });
    const personalized = seedCount > 0 && rows.some((row) => row.score > 0);
    let pool = personalized ? rows.filter((row) => row.score > 0) : rows;
    // A balanced starter list is explicitly labeled as such by the returned
    // reason. A global IMDb rating is never presented as personal confidence.
    pool = pool.slice().sort((a, b) => b.score - a.score || a.index - b.index);
    const chosen = [];
    const genresUsed = Object.create(null);
    const kindsUsed = Object.create(null);
    const categoriesUsed = Object.create(null);
    while (pool.length && chosen.length < limit) {
      let best = 0;
      let bestScore = -Infinity;
      pool.forEach((row, index) => {
        const repeated = row.info.genres.reduce((sum, genre) => sum + (genresUsed[genre] || 0), 0);
        const category = row.item.kind + ':' + (row.item.catId == null ? '' : row.item.catId);
        const groupRepeats = (kindsUsed[row.item.kind] || 0) + (categoriesUsed[category] || 0);
        const known = row.info.genres.length || row.info.cast.length || row.info.director.length;
        const base = personalized ? row.score : known ? 1.1 : 1;
        const score = base / (1 + repeated * 0.25 + (personalized ? 0 : groupRepeats * 0.5));
        if (score > bestScore) { best = index; bestScore = score; }
      });
      const selected = pool.splice(best, 1)[0];
      chosen.push(selected.item);
      selected.info.genres.forEach((genre) => { genresUsed[genre] = (genresUsed[genre] || 0) + 1; });
      kindsUsed[selected.item.kind] = (kindsUsed[selected.item.kind] || 0) + 1;
      const category = selected.item.kind + ':' + (selected.item.catId == null ? '' : selected.item.catId);
      categoriesUsed[category] = (categoriesUsed[category] || 0) + 1;
    }
    return {
      items: chosen, personalized: personalized, seedCount: seedCount,
      reason: personalized ? 'Passend zu deinen Bewertungen, deiner Liste und angesehenen Titeln' :
        signalCount ? 'Noch keine passenden Filminformationen gefunden. Entdecke weitere Titel aus deiner Liste.' :
          'Zum Entdecken – mit „Gefällt mir“ werden die Vorschläge persönlicher',
    };
  };
})(IpFlix);
