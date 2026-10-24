// Startseite mit echten Inhalten der Playlist. Kleine, begrenzte Ausschnitte
// halten auch große Anbieterlisten auf älteren Fernsehern benutzbar.
'use strict';

(function (App) {
  const h = App.h;
  const LIMIT = 16;

  function keyOf(item) {
    return item ? item.kind + ':' + item.id : '';
  }

  function unique(items) {
    const seen = {};
    const result = [];
    for (let i = 0; i < items.length && result.length < LIMIT; i++) {
      const item = items[i];
      const key = keyOf(item);
      if (!item || seen[key]) continue;
      seen[key] = true;
      result.push(item);
    }
    return result;
  }

  function sampleCategories(categories) {
    const seen = {};
    const items = [];
    let index = 0;
    let more = true;
    // Abwechselnd aus den geladenen Kategorien wählen, damit auch die zweite
    // vertreten ist. Große Listen nicht erst vollständig zusammenkopieren.
    while (more && items.length < LIMIT) {
      more = false;
      for (let i = 0; i < categories.length && items.length < LIMIT; i++) {
        const list = categories[i].items;
        if (index >= list.length) continue;
        more = true;
        const item = list[index];
        const key = keyOf(item);
        if (!item || seen[key]) continue;
        seen[key] = true;
        items.push(item);
      }
      index++;
    }
    return items;
  }

  function DiscoverPanel(home) {
    this.home = home;
    this.loadToken = 0;
    this.heroItem = null;
    this.heroDetails = {};
    this.artUrl = null;
    this.actionState = null;
    this.sections = {};
    this.order = [];
    this.liveCatalog = [];
    this.movieCatalog = [];
    this.seriesCatalog = [];
    this.art = h('div.discover-art');
    this.eyebrow = h('div.discover-eyebrow', { text: 'DEINE MEDIATHEK' });
    this.title = h('h1.discover-title', { text: 'Entdecke dein Programm.' });
    this.meta = h('div.discover-meta');
    this.plot = h('p.discover-plot', { text: 'Filme, Serien und Live-TV aus deiner Playlist.' });
    this.actions = new App.Row({
      className: 'discover-actions',
      scrollContainer: () => this.el,
      render: (action) => h('button.button' + (action.primary ? '.primary' : ''), { type: 'button' }, [
        action.icon ? App.icon(action.icon) : null,
        h('span', { text: action.label }),
      ]),
      onActivate: (action) => action.run(),
      onPointer: () => home.zones.activate(this.actions, true),
    });
    this.hero = h('div.discover-hero', null, [
      this.art,
      h('div.discover-shade'),
      h('div.discover-copy', null, [this.eyebrow, this.title, this.meta, this.plot, this.actions.el]),
    ]);
    this.el = h('div.panel.discover', null, [this.hero]);
    this.order.push(this.actions);
    this.addSection('continue', 'Weiterschauen', true);
    this.addSection('recommended', 'Für dich empfohlen');
    this.addSection('most-watched', 'Deine meistgesehenen Sender', true);
    this.addSection('new-movies', 'Neu in deiner Liste');
    this.addSection('movie', 'Filme entdecken');
    this.addSection('imdb-top', 'Bestbewertete Filme · IMDb');
    this.addSection('imdb-crime', 'Die besten Krimis · IMDb');
    this.addSection('imdb-scifi', 'Science-Fiction · IMDb');
    this.addSection('series', 'Serien entdecken');
    this.addSection('live', 'Live TV');
    this.addSection('favorites', 'Meine Liste', true);
    this.imdbCredit = h('p.metadata-credit', { text: 'Information courtesy of IMDb (https://www.imdb.com). Used with permission.' });
    this.imdbCredit.style.display = 'none';
    this.el.appendChild(this.imdbCredit);
    this.order.forEach((zone, index) => {
      home.zones.add(zone, {
        left: () => home.sidebar,
        up: () => this.order.slice(0, index).reverse().filter((row) => row.items.length)[0],
        down: () => this.order.slice(index + 1).filter((row) => row.items.length)[0],
      });
    });
  }

  DiscoverPanel.prototype.addSection = function (id, title, personal) {
    const section = { personal: !!personal };
    const row = section.row = new App.Row({
      className: 'discover-row' + (id === 'live' || id === 'most-watched' ? ' discover-live-row' : ''),
      scrollContainer: () => this.el,
      render: (item) => {
        const tile = App.tile(item);
        tile.classList.add('discover-tile');
        return tile;
      },
      onActivate: (item) => App.openItem(item, row.items),
      onPointer: () => this.home.zones.activate(row, true),
    });
    const onKey = row.onKey;
    row.onKey = (key) => {
      if (key === 'red' && row.current()) {
        App.toggleFavorite(row.current());
        this.refresh();
        return true;
      }
      return onKey.call(row, key);
    };
    section.note = h('div.discover-section-note');
    section.status = h('div.discover-status');
    section.el = h('section.discover-section', { 'data-kind': id }, [
      h('div.discover-section-head', null, [h('h2.discover-section-title', { text: title }), section.note]),
      row.el,
      section.status,
    ]);
    this.sections[id] = section;
    this.order.push(row);
    this.el.appendChild(section.el);
    this.setRow(section, []);
  };

  DiscoverPanel.prototype.setRow = function (section, items, status) {
    const row = section.row;
    const selected = keyOf(row.current());
    const index = items.map(keyOf).indexOf(selected);
    const left = row.el.scrollLeft;
    row.setItems(items, index >= 0 ? index : row.index);
    row.el.scrollLeft = left;
    section.el.style.display = items.length || status ? '' : 'none';
    row.el.style.display = items.length ? '' : 'none';
    section.status.textContent = status || '';
    section.status.style.display = status ? '' : 'none';
  };

  DiscoverPanel.prototype.entryZone = function () {
    return this.order.filter((row) => row.items.length)[0] || this.home.sidebar;
  };

  DiscoverPanel.prototype.start = function () {
    const token = ++this.loadToken;
    const provider = App.provider;
    this.scope = App.libraryScope(provider);
    this.liveCatalog = [];
    this.movieCatalog = [];
    this.seriesCatalog = [];
    this.heroItem = null;
    this.heroDetails = {};
    this.renderHero();
    this.plot.textContent = 'Deine Playlist wird geladen …';
    this.refresh();
    const personalLoad = this.loadPersonalRows(token, provider);
    if (App.imdbCatalog) this.loadRankings(token, provider);
    const loads = ['movie', 'series', 'live'].map((kind) => {
      const section = this.sections[kind];
      section.note.textContent = '';
      this.setRow(section, [], 'Wird geladen …');
      return Promise.resolve().then(() => provider.categories(kind)).then((categories) => {
        // Die regulären Reihen laden höchstens zwei passende Kategorien.
        const chosen = categories.filter((category) => App.passesCountryFilter(category.name)).slice(0, 2);
        return Promise.all(chosen.map((category) => Promise.resolve()
          .then(() => provider.items(kind, category.id))
          .then((items) => ({ items: items }), () => ({ items: [], failed: true }))));
      }).then((results) => {
        if (token !== this.loadToken || provider !== App.provider) return;
        const items = sampleCategories(results);
        const failed = results.some((result) => result.failed);
        section.note.textContent = failed && items.length ? 'Ein Teil der Inhalte ist gerade nicht erreichbar.' : '';
        this.setRow(section, items, items.length ? '' : failed
          ? 'Inhalte gerade nicht erreichbar.'
          : 'Keine passenden Inhalte in deiner Playlist.');
        this.chooseHero(token, provider);
      }, () => {
        if (token !== this.loadToken || provider !== App.provider) return;
        this.setRow(section, [], 'Inhalte gerade nicht erreichbar.');
      });
    });
    return Promise.all(loads.concat([personalLoad])).then(() => {
      if (token !== this.loadToken || provider !== App.provider) return;
      if (!this.heroItem) this.plot.textContent = 'Öffne Live TV oder wähle einen anderen Bereich. Deine Playlist bestimmt, welche Inhalte hier erscheinen.';
    });
  };

  DiscoverPanel.prototype.filteredCatalog = function (provider, kind) {
    return Promise.all([
      Promise.resolve().then(() => provider.categories(kind)),
      Promise.resolve().then(() => provider.allItems(kind)),
    ]).then((data) => {
      const cats = {};
      data[0].forEach((cat) => { cats[cat.id] = cat.name; });
      return { all: data[1], visible: data[1].filter((item) => App.passesCountryFilter(cats[item.catId] || '')) };
    });
  };

  DiscoverPanel.prototype.loadPersonalRows = function (token, provider) {
    const scope = this.scope;
    const watched = this.sections['most-watched'];
    const added = this.sections['new-movies'];
    const recommended = this.sections.recommended;
    watched.note.textContent = 'Nach deiner Sehzeit';
    added.note.textContent = 'In den letzten 30 Tagen hinzugefügt';
    this.setRow(watched, [], 'Sender werden geladen …');
    this.setRow(added, [], 'Filmliste wird geprüft …');
    this.setRow(recommended, [], 'Deine Auswahl wird zusammengestellt …');
    // Diese beiden Reihen benötigen den ganzen Katalog, nicht nur die ersten
    // Kategorien. Der Provider teilt die Anfrage mit Suche und IMDb-Reihen.
    this.movieCatalogPromise = Promise.resolve().then(() => this.filteredCatalog(provider, 'movie'));
    const movies = this.movieCatalogPromise.then((catalog) => {
      if (token !== this.loadToken || provider !== App.provider) return;
      App.observeMovieCatalog(catalog.all, scope);
      this.movieCatalog = catalog.visible;
      this.updateRecommendations();
      this.setRow(added, App.newMovies(this.movieCatalog, LIMIT, scope), '');
      if (!added.row.items.length) this.setRow(added, [], 'Noch keine neuen Filme erkannt. Ohne Anbieterdatum beginnt der Vergleich mit dieser Liste.');
    }, () => {
      if (token === this.loadToken && provider === App.provider) {
        this.setRow(added, [], 'Neue Filme gerade nicht erreichbar.');
        this.updateRecommendations();
      }
    });
    const series = Promise.resolve().then(() => this.filteredCatalog(provider, 'series')).then((catalog) => {
      if (token !== this.loadToken || provider !== App.provider) return;
      this.seriesCatalog = catalog.visible;
      this.updateRecommendations();
    }, () => {
      if (token === this.loadToken && provider === App.provider) this.updateRecommendations();
    });
    const live = Promise.resolve().then(() => this.filteredCatalog(provider, 'live')).then((catalog) => {
      if (token !== this.loadToken || provider !== App.provider) return;
      this.liveCatalog = catalog.visible;
      this.updateMostWatched();
    }, () => {
      if (token === this.loadToken && provider === App.provider) this.setRow(watched, [], 'Sender gerade nicht erreichbar.');
    });
    return Promise.all([movies, series, live]);
  };

  DiscoverPanel.prototype.updateRecommendations = function () {
    if (!App.recommendations) return;
    const result = App.recommendations(this.movieCatalog.concat(this.seriesCatalog), { limit: LIMIT, scope: this.scope });
    const section = this.sections.recommended;
    section.note.textContent = result.personalized ? 'Nach deinem Geschmack'
      : result.reason || 'Zum Entdecken · Mit deinen Bewertungen wird die Auswahl persönlicher';
    this.setRow(section, result.items, result.items.length ? ''
      : 'Noch keine passenden Vorschläge. Mit „Gefällt mir“ kannst du uns deinen Geschmack zeigen.');
  };

  DiscoverPanel.prototype.updateMostWatched = function () {
    const items = App.mostWatched(this.liveCatalog, LIMIT, this.scope);
    this.setRow(this.sections['most-watched'], items, items.length ? ''
      : 'Schaue einen Sender mindestens 30 Sekunden. Deine Favoriten nach Sehzeit erscheinen dann hier.');
  };

  DiscoverPanel.prototype.loadRankings = function (token, provider) {
    const sections = [['imdb-top', null], ['imdb-crime', 'Crime'], ['imdb-scifi', 'Sci-Fi']];
    this.imdbCredit.style.display = 'none';
    sections.forEach((pair) => this.setRow(this.sections[pair[0]], []));
    App.imdbCatalog.load().then((info) => {
      if (!info.available || token !== this.loadToken || provider !== App.provider) return;
      // Für eine faire Rangfolge die Filme aller passenden Kategorien prüfen.
      // Der Anbieter-Client cached diese Liste auch für Suche und Empfehlungen.
      return this.movieCatalogPromise.then((catalog) => {
        if (token !== this.loadToken || provider !== App.provider) return;
        const movies = catalog.visible;
        sections.forEach((pair) => {
          const section = this.sections[pair[0]];
          const ranked = App.rankedMovies(movies, pair[1], { limit: LIMIT });
          this.setRow(section, ranked.items);
          section.note.textContent = 'In deiner Playlist · ab ' + info.minVotes.toLocaleString('de-DE') + ' Stimmen';
          section.note.classList.add('imdb-source');
        });
        this.imdbCredit.style.display = sections.some((pair) => this.sections[pair[0]].row.items.length) ? '' : 'none';
        this.updateRecommendations();
      });
    }).catch(() => {});
  };

  DiscoverPanel.prototype.chooseHero = function (token, provider) {
    // Ein ruhiges Titelbild, kein automatisch wechselndes Karussell.
    if (this.heroItem) return;
    const candidates = this.sections.movie.row.items.concat(this.sections.series.row.items);
    const item = candidates.filter((candidate) => candidate.logo)[0] || candidates[0];
    if (!item) return;
    this.heroItem = item;
    this.heroDetails = {};
    this.renderHero();
    Promise.resolve().then(() => provider.details(item)).then((details) => {
      if (token !== this.loadToken || provider !== App.provider || this.heroItem !== item) return;
      this.heroDetails = details || {};
      this.renderHero();
    }, () => {
      // Auch ohne Zusatzdaten bleiben Titel, Merkliste und Details erreichbar.
    });
  };

  DiscoverPanel.prototype.renderHero = function () {
    const item = this.heroItem;
    const details = this.heroDetails;
    const scroll = this.el.scrollTop;
    if (!item) {
      App.clear(this.art);
      this.artUrl = null;
      this.actionState = null;
      this.eyebrow.textContent = 'DEINE MEDIATHEK';
      this.title.textContent = 'Entdecke dein Programm.';
      this.meta.textContent = '';
      this.actions.setItems([]);
      return;
    }
    const art = details.backdrop || details.poster || item.logo;
    if (art !== this.artUrl) {
      App.clear(this.art);
      if (art) this.art.appendChild(App.image(art, 'discover-image'));
      this.artUrl = art;
    }
    this.eyebrow.textContent = 'AUS DEINER MEDIATHEK';
    this.title.textContent = App.displayTitle(item);
    this.meta.textContent = [item.kind === 'series' ? 'Serie' : 'Film', details.year || item.year, details.genre, details.duration].filter(Boolean).join(' · ');
    this.plot.textContent = details.plot || 'Entdecke diesen Titel aus deiner Playlist oder merke ihn dir für später.';
    const actionState = keyOf(item) + ':' + App.isFavorite(item);
    if (this.actionState !== actionState) {
      this.actions.setItems([
        { label: 'Details ansehen', primary: true, icon: 'play', run: () => App.openItem(this.heroItem, [this.heroItem]) },
        { label: App.isFavorite(item) ? 'In meiner Liste' : 'Meine Liste', icon: App.isFavorite(item) ? 'check' : 'star', run: () => {
          App.toggleFavorite(this.heroItem);
          this.refresh();
        } },
      ], this.actions.index);
      this.actionState = actionState;
    }
    this.el.scrollTop = scroll;
  };

  DiscoverPanel.prototype.refresh = function () {
    const top = this.el.scrollTop;
    const active = this.home.zones.active;
    this.setRow(this.sections.continue, unique(App.continueWatching('movie').concat(App.continueWatching('episode'))));
    this.setRow(this.sections.favorites, unique(App.favorites('movie').concat(App.favorites('series'), App.favorites('live'))));
    if (this.liveCatalog.length) this.updateMostWatched();
    if (this.movieCatalog.length || this.seriesCatalog.length) this.updateRecommendations();
    ['movie', 'series', 'live', 'new-movies', 'imdb-top', 'imdb-crime', 'imdb-scifi'].forEach((kind) => {
      const section = this.sections[kind];
      if (section.row.items.length) this.setRow(section, section.row.items);
    });
    if (this.heroItem) this.renderHero();
    // Entfernte Favoriten dürfen keine leere Fokuszone zurücklassen.
    if (this.order.indexOf(active) >= 0 && !active.items.length) {
      this.home.zones.activate(this.entryZone(), true);
    }
    this.el.scrollTop = top;
  };

  DiscoverPanel.prototype.resize = function () {
    const top = this.el.scrollTop;
    this.order.forEach((row) => row.refresh(false));
    this.el.scrollTop = top;
  };

  App.DiscoverPanel = DiscoverPanel;
})(IpFlix);
