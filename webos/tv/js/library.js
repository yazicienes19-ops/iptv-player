// Favoriten, zuletzt gesehene Sender und Wiedergabe-Fortschritt (localStorage).
'use strict';

(function (App) {
  function keyOf(item) {
    return item.kind + ':' + item.id;
  }

  // Nur was zum Anzeigen und Abspielen nötig ist, ohne Zwischenstände.
  function slim(item) {
    const copy = {};
    ['kind', 'id', 'name', 'logo', 'catId', 'ext', 'url', 'rating', 'year', 'number', 'season', 'seriesId', 'seriesName'].forEach((k) => {
      if (item[k] != null) copy[k] = item[k];
    });
    return copy;
  }

  // ---------- Favoriten ----------

  let favorites = App.load('favorites', []);

  App.isFavorite = function (item) {
    const key = keyOf(item);
    return favorites.some((f) => keyOf(f) === key);
  };

  App.toggleFavorite = function (item) {
    const key = keyOf(item);
    const had = App.isFavorite(item);
    favorites = had ? favorites.filter((f) => keyOf(f) !== key) : [slim(item)].concat(favorites);
    App.save('favorites', favorites);
    App.toast(had ? 'Aus Favoriten entfernt' : 'Zu Favoriten hinzugefügt');
    return !had;
  };

  App.favorites = function (kind) {
    return favorites.filter((f) => f.kind === kind);
  };

  // ---------- Zuletzt gesehen (Live) ----------

  App.addRecent = function (item) {
    const key = keyOf(item);
    const list = [slim(item)].concat(App.load('recent', []).filter((r) => keyOf(r) !== key)).slice(0, 40);
    App.save('recent', list);
  };

  App.recent = function () {
    return App.load('recent', []);
  };

  // ---------- Fortschritt (Filme und Folgen) ----------

  let progress = App.load('progress', {});

  App.saveProgress = function (item, position, duration) {
    if (!(duration > 0)) return;
    const key = keyOf(item);
    // Fast fertig gilt als gesehen (Abspann: letzte 2 Minuten bei langen Titeln).
    if (position > duration * 0.95 || (duration > 1200 && duration - position < 120)) {
      progress[key] = { done: true, at: Date.now(), item: slim(item) };
    } else if (position > 30) {
      progress[key] = { pos: position, dur: duration, at: Date.now(), item: slim(item) };
    }
    App.save('progress', progress);
  };

  App.clearProgress = function (item) {
    delete progress[keyOf(item)];
    App.save('progress', progress);
  };

  App.resumePosition = function (item) {
    const entry = progress[keyOf(item)];
    return entry && !entry.done ? entry.pos : 0;
  };

  App.progressOf = function (item) {
    const entry = progress[keyOf(item)];
    if (!entry) return 0;
    return entry.done ? 1 : entry.pos / entry.dur;
  };

  /// Angefangene Filme bzw. Folgen, neueste zuerst.
  App.continueWatching = function (kind) {
    return Object.keys(progress)
      .map((k) => progress[k])
      .filter((p) => !p.done && p.item.kind === kind)
      .sort((a, b) => b.at - a.at)
      .map((p) => p.item);
  };

  /// Zuletzt gesehene Folge einer Serie (für „Weiterschauen“ auf der Serienseite).
  App.lastEpisodeOf = function (seriesId) {
    let best = null;
    Object.keys(progress).forEach((k) => {
      const p = progress[k];
      if (p.item.kind === 'episode' && p.item.seriesId === seriesId && (!best || p.at > best.at)) best = p;
    });
    return best;
  };
})(IpFlix);
