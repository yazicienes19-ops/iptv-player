// Favoriten, zuletzt gesehene Sender und Wiedergabe-Fortschritt (localStorage).
'use strict';

(function (App) {
  const legacyAccount = App.load('account', null);
  const libraries = Object.create(null);

  function library(scope) {
    const key = scope || App.libraryScope();
    if (!libraries[key]) {
      const favorites = App.load('favorites.' + key, []);
      const recent = App.load('recent.' + key, []);
      const progress = App.load('progress.' + key, {});
      libraries[key] = {
        favorites: Array.isArray(favorites) ? favorites : [],
        recent: Array.isArray(recent) ? recent : [],
        progress: progress && typeof progress === 'object' && !Array.isArray(progress) ? progress : {},
      };
    }
    return libraries[key];
  }

  // Nur was zum Anzeigen und Abspielen nötig ist, ohne Zwischenstände.
  function slim(item) {
    const copy = {};
    ['kind', 'id', 'name', 'logo', 'catId', 'ext', 'url', 'rating', 'year', 'number', 'season', 'seriesId', 'seriesName',
      'imdbId', 'genres', 'cast', 'director'].forEach((k) => {
      if (item[k] != null) copy[k] = item[k];
    });
    return copy;
  }

  // ---------- Favoriten ----------

  App.isFavorite = function (item, scope) {
    const key = personalKey(item);
    return library(scope).favorites.some((f) => personalKey(f) === key);
  };

  App.toggleFavorite = function (item, scope) {
    const key = personalKey(item);
    const data = library(scope);
    const had = App.isFavorite(item, scope);
    data.favorites = had ? data.favorites.filter((f) => personalKey(f) !== key) : [slim(item)].concat(data.favorites);
    App.save('favorites.' + (scope || App.libraryScope()), data.favorites);
    App.toast(had ? 'Aus Favoriten entfernt' : 'Zu Favoriten hinzugefügt');
    return !had;
  };

  App.favorites = function (kind, scope) {
    return library(scope).favorites.filter((f) => f.kind === kind);
  };

  // A user can favorite a title before its detail request finishes. Enrich the
  // saved item afterwards without removing/re-adding it or changing list order.
  App.rememberFavoriteMetadata = function (item, scope) {
    const data = library(scope);
    const key = personalKey(item);
    const canonical = App.catalogIdentity ? App.catalogIdentity(item) : null;
    let changed = false;
    data.favorites.forEach((favorite) => {
      if (personalKey(favorite) !== key && !(canonical && App.catalogIdentity(favorite) === canonical)) return;
      ['imdbId', 'year', 'genres', 'cast', 'director'].forEach((name) => {
        const value = item[name];
        if (value == null || value === '' || Array.isArray(value) && !value.length) return;
        if (JSON.stringify(favorite[name]) === JSON.stringify(value)) return;
        favorite[name] = value;
        changed = true;
      });
    });
    if (changed) App.save('favorites.' + (scope || App.libraryScope()), data.favorites);
  };

  // ---------- Zuletzt gesehen (Live) ----------

  App.addRecent = function (item, scope) {
    const key = personalKey(item);
    const data = library(scope);
    data.recent = [slim(item)].concat(data.recent.filter((r) => personalKey(r) !== key)).slice(0, 40);
    App.save('recent.' + (scope || App.libraryScope()), data.recent);
  };

  App.recent = function (scope) {
    return library(scope).recent;
  };

  // ---------- Persönliche Startseite (pro Playlist) ----------

  const DAY = 24 * 60 * 60 * 1000;
  const personal = Object.create(null);

  // Keine Server-Adressen oder Zugangsdaten in Speicherschlüsseln ablegen.
  // Zwei unabhängige 32-Bit-Hashes trennen Playlists und M3U-Adressen stabil.
  function fingerprint(value) {
    const text = String(value || '');
    let a = 2166136261;
    let b = 5381;
    for (let i = 0; i < text.length; i++) {
      a = Math.imul(a ^ text.charCodeAt(i), 16777619);
      b = Math.imul(b, 33) ^ text.charCodeAt(i);
    }
    return (a >>> 0).toString(16) + '-' + (b >>> 0).toString(16);
  }

  App.libraryScope = function (provider) {
    const account = (provider || App.provider || {}).account || App.load('account', {});
    return fingerprint(account.type === 'm3u' ? 'm3u:' + account.url
      : 'xtream:' + String(account.server || '').replace(/\/+$/, '') + ':' + (account.username || ''));
  };

  function personalKey(item) {
    // M3U-IDs enthalten eine laufende Nummer und ändern sich beim Umsortieren.
    return item.kind + ':' + fingerprint(item.url || item.id);
  }

  App.libraryItemKey = personalKey;

  // Old versions had one history for the saved login. Capture that login before
  // startWith or a later sign-in can change it; never adopt it for another user.
  // Unowned legacy data remains untouched and cannot be adopted on a later boot.
  if (App.load('library-legacy-owner', null) == null) {
    if (legacyAccount) {
      const owner = App.libraryScope({ account: legacyAccount });
      ['favorites', 'recent'].forEach((name) => {
        if (App.load(name + '.' + owner, null) == null) {
          const old = App.load(name, []);
          App.save(name + '.' + owner, Array.isArray(old) ? old : []);
        }
      });
      if (App.load('progress.' + owner, null) == null) {
        const old = App.load('progress', {});
        const migrated = {};
        Object.keys(old || {}).forEach((key) => {
          const entry = old[key];
          if (entry && entry.item) migrated[personalKey(entry.item)] = entry;
        });
        App.save('progress.' + owner, migrated);
      }
      App.save('library-legacy-owner', owner);
    } else App.save('library-legacy-owner', 'unassigned');
  }

  function personalState(scope) {
    const key = scope || App.libraryScope();
    if (!personal[key]) {
      const data = App.load('personal.' + key, null);
      const valid = data && data.version === 1 && data.movies && typeof data.movies === 'object' && !Array.isArray(data.movies);
      const watched = App.load('personal-watch.' + key, null) || (data && data.watched);
      personal[key] = {
        version: 1,
        watched: watched && typeof watched === 'object' && !Array.isArray(watched) ? watched : {},
        movies: valid ? data.movies : {}, initialized: valid ? !!data.initialized : false,
      };
    }
    return personal[key];
  }

  function savePersonal(scope) {
    const key = scope || App.libraryScope();
    const state = personalState(key);
    App.save('personal.' + key, { version: 1, movies: state.movies, initialized: state.initialized });
  }

  App.recordLiveWatch = function (item, seconds, scope) {
    if (!item || item.kind !== 'live' || !Number.isFinite(seconds) || seconds <= 0) return;
    const state = personalState(scope);
    const key = personalKey(item);
    const old = state.watched[key] || {};
    state.watched[key] = { seconds: (Number(old.seconds) || 0) + seconds, at: Date.now() };
    // Sehzeit häufig, große Filmlisten dagegen nur bei Katalogänderungen sichern.
    App.save('personal-watch.' + (scope || App.libraryScope()), state.watched);
  };

  App.mostWatched = function (available, limit, scope) {
    const watched = personalState(scope).watched;
    const seen = Object.create(null);
    return (available || []).filter((item) => {
      const key = personalKey(item);
      if (item.kind !== 'live' || seen[key] || !watched[key] || !(watched[key].seconds >= 30)) return false;
      seen[key] = true;
      return true;
    }).sort((a, b) => {
      const first = watched[personalKey(a)];
      const second = watched[personalKey(b)];
      return second.seconds - first.seconds || second.at - first.at || String(a.name).localeCompare(String(b.name));
    }).slice(0, limit || 20);
  };

  App.addedTimestamp = function (value, now) {
    if (value == null || value === '') return null;
    const number = Number(value);
    const time = Number.isFinite(number) ? (number < 100000000000 ? number * 1000 : number) : Date.parse(String(value));
    return Number.isFinite(time) && time >= 946684800000 && time <= (now || Date.now()) ? time : null;
  };

  // Nur nach einem vollständig erfolgreichen Katalogabruf aufrufen. Filter
  // dürfen die Vergleichsbasis nicht verändern oder alte Titel zu neuen machen.
  App.observeMovieCatalog = function (items, scope, now) {
    const time = now || Date.now();
    const state = personalState(scope);
    const next = {};
    let changed = !state.initialized;
    (items || []).forEach((item) => {
      if (item.kind !== 'movie') return;
      const key = personalKey(item);
      if (next[key]) return;
      const old = state.movies[key];
      if (!old) changed = true;
      next[key] = old || { firstSeen: state.initialized ? time : null };
    });
    if (Object.keys(state.movies).length !== Object.keys(next).length) changed = true;
    state.movies = next;
    state.initialized = true;
    if (changed) savePersonal(scope);
  };

  App.newMovies = function (available, limit, scope, now) {
    const time = now || Date.now();
    const state = personalState(scope);
    const seen = Object.create(null);
    return (available || []).map((item) => {
      const key = personalKey(item);
      if (item.kind !== 'movie' || seen[key]) return null;
      seen[key] = true;
      const added = App.addedTimestamp(item.addedAt, time);
      const entry = state.movies[key];
      const firstSeen = entry && entry.firstSeen;
      const date = added || firstSeen;
      if (!date || date < time - 30 * DAY || date > time) return null;
      return { item: item, date: date };
    }).filter(Boolean).sort((a, b) => b.date - a.date || String(a.item.name).localeCompare(String(b.item.name)))
      .slice(0, limit || 20).map((entry) => entry.item);
  };

  // ---------- Fortschritt (Filme und Folgen) ----------

  App.saveProgress = function (item, position, duration, scope) {
    if (!(duration > 0)) return;
    const progress = library(scope).progress;
    const key = personalKey(item);
    // Fast fertig gilt als gesehen (Abspann: letzte 2 Minuten bei langen Titeln).
    if (position > duration * 0.95 || (duration > 1200 && duration - position < 120)) {
      progress[key] = { done: true, at: Date.now(), item: slim(item) };
    } else if (position > 30) {
      progress[key] = { pos: position, dur: duration, at: Date.now(), item: slim(item) };
    }
    App.save('progress.' + (scope || App.libraryScope()), progress);
  };

  App.clearProgress = function (item, scope) {
    const progress = library(scope).progress;
    delete progress[personalKey(item)];
    App.save('progress.' + (scope || App.libraryScope()), progress);
  };

  App.resumePosition = function (item, scope) {
    const entry = library(scope).progress[personalKey(item)];
    return entry && !entry.done ? entry.pos : 0;
  };

  App.progressOf = function (item, scope) {
    const entry = library(scope).progress[personalKey(item)];
    if (!entry) return 0;
    return entry.done ? 1 : entry.pos / entry.dur;
  };

  /// Angefangene Filme bzw. Folgen, neueste zuerst.
  App.continueWatching = function (kind, scope) {
    const progress = library(scope).progress;
    return Object.keys(progress)
      .map((k) => progress[k])
      .filter((p) => !p.done && p.item.kind === kind)
      .sort((a, b) => b.at - a.at)
      .map((p) => p.item);
  };

  /// Zuletzt gesehene Folge einer Serie (für „Weiterschauen“ auf der Serienseite).
  App.lastEpisodeOf = function (seriesId, scope) {
    const progress = library(scope).progress;
    let best = null;
    Object.keys(progress).forEach((k) => {
      const p = progress[k];
      if (p.item.kind === 'episode' && p.item.seriesId === seriesId && (!best || p.at > best.at)) best = p;
    });
    return best;
  };
})(IpFlix);
