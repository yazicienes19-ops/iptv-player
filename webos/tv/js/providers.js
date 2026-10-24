// Datenquellen: Xtream Codes (player_api.php) und M3U-Listen.
// Einträge haben alle dieselbe Form:
//   { kind: 'live'|'movie'|'series'|'episode', id, name, logo, catId, ext, url? }
'use strict';

(function (App) {
  function text(value) {
    return typeof value === 'string' && value.trim() ? value.trim() : null;
  }

  function asList(data) {
    if (Array.isArray(data)) return data;
    // Manche Panels liefern ein Objekt mit numerischen Schlüsseln.
    if (data && typeof data === 'object') return Object.keys(data).map((k) => data[k]);
    return [];
  }

  function decodeBase64(value) {
    try {
      return decodeURIComponent(escape(atob(value || '')));
    } catch (e) {
      return value || '';
    }
  }

  function formatDuration(seconds, fallback) {
    const secs = parseInt(seconds, 10);
    if (!(secs > 0)) return text(fallback);
    const h = Math.floor(secs / 3600);
    const m = Math.floor((secs % 3600) / 60);
    return h > 0 ? h + ' Std. ' + m + ' Min.' : m + ' Min.';
  }

  // ---------- Xtream ----------

  function Xtream(account) {
    this.account = account;
    this.server = account.server.replace(/\/+$/, '');
    if (!/^https?:\/\//i.test(this.server)) this.server = 'http://' + this.server;
    this.cache = {};
  }

  Xtream.prototype.api = function (action, params) {
    let url =
      this.server +
      '/player_api.php?username=' +
      encodeURIComponent(this.account.username) +
      '&password=' +
      encodeURIComponent(this.account.password);
    if (action) url += '&action=' + action;
    Object.keys(params || {}).forEach((k) => {
      url += '&' + k + '=' + encodeURIComponent(params[k]);
    });
    return App.fetchJson(url, 90000);
  };

  Xtream.prototype.authenticate = function () {
    return this.api(null).then((data) => {
      const info = data && data.user_info;
      if (!info) throw new Error('Ungültige Antwort. Ist das ein Xtream-Codes-Server?');
      if (String(info.auth) !== '1') throw new Error('Benutzername oder Passwort falsch.');
      if (String(info.status).toLowerCase() !== 'active') throw new Error('Konto nicht aktiv (Status: ' + info.status + ').');
      return info;
    });
  };

  const CATEGORY_ACTIONS = { live: 'get_live_categories', movie: 'get_vod_categories', series: 'get_series_categories' };
  const STREAM_ACTIONS = { live: 'get_live_streams', movie: 'get_vod_streams', series: 'get_series' };

  Xtream.prototype.categories = function (section) {
    const key = 'cat:' + section;
    if (!this.cache[key]) {
      this.cache[key] = this.api(CATEGORY_ACTIONS[section]).then((data) =>
        asList(data).map((c) => ({ id: String(c.category_id), name: text(c.category_name) || 'Ohne Namen' }))
      );
      this.cache[key].catch(() => delete this.cache[key]);
    }
    return this.cache[key];
  };

  Xtream.prototype.items = function (section, categoryId) {
    const key = 'items:' + section + ':' + (categoryId || '*');
    if (!this.cache[key]) {
      const params = categoryId ? { category_id: categoryId } : {};
      this.cache[key] = this.api(STREAM_ACTIONS[section], params).then((data) => asList(data).map((json) => this.item(json, section)));
      this.cache[key].catch(() => delete this.cache[key]);
    }
    return this.cache[key];
  };

  Xtream.prototype.allItems = function (section) {
    return this.items(section, null);
  };

  Xtream.prototype.item = function (json, section) {
    const id = String(json.stream_id != null ? json.stream_id : json.series_id);
    return {
      kind: section,
      id: id,
      name: text(json.name) || 'Ohne Namen',
      logo: text(json.stream_icon) || text(json.cover),
      catId: json.category_id == null ? null : String(json.category_id),
      ext: text(json.container_extension) || 'mp4',
      rating: parseFloat(json.rating) || null,
      year: text(json.year) || (text(json.releaseDate) || '').slice(0, 4) || null,
      addedAt: json.added != null ? json.added : json.added_at,
      imdbId: text(json.imdb_id || json.imdb),
      genres: Array.isArray(json.genres) ? json.genres : text(json.genre),
      director: text(json.director),
      cast: text(json.cast || json.actors),
      num: json.num,
    };
  };

  Xtream.prototype.streamUrl = function (item) {
    const u = encodeURIComponent(this.account.username);
    const p = encodeURIComponent(this.account.password);
    if (item.kind === 'live') return this.server + '/live/' + u + '/' + p + '/' + item.id + '.' + App.settings.liveFormat;
    if (item.kind === 'movie') return this.server + '/movie/' + u + '/' + p + '/' + item.id + '.' + item.ext;
    if (item.kind === 'episode') return this.server + '/series/' + u + '/' + p + '/' + item.id + '.' + item.ext;
    return item.url || '';
  };

  Xtream.prototype.details = function (item) {
    if (item.kind === 'movie') {
      return this.api('get_vod_info', { vod_id: item.id }).then((data) => describe((data && data.info) || {}, item));
    }
    return this.api('get_series_info', { series_id: item.id }).then((data) => {
      const details = describe((data && data.info) || {}, item);
      const episodes = (data && data.episodes) || {};
      details.seasons = Object.keys(episodes)
        .map((season) => ({
          number: parseInt(season, 10) || 0,
          episodes: asList(episodes[season])
            .map((ep) => {
              const info = ep.info || {};
              const number = parseInt(ep.episode_num, 10) || 0;
              return {
                kind: 'episode',
                id: String(ep.id),
                ext: text(ep.container_extension) || 'mp4',
                number: number,
                season: parseInt(season, 10) || 0,
                name: text(ep.title) || 'Folge ' + number,
                plot: text(info.plot),
                duration: formatDuration(info.duration_secs, info.duration),
                logo: text(info.movie_image) || item.logo,
                seriesId: item.id,
                seriesName: item.name,
              };
            })
            .sort((a, b) => a.number - b.number),
        }))
        .sort((a, b) => a.number - b.number);
      return details;
    });
  };

  function describe(info, item) {
    const backdrops = info.backdrop_path;
    const release = text(info.releasedate || info.releaseDate || info.release_date) || '';
    return {
      plot: text(info.plot || info.description),
      genre: text(info.genre),
      year: release.slice(0, 4) || item.year,
      rating: parseFloat(info.rating) || item.rating,
      duration: formatDuration(info.duration_secs, info.duration),
      backdrop: Array.isArray(backdrops) ? text(backdrops[0]) : text(backdrops),
      poster: text(info.movie_image || info.cover_big || info.cover) || item.logo,
      cast: text(info.cast || info.actors),
      director: text(info.director),
      tmdbId: parseInt(info.tmdb_id || info.tmdb, 10) || null,
      imdbId: text(info.imdb_id || info.imdb) || item.imdbId,
      seasons: [],
    };
  }

  Xtream.prototype.shortEpg = function (item) {
    return this.api('get_short_epg', { stream_id: item.id, limit: 3 }).then((data) =>
      asList(data && data.epg_listings)
        .map((e) => ({
          title: decodeBase64(e.title),
          start: parseInt(e.start_timestamp, 10) * 1000,
          end: parseInt(e.stop_timestamp, 10) * 1000,
        }))
        .filter((e) => e.end > Date.now())
        .sort((a, b) => a.start - b.start)
    );
  };

  // ---------- M3U ----------

  function M3u(account) {
    this.account = account;
    this.loaded = null;
  }

  M3u.prototype.load = function () {
    if (!this.loaded) {
      this.loaded = App.fetchText(this.account.url, 180000).then(parseM3u);
      this.loaded.catch(() => (this.loaded = null));
    }
    return this.loaded;
  };

  M3u.prototype.authenticate = function () {
    return this.load().then((data) => {
      if (!data.live.items.length && !data.movie.items.length && !data.series.items.length) {
        throw new Error('Die Playlist enthält keine Einträge. Ist es wirklich eine M3U-Liste?');
      }
      return null;
    });
  };

  M3u.prototype.categories = function (section) {
    return this.load().then((data) => data[section].categories);
  };

  M3u.prototype.items = function (section, categoryId) {
    return this.load().then((data) => data[section].items.filter((i) => !categoryId || i.catId === categoryId));
  };

  M3u.prototype.allItems = function (section) {
    return this.items(section, null);
  };

  M3u.prototype.streamUrl = function (item) {
    return item.url;
  };

  M3u.prototype.details = function (item) {
    return Promise.resolve({ poster: item.logo, seasons: [] });
  };

  M3u.prototype.shortEpg = function () {
    return Promise.resolve([]);
  };

  function parseM3u(content) {
    const sections = { live: newSection(), movie: newSection(), series: newSection() };
    const attr = /([\w-]+)="([^"]*)"/g;
    let pending = null;
    let extGroup = null;
    let counter = 0;
    content.split(/\r?\n/).forEach((raw) => {
      const line = raw.trim();
      if (!line) return;
      if (line.indexOf('#EXTINF') === 0) {
        const attrs = {};
        let m;
        attr.lastIndex = 0;
        while ((m = attr.exec(line))) attrs[m[1].toLowerCase()] = m[2];
        pending = { name: m3uTitle(line) || attrs['tvg-name'] || 'Ohne Namen', attrs: attrs };
        extGroup = null;
        return;
      }
      if (line.indexOf('#EXTGRP:') === 0) {
        extGroup = line.slice(8).trim();
        return;
      }
      if (line.charAt(0) === '#' || !pending) return;
      // Serien in M3U-Listen sind einzelne Folgen; sie werden direkt abgespielt.
      const group = pending.attrs['group-title'] || extGroup || 'Ohne Kategorie';
      const section = m3uSection(line, group);
      const target = sections[section];
      if (!target.byName[group]) {
        target.byName[group] = String(target.categories.length + 1);
        target.categories.push({ id: target.byName[group], name: group });
      }
      target.items.push({
        kind: section === 'live' ? 'live' : 'movie',
        id: 'm' + counter++,
        name: pending.name,
        logo: pending.attrs['tvg-logo'] || null,
        catId: target.byName[group],
        url: line,
      });
      pending = null;
    });
    return sections;
  }

  function m3uTitle(line) {
    let inQuotes = false;
    for (let i = 0; i < line.length; i++) {
      if (line.charAt(i) === '"') inQuotes = !inQuotes;
      else if (line.charAt(i) === ',' && !inQuotes) return line.slice(i + 1).trim();
    }
    return '';
  }

  function m3uSection(address, group) {
    const lower = address.toLowerCase();
    if (lower.indexOf('/series/') >= 0) return 'series';
    if (lower.indexOf('/movie/') >= 0) return 'movie';
    const category = group.toLowerCase();
    if (!/^[^?#]*\.(mp4|mkv|avi|mov|m4v|wmv|flv|webm|ogv|mpg|mpeg|m2ts|vob)([?#]|$)/.test(lower) && !/\bvod\b/.test(category)) return 'live';
    return category.indexOf('serie') >= 0 ? 'series' : 'movie';
  }

  function newSection() {
    return { categories: [], items: [], byName: {} };
  }

  App.createProvider = function (account) {
    return account.type === 'm3u' ? new M3u(account) : new Xtream(account);
  };
})(IpFlix);
