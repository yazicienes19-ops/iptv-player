// Gemeinsame Suche über die Playlist; IMDb-Daten bleiben eine getrennte Quelle.
'use strict';

(function (App) {
  const h = App.h;
  const TYPES = [
    { id: 'all', label: 'Alles' }, { id: 'movie', label: 'Filme' },
    { id: 'series', label: 'Serien' }, { id: 'live', label: 'Live TV' },
  ];
  const COLLECTIONS = [
    { id: 'discover', label: 'Entdecken' },
    { id: 'top', label: 'Höchstbewertet', rated: true },
    { id: 'crime', label: 'Krimi', genre: 'Crime', rated: true },
    { id: 'thriller', label: 'Thriller', genre: 'Thriller', rated: true },
    { id: 'scifi', label: 'Science-Fiction', genre: 'Sci-Fi', rated: true },
    { id: 'drama', label: 'Drama', genre: 'Drama', rated: true },
    { id: 'comedy', label: 'Komödie', genre: 'Comedy', rated: true },
  ];

  function SearchPanel(home) {
    this.home = home;
    this.type = 'all';
    this.collection = COLLECTIONS[0];
    this.items = [];
    this.ready = false;
    this.token = 0;
    this.failed = [];
    this.imdb = { available: false };
    this.title = h('h1.search-title', { text: 'Was möchtest du sehen?' });
    this.field = h('input.field.search-field', {
      type: 'search', placeholder: 'Titel, Genre oder „Filme wie …“',
      'aria-label': 'Filme, Serien und Sender durchsuchen', autocomplete: 'off', spellcheck: false,
    });
    this.clearButton = h('button.search-clear', {
      type: 'button', text: '×', 'aria-label': 'Suche löschen',
      onclick: () => { this.field.value = ''; this.search(); this.field.focus(); },
    });
    this.resultTitle = h('h2.search-results-title', { text: 'In deiner Mediathek' });
    this.resultCount = h('span.search-count');
    this.source = h('div.search-source');
    this.status = h('div.panel-status.search-status', { role: 'status', 'aria-live': 'polite' });
    this.retry = h('button.button.search-retry', { type: 'button', text: 'Erneut laden', onclick: () => this.start() });
    this.inputZone = {
      items: [1],
      setActive: (active) => this.field.classList.toggle('focused', active),
      onKey: (key) => {
        if (key === 'ok') { this.field.focus(); return true; }
        if (key === 'down') this.field.blur();
        return false;
      },
    };
    this.types = this.chips(TYPES, (choice) => {
      this.type = choice.id;
      if (this.type === 'series' || this.type === 'live') this.collection = COLLECTIONS[0];
      this.search();
    });
    this.collections = this.chips(COLLECTIONS, (choice) => {
      this.collection = choice;
      if (choice.rated) this.type = 'movie';
      this.search();
    });
    this.grid = new App.Grid({
      width: 12, height: 22, gap: 1.3,
      tile: (item) => this.tile(item),
      onActivate: (item) => App.openItem(item, this.grid.items),
      onPointer: () => home.zones.activate(this.grid, true),
      onSecondary: (item) => { App.toggleFavorite(item); this.refresh(); },
    });
    const gridKey = this.grid.onKey;
    this.grid.onKey = (key) => {
      if (key === 'info' && this.grid.current() && this.grid.current().kind !== 'live') {
        this.similar(this.grid.current()); return true;
      }
      return gridKey.call(this.grid, key);
    };
    const order = [this.inputZone, this.types, this.collections, this.grid];
    order.forEach((zone, i) => home.zones.add(zone, {
      left: () => home.sidebar, up: () => order[i - 1], down: () => order[i + 1],
    }));
    this.field.addEventListener('focus', () => home.zones.activate(this.inputZone, true));
    this.field.addEventListener('input', () => {
      // Auch das Leeren invalidiert bereits laufende Empfehlungen.
      this.token++;
      clearTimeout(this.timer);
      this.timer = setTimeout(() => this.search(), 180);
    });
    this.el = h('div.panel.search-panel', null, [
      h('div.search-header', null, [
        h('div.search-eyebrow', { text: 'DEINE NÄCHSTE ENTDECKUNG' }), this.title,
        h('div.search-input-wrap', null, [App.icon('search'), this.field, this.clearButton]),
        h('p.search-help', { text: 'Auch mit Tippfehlern. Oder suche nach „Filme wie Inception“.' }),
        this.types.el, this.collections.el,
      ]),
      h('div.search-result-head', null, [this.resultTitle, this.resultCount]),
      this.source,
      h('div.grid-box.search-results', null, [this.grid.el, this.status]), this.retry,
      h('a.metadata-credit', { href: 'https://www.imdb.com', target: '_blank', rel: 'noopener noreferrer', text: 'Information courtesy of IMDb (https://www.imdb.com). Used with permission.' }),
    ]);
    this.paintChips();
  }

  SearchPanel.prototype.chips = function (items, activate) {
    let row;
    row = new App.Row({
      className: 'search-chips',
      render: (choice, index) => h('button.search-chip', {
        type: 'button', text: choice.label,
        onfocus: () => { this.home.zones.activate(row, true); row.focusIndex(index, true); },
      }),
      onActivate: activate,
      onPointer: () => this.home.zones.activate(row, true),
    });
    row.setItems(items);
    return row;
  };

  SearchPanel.prototype.paintChips = function () {
    [[this.types, this.type], [this.collections, this.collection.id]].forEach((pair) => {
      pair[0].nodes.forEach((node, i) => {
        const active = pair[0].items[i].id === pair[1];
        node.classList.toggle('chosen', active);
        node.setAttribute('aria-pressed', String(active));
      });
    });
  };

  SearchPanel.prototype.entryZone = function () { return this.inputZone; };

  SearchPanel.prototype.start = function () {
    const token = this.loadToken = (this.loadToken || 0) + 1;
    this.ready = false;
    this.failed = [];
    this.items = [];
    this.setStatus('Deine Mediathek wird durchsucht …');
    this.retry.style.display = 'none';
    const provider = App.provider;
    const loads = ['movie', 'series', 'live'].map((kind) => Promise.all([
      provider.categories(kind), provider.allItems(kind),
    ]).then((data) => {
      const cats = {};
      data[0].forEach((cat) => { cats[cat.id] = cat.name; });
      return data[1].filter((item) => App.passesCountryFilter(cats[item.catId] || ''));
    }, () => { if (token === this.loadToken) this.failed.push(kind); return []; }));
    const metadata = App.imdbCatalog.load().then((info) => {
      if (token === this.loadToken) this.imdb = info;
    });
    return Promise.all(loads.concat([metadata])).then((lists) => {
      if (token !== this.loadToken || provider !== App.provider) return;
      this.items = [].concat(lists[0], lists[1], lists[2]);
      this.ready = true;
      this.search();
    });
  };

  SearchPanel.prototype.setStatus = function (text) {
    this.status.textContent = text;
    this.status.style.display = text ? '' : 'none';
  };

  SearchPanel.prototype.tile = function (item) {
    const imdb = App.imdbCatalog.match(item);
    const tile = App.tile(imdb ? Object.assign({}, item, { imdb: imdb }) : item);
    tile.classList.add('search-card');
    tile.appendChild(h('div.search-card-meta', { text: [imdb ? imdb.year : item.year, item.kind === 'series' ? 'Serie' : item.kind === 'live' ? 'Live TV' : 'Film'].filter(Boolean).join(' · ') }));
    if (item.kind !== 'live') tile.appendChild(h('button.similar-button', {
      type: 'button', text: '≈', title: 'Ähnliche Titel finden', 'aria-label': 'Ähnliche Titel wie ' + App.displayTitle(item),
      onclick: (event) => { event.stopPropagation(); this.similar(item); },
    }));
    return tile;
  };

  SearchPanel.prototype.similar = function (item) {
    this.type = item.kind === 'series' ? 'series' : 'movie';
    this.collection = COLLECTIONS[0];
    this.field.value = (item.kind === 'series' ? 'Serien wie ' : 'Filme wie ') + App.displayTitle(item);
    this.search(item);
    this.home.zones.activate(this.inputZone, true);
  };

  SearchPanel.prototype.search = function (seed) {
    const token = ++this.token;
    const query = this.field.value.trim();
    this.clearButton.style.display = query ? '' : 'none';
    this.paintChips();
    if (!this.ready) return;
    let pool = this.items.filter((item) => this.type === 'all' || item.kind === this.type);
    const similarQuery = App.parseSimilarQuery(query);
    const target = seed || (similarQuery ? App.catalogSearch(this.items, similarQuery, { limit: 1 })[0] : null);
    let source = '';
    if (this.collection.rated) {
      const ranked = App.rankedMovies(pool, this.collection.genre, { limit: 500 });
      pool = ranked.items;
      source = ranked.available
        ? 'IMDb-Nutzerbewertungen · mindestens ' + ranked.minVotes.toLocaleString('de-DE') + ' Stimmen · nur in deiner Playlist · Stand ' + String(ranked.generatedAt || '').slice(0, 10)
        : 'Für diese Auswahl fehlen die IMDb-Daten. Die normale Titelsuche funktioniert weiterhin.';
    }
    const results = query ? App.catalogSearch(pool, query, { limit: 150, similarTo: target }) : pool.slice(0, 150);
    this.resize();
    this.grid.setItems(results);
    this.resultTitle.textContent = similarQuery ? 'Ähnlich wie „' + similarQuery + '“' : query ? 'Ergebnisse für „' + query + '“'
      : this.collection.rated ? (this.collection.genre ? 'Die besten ' + this.collection.label + '-Filme deiner Playlist' : 'Die bestbewerteten Filme deiner Playlist') : 'In deiner Mediathek';
    this.resultCount.textContent = results.length ? results.length + (results.length === 150 ? '+' : '') + ' Titel' : '';
    this.source.textContent = source || (similarQuery ? 'Ähnlichkeit nach verfügbaren Genres und Filmdaten.' : 'Titel und Genres durchsuchen. ≈ findet ähnliche Filme und Serien.');
    this.setStatus(results.length ? '' : query ? 'Keine passenden Titel. Probiere einen kürzeren Titel oder ein anderes Genre.' : 'Keine passenden Titel in deiner Playlist.');
    this.retry.style.display = this.failed.length ? '' : 'none';
    if (this.failed.length) this.source.textContent += ' Ein Teil der Mediathek ist gerade nicht erreichbar.';

    // TMDB ergänzt ähnliche Titel nur bei eingerichteter Verbindung und nur,
    // wenn sie tatsächlich in der Playlist vorhanden sind.
    if (similarQuery && App.hasTmdb()) {
      if (!target || target.kind === 'live') return;
      App.tmdbFor(target).then((data) => data ? App.findInPlaylist(data.recommendations) : []).then((items) => {
        if (token !== this.token) return;
        const ids = {};
        const merged = items.concat(results).filter((item) => {
          if (!item || item.kind !== target.kind || (item.id === target.id && item.kind === target.kind)) return false;
          const key = item.kind + ':' + item.id;
          if (ids[key] || !pool.some((available) => available.id === item.id && available.kind === item.kind)) return false;
          ids[key] = true; return true;
        }).slice(0, 150);
        const current = this.grid.current();
        const keep = current ? merged.map((item) => item.kind + ':' + item.id).indexOf(current.kind + ':' + current.id) : 0;
        this.grid.setItems(merged, Math.max(0, keep));
        this.resultCount.textContent = merged.length ? merged.length + ' Titel' : '';
        if (merged.length) this.setStatus('');
        this.source.textContent = [source, 'TMDB-Empfehlungen und ähnliche Genres · nur Titel aus deiner Playlist', this.failed.length ? 'Ein Teil der Mediathek ist gerade nicht erreichbar.' : ''].filter(Boolean).join(' · ');
      }).catch(() => {});
    }
  };

  SearchPanel.prototype.refresh = function () {
    if (!this.ready) return;
    this.grid.nodes = {};
    App.clear(this.grid.inner);
    this.grid.render();
  };

  SearchPanel.prototype.resize = function () {
    const narrow = this.grid.el.clientWidth > 0 && this.grid.el.clientWidth < 500;
    this.grid.setLayout(this.type === 'live' ? App.LAYOUTS.live : narrow
      ? { width: 9, height: 17, gap: 1 }
      : { width: 12, height: 22, gap: 1.3 });
    this.grid.ensureVisible();
    this.grid.render();
  };

  App.SearchPanel = SearchPanel;
})(IpFlix);
