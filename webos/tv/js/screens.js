// Bildschirme: Navigation, Anmeldung, Startseite mit Bereichen, Detailseiten.
'use strict';

(function (App) {
  const h = App.h;

  // ---------- Navigation ----------

  const stack = [];
  const root = () => document.getElementById('app');

  App.push = function (screen) {
    const top = stack[stack.length - 1];
    // Rückfragen liegen über der Seite, die Seite bleibt sichtbar.
    if (top && !screen.isOverlay) {
      top.el.style.display = 'none';
      if (top.onHide) top.onHide();
    }
    stack.push(screen);
    root().appendChild(screen.el);
    if (screen.onShow) screen.onShow();
  };

  App.pop = function () {
    if (stack.length < 2) return;
    const screen = stack.pop();
    if (screen.onDestroy) screen.onDestroy();
    root().removeChild(screen.el);
    const top = stack[stack.length - 1];
    top.el.style.display = '';
    if (top.onShow) top.onShow();
  };

  App.reset = function (screen) {
    while (stack.length) {
      const s = stack.pop();
      if (s.onDestroy) s.onDestroy();
    }
    App.clear(root());
    App.push(screen);
  };

  App.dispatchKey = function (key) {
    const top = stack[stack.length - 1];
    if (top && top.onKey(key)) return;
    if (key === 'back' && stack.length > 1) App.pop();
  };

  // ---------- Rückfrage ----------

  function ConfirmScreen(title, text, confirmLabel, onConfirm) {
    this.row = new App.Row({
      className: 'buttons',
      render: (b) => h('div.button', { text: b.label }),
      onActivate: (b) => {
        App.pop();
        if (b.ok) onConfirm();
      },
    });
    this.row.setItems([{ label: 'Abbrechen' }, { label: confirmLabel, ok: true }], 0);
    this.row.setActive(true);
    this.el = h('div.screen.dialog', null, [
      h('div.dialog-box', null, [h('div.dialog-title', { text: title }), text ? h('div.dialog-text', { text: text }) : h('div.dialog-gap'), this.row.el]),
    ]);
  }

  ConfirmScreen.prototype.isOverlay = true;

  ConfirmScreen.prototype.onKey = function (key) {
    return this.row.onKey(key);
  };

  App.confirm = function (title, text, confirmLabel, onConfirm) {
    App.push(new ConfirmScreen(title, text, confirmLabel, onConfirm));
  };

  // ---------- Anmeldung ----------

  function LoginScreen() {
    this.type = 'xtream';
    this.fields = {
      server: input('Server-URL, z. B. http://anbieter.tv:8080', 'url'),
      username: input('Benutzername', 'text'),
      password: input('Passwort', 'password'),
      url: input('M3U-Adresse (http://…)', 'url'),
    };
    this.message = h('div.form-message');
    this.typeRow = new App.Row({
      className: 'segments',
      render: (t) => h('div.segment', { text: t.label }),
      onActivate: (t) => this.setType(t.id),
      onPointer: () => this.focus(0),
    });
    this.typeRow.setItems(
      [
        { id: 'xtream', label: 'Xtream' },
        { id: 'm3u', label: 'M3U-Adresse' },
      ],
      0
    );
    this.submit = h('div.button.primary', { text: 'Anmelden', onclick: () => this.login() });
    this.form = h('div.form');
    this.phone = h('div.phone-setup');
    this.el = h('div.screen.login', null, [
      this.phone,
      h('div.login-box', null, [
        h('div.brand', { text: 'IpFlix' }),
        h('div.login-sub', { text: 'Melde dich mit deinem IPTV-Zugang an.' }),
        this.typeRow.el,
        this.form,
        this.message,
        h('div.login-hint', { text: 'OK öffnet die Bildschirmtastatur. Mit ▲▼ wechselst du die Felder.' }),
      ]),
    ]);
    this.setType('xtream');
    this.startPhoneSetup();
  }

  /// QR-Code für die Eingabe am Handy; der Hilfsdienst öffnet dafür eine Seite im WLAN.
  LoginScreen.prototype.startPhoneSetup = function () {
    showPhoneQr(this, '/setup/start', 'Mit dem Handy eingeben', (account) => {
      if (this.busy) return;
      if (account.tmdbKey) {
        App.save('tmdbKey', account.tmdbKey);
        delete account.tmdbKey;
      }
      this.setType(account.type === 'm3u' ? 'm3u' : 'xtream');
      this.typeRow.focusIndex(account.type === 'm3u' ? 1 : 0);
      ['server', 'username', 'password', 'url'].forEach((k) => {
        this.fields[k].value = account[k] || '';
      });
      this.login(true);
    });
  };

  LoginScreen.prototype.onDestroy = function () {
    this.destroyed = true;
    clearInterval(this.pollTimer);
    fetch('/setup/stop').catch(() => {});
  };

  function input(placeholder, type) {
    return h('input.field', { placeholder: placeholder, type: type, autocomplete: 'off', spellcheck: false });
  }

  LoginScreen.prototype.setType = function (type) {
    this.type = type;
    App.clear(this.form);
    this.controls = [this.typeRow];
    const names = type === 'xtream' ? ['server', 'username', 'password'] : ['url'];
    names.forEach((name) => {
      const field = this.fields[name];
      this.form.appendChild(field);
      this.controls.push(field);
      field.onfocus = () => this.focus(this.controls.indexOf(field), true);
    });
    this.form.appendChild(this.submit);
    this.controls.push(this.submit);
    this.focus(this.focusIndex || 0);
  };

  LoginScreen.prototype.focus = function (index, fromInput) {
    this.focusIndex = Math.max(0, Math.min(index, this.controls.length - 1));
    this.controls.forEach((c, i) => {
      const el = c.el || c;
      el.classList.toggle('focused', i === this.focusIndex);
      if (c.setActive) c.setActive(i === this.focusIndex);
    });
    const current = this.controls[this.focusIndex];
    if (!fromInput && document.activeElement && document.activeElement.blur) document.activeElement.blur();
    return current;
  };

  LoginScreen.prototype.onKey = function (key) {
    const current = this.controls[this.focusIndex];
    if (key === 'up') return this.focus(this.focusIndex - 1), true;
    if (key === 'down') return this.focus(this.focusIndex + 1), true;
    if (key === 'back' && App.isTyping()) return document.activeElement.blur(), true;
    if (current === this.typeRow) return this.typeRow.onKey(key);
    if (key === 'ok') {
      if (current === this.submit) return this.login(), true;
      // Enter in der Tastatur: Feld verlassen und zum nächsten springen.
      if (document.activeElement === current) return this.focus(this.focusIndex + 1), true;
      current.focus();
      return true;
    }
    return false;
  };

  LoginScreen.prototype.login = function (fromPhone) {
    if (this.busy) return;
    const f = this.fields;
    const account =
      this.type === 'xtream'
        ? { type: 'xtream', server: f.server.value.trim(), username: f.username.value.trim(), password: f.password.value }
        : { type: 'm3u', url: f.url.value.trim() };
    if (this.type === 'xtream' && (!account.server || !account.username || !account.password)) {
      return this.say('Bitte Server, Benutzername und Passwort eingeben.', true);
    }
    if (this.type === 'm3u' && !/^https?:\/\//i.test(account.url)) {
      return this.say('Bitte eine Adresse eingeben, die mit http:// oder https:// beginnt.', true);
    }
    this.busy = true;
    this.say(fromPhone ? 'Daten vom Handy empfangen. Verbinde …' : 'Verbinde …');
    const provider = App.createProvider(account);
    provider.authenticate().then(
      (info) => {
        this.busy = false;
        if (info && info.exp_date) account.expires = parseInt(info.exp_date, 10) * 1000;
        App.save('account', account);
        App.startWith(provider);
      },
      (e) => {
        this.busy = false;
        this.say(e.message || String(e), true);
        // Vom Handy gesendet, aber falsch: Seite für einen neuen Versuch wieder öffnen.
        if (fromPhone) this.startPhoneSetup();
      }
    );
  };

  LoginScreen.prototype.say = function (text, isError) {
    this.message.textContent = text;
    this.message.classList.toggle('error', !!isError);
  };

  App.LoginScreen = LoginScreen;

  // ---------- Bereich mit Kategorien und Raster ----------

  /// source: { categories() → Promise<[{id,name}]>, items(cat) → Promise<[item]> }
  function BrowsePanel(title, source, home) {
    this.source = source;
    this.home = home;
    this.loadToken = 0;
    this.title = h('div.panel-title', { text: title });
    this.subtitle = h('div.panel-sub');
    this.status = h('div.panel-status');
    this.categories = new App.VList({
      className: 'categories',
      render: (c) => h('div.category', null, [h('span.cat-name', { text: c.name })]),
      onFocus: (c) => this.scheduleLoad(c),
      onActivate: () => this.home.zones.activate(this.grid),
      onPointer: () => this.home.zones.activate(this.categories),
    });
    this.grid = new App.Grid({
      width: App.LAYOUTS.live.width,
      height: App.LAYOUTS.live.height,
      gap: App.LAYOUTS.live.gap,
      tile: (item) => App.tile(item),
      onActivate: (item) => this.open(item),
      onSecondary: (item) => {
        App.toggleFavorite(item);
        this.grid.nodes = {};
        App.clear(this.grid.inner);
        this.grid.render();
      },
      onPointer: () => this.home.zones.activate(this.grid),
    });
    this.home.zones.add(this.categories, { left: () => home.sidebar, right: () => this.grid });
    this.home.zones.add(this.grid, { left: () => this.categories });
    const gridBox = h('div.grid-box', null, [this.grid.el, this.status]);
    this.el = h('div.panel', null, [
      h('div.panel-head', null, [this.title, this.subtitle, h('div.panel-hint', { text: 'Rot: Favorit' })]),
      h('div.panel-body', null, [this.categories.el, gridBox]),
    ]);
  }

  BrowsePanel.prototype.entryZone = function () {
    return this.categories;
  };

  BrowsePanel.prototype.start = function () {
    this.setStatus('Lädt Kategorien …');
    this.source.categories().then(
      (cats) => {
        const keep = this.categories.current();
        // Leeres „Zuletzt gesehen“/„Weiterschauen“ überspringen.
        const startAt = cats[0] && cats[0].list && !cats[0].list().length && cats.length > 1 ? 1 : 0;
        const index = keep ? Math.max(0, cats.map((c) => c.id).indexOf(keep.id)) : startAt;
        this.categories.setItems(cats, index);
        if (!cats.length) return this.setStatus('Keine Kategorien gefunden.');
        this.load(this.categories.current());
      },
      (e) => this.setStatus(e.message + ' Zum Neuladen den Bereich erneut öffnen.')
    );
  };

  BrowsePanel.prototype.scheduleLoad = function (category) {
    clearTimeout(this.loadTimer);
    // Beim schnellen Durchblättern nicht jede Kategorie laden.
    this.loadTimer = setTimeout(() => this.load(category), 350);
  };

  BrowsePanel.prototype.load = function (category) {
    const token = ++this.loadToken;
    this.subtitle.textContent = category.name;
    this.grid.setItems([], 0);
    this.setStatus('Lädt …');
    this.source.items(category).then(
      (items) => {
        if (token !== this.loadToken) return;
        this.grid.setLayout(App.layoutFor(items[0]));
        this.grid.setItems(items, 0);
        this.setStatus(items.length ? '' : category.empty || 'Hier ist nichts.');
      },
      (e) => {
        if (token === this.loadToken) this.setStatus(e.message);
      }
    );
  };

  BrowsePanel.prototype.setStatus = function (text) {
    this.status.textContent = text;
    this.status.style.display = text ? '' : 'none';
  };

  BrowsePanel.prototype.open = function (item) {
    if (item.kind === 'live') return App.play(item, this.grid.items);
    if (item.kind === 'episode' || item.url) return App.play(item, [item]);
    App.push(new DetailScreen(item));
  };

  BrowsePanel.prototype.refresh = function () {
    // Fortschritt und Favoriten können sich im Player geändert haben.
    const category = this.categories && this.categories.current();
    if (category && category.dynamic) return this.load(category);
    this.grid.nodes = {};
    App.clear(this.grid.inner);
    this.grid.render();
  };

  function providerSource(section) {
    const special =
      section === 'live'
        ? { id: '__recent', name: 'Zuletzt gesehen', dynamic: true, empty: 'Noch keine Sender angesehen.', list: () => App.recent() }
        : {
            id: '__continue',
            name: 'Weiterschauen',
            dynamic: true,
            empty: 'Noch nichts angefangen.',
            list: () => App.continueWatching(section === 'movie' ? 'movie' : 'episode'),
          };
    return {
      categories: () =>
        App.provider.categories(section).then((cats) => [special].concat(cats.filter((c) => App.passesCountryFilter(c.name)))),
      items: (cat) => (cat.list ? Promise.resolve(cat.list()) : App.provider.items(section, cat.id)),
    };
  }

  function favoritesSource() {
    const lists = [
      { id: 'live', name: 'Sender', empty: 'Rot drücken, um einen Sender zu merken.' },
      { id: 'movie', name: 'Filme', empty: 'Rot drücken, um einen Film zu merken.' },
      { id: 'series', name: 'Serien', empty: 'Rot drücken, um eine Serie zu merken.' },
    ];
    return {
      categories: () => Promise.resolve(lists.map((l) => Object.assign({ dynamic: true }, l))),
      items: (cat) => Promise.resolve(App.favorites(cat.id)),
    };
  }

  // ---------- Suche ----------

  function SearchPanel(home) {
    this.home = home;
    this.field = h('input.field.search-field', { placeholder: 'Sender, Filme oder Serien suchen', type: 'text', autocomplete: 'off' });
    this.status = h('div.panel-status');
    const field = this.field;
    this.inputZone = {
      items: [1],
      setActive: (active) => field.classList.toggle('focused', active),
      onKey: (key) => {
        if (key === 'ok') {
          if (document.activeElement === field) field.blur();
          else field.focus();
          return true;
        }
        if (key === 'down' && App.isTyping()) field.blur();
        return false;
      },
    };
    this.grid = new App.Grid({
      width: App.LAYOUTS.poster.width,
      height: App.LAYOUTS.poster.height,
      gap: App.LAYOUTS.poster.gap,
      tile: (item) => App.tile(item),
      onActivate: (item) => BrowsePanel.prototype.open.call(this, item),
      onSecondary: (item) => {
        App.toggleFavorite(item);
        BrowsePanel.prototype.refresh.call(this);
      },
      onPointer: () => home.zones.activate(this.grid),
    });
    home.zones.add(this.inputZone, { left: () => home.sidebar, down: () => this.grid });
    home.zones.add(this.grid, { up: () => this.inputZone, left: () => home.sidebar });
    field.addEventListener('input', () => {
      clearTimeout(this.timer);
      this.timer = setTimeout(() => this.search(), 500);
    });
    this.el = h('div.panel', null, [
      h('div.panel-head', null, [h('div.panel-title', { text: 'Suche' })]),
      this.field,
      h('div.grid-box.search-results', null, [this.grid.el, this.status]),
    ]);
    this.setStatus('Mindestens 2 Buchstaben eingeben.');
  }

  SearchPanel.prototype.entryZone = function () {
    return this.inputZone;
  };

  SearchPanel.prototype.start = function () {};

  SearchPanel.prototype.refresh = function () {
    BrowsePanel.prototype.refresh.call(this);
  };

  SearchPanel.prototype.setStatus = BrowsePanel.prototype.setStatus;

  SearchPanel.prototype.search = function () {
    const query = App.normalize(this.field.value.trim());
    if (query.length < 2) {
      this.grid.setItems([], 0);
      return this.setStatus('Mindestens 2 Buchstaben eingeben.');
    }
    const token = (this.token = (this.token || 0) + 1);
    this.setStatus('Durchsucht Sender, Filme und Serien … (beim ersten Mal dauert es etwas)');
    Promise.all(['live', 'movie', 'series'].map((s) => App.provider.allItems(s).catch(() => []))).then((lists) => {
      if (token !== this.token) return;
      const results = [];
      lists.forEach((list) => {
        let found = 0;
        for (let i = 0; i < list.length && found < 150; i++) {
          if (App.normalize(list[i].name).indexOf(query) >= 0) {
            results.push(list[i]);
            found++;
          }
        }
      });
      this.grid.setItems(results, 0);
      this.setStatus(results.length ? '' : 'Nichts gefunden.');
    });
  };

  // ---------- Einstellungen ----------

  function SettingsPanel(home) {
    this.home = home;
    this.list = new App.VList({
      className: 'settings-list',
      render: (row) => {
        const node = h('div.setting', null, [h('div.setting-label', { text: row.label }), h('div.setting-value', { text: row.value() })]);
        row.node = node;
        return node;
      },
      onActivate: (row) => {
        row.action();
        if (row.node) row.node.lastChild.textContent = row.value();
      },
      onPointer: () => home.zones.activate(this.list),
    });
    home.zones.add(this.list, { left: () => home.sidebar });
    this.el = h('div.panel', null, [h('div.panel-head', null, [h('div.panel-title', { text: 'Einstellungen' })]), this.list.el]);
  }

  SettingsPanel.prototype.entryZone = function () {
    return this.list;
  };

  SettingsPanel.prototype.start = function () {
    const account = App.load('account', {});
    const agents = App.USER_AGENTS;
    const rows = [
      {
        label: 'Tarnung (User-Agent)',
        value: () => {
          const match = agents.filter((a) => a.value === App.settings.userAgent)[0];
          return match ? match.label : App.settings.userAgent;
        },
        action: () => {
          const index = agents.map((a) => a.value).indexOf(App.settings.userAgent);
          App.updateSettings({ userAgent: agents[(index + 1) % agents.length].value });
        },
      },
      {
        label: 'Live-Format',
        value: () => (App.settings.liveFormat === 'ts' ? 'MPEG-TS (.ts)' : 'HLS (.m3u8)'),
        action: () => App.updateSettings({ liveFormat: App.settings.liveFormat === 'ts' ? 'm3u8' : 'ts' }),
      },
      {
        label: 'Länderfilter',
        value: () => (App.settings.countries.length ? App.settings.countries.join(', ') : 'Alle Länder'),
        action: () => App.push(new CountryScreen(this.home)),
      },
      {
        label: 'TMDB (Darsteller, Empfehlungen)',
        value: () => (App.hasTmdb() ? 'Eingerichtet' : 'Nicht eingerichtet'),
        action: () => App.push(new TmdbKeyScreen()),
      },
      {
        label: 'Konto',
        value: () =>
          account.type === 'm3u'
            ? 'M3U-Liste'
            : (account.username || '') + (account.expires ? ' · gültig bis ' + new Date(account.expires).toLocaleDateString('de-DE') : ''),
        action: () => {},
      },
      {
        label: 'Abmelden',
        value: () => 'Zugang, Favoriten und Verlauf löschen',
        action: () =>
          App.confirm('Abmelden?', 'Zugangsdaten, Favoriten und Verlauf werden von diesem Fernseher gelöscht.', 'Abmelden', () => {
            App.wipe();
            location.reload();
          }),
      },
      { label: 'Version', value: () => 'IpFlix TV 1.0', action: () => {} },
    ];
    this.list.setItems(rows, this.list.index);
  };

  SettingsPanel.prototype.refresh = function () {
    this.start();
  };

  // ---------- Länderfilter ----------

  function CountryScreen(home) {
    this.home = home;
    this.chosen = App.settings.countries.slice();
    this.list = new App.VList({
      className: 'country-list',
      render: (c) =>
        h('div.setting', null, [
          h('div.setting-label', { text: c.code }),
          h('div.setting-value', { text: c.count + (c.count === 1 ? ' Kategorie' : ' Kategorien') }),
          h('div.check' + (this.chosen.indexOf(c.code) >= 0 ? '.on' : ''), null, [App.icon('check')]),
        ]),
      onActivate: (c, i) => {
        const at = this.chosen.indexOf(c.code);
        if (at >= 0) this.chosen.splice(at, 1);
        else this.chosen.push(c.code);
        this.list.nodes[i].lastChild.classList.toggle('on', at < 0);
        this.renderSummary();
      },
    });
    this.list.setActive(true);
    this.summary = h('div.panel-sub');
    this.el = h('div.screen.sheet', null, [
      h('div.panel-head', null, [h('div.panel-title', { text: 'Länderfilter' }), this.summary]),
      h('div.login-hint', { text: 'OK wählt ein Land. Nichts gewählt = alle Länder. Zurück speichert.' }),
      this.list.el,
    ]);
    this.renderSummary();
    Promise.all(['live', 'movie', 'series'].map((s) => App.provider.categories(s).catch(() => []))).then((lists) => {
      const counts = {};
      lists.forEach((cats) =>
        cats.forEach((c) => {
          const code = App.countryOf(c.name);
          if (code) counts[code] = (counts[code] || 0) + 1;
        })
      );
      const items = Object.keys(counts)
        .map((code) => ({ code: code, count: counts[code] }))
        .sort((a, b) => b.count - a.count);
      this.list.setItems(items, 0);
      if (!items.length) this.summary.textContent = 'Keine Länderkürzel in den Kategorien gefunden.';
    });
  }

  CountryScreen.prototype.renderSummary = function () {
    this.summary.textContent = this.chosen.length ? 'Gewählt: ' + this.chosen.join(', ') : 'Alle Länder';
  };

  CountryScreen.prototype.onKey = function (key) {
    return this.list.onKey(key);
  };

  CountryScreen.prototype.onDestroy = function () {
    App.updateSettings({ countries: this.chosen });
    this.home.reloadAll();
  };

  // ---------- Startseite ----------

  const SECTIONS = [
    { id: 'search', label: 'Suche', icon: 'search' },
    { id: 'live', label: 'Live TV', icon: 'live' },
    { id: 'movie', label: 'Filme', icon: 'movie' },
    { id: 'series', label: 'Serien', icon: 'series' },
    { id: 'favorites', label: 'Favoriten', icon: 'star' },
    { id: 'settings', label: 'Einstellungen', icon: 'settings' },
  ];

  function HomeScreen() {
    this.zones = new App.Zones();
    this.panels = {};
    this.sidebar = new App.VList({
      className: 'nav',
      render: (s) => h('div.nav-item', null, [App.icon(s.icon), h('span.nav-label', { text: s.label })]),
      onFocus: (s) => this.show(s.id),
      onActivate: () => this.zones.activate(this.panel.entryZone()),
      onPointer: () => this.zones.activate(this.sidebar),
    });
    this.zones.add(this.sidebar, { right: () => this.panel && this.panel.entryZone() });
    this.content = h('div.content');
    this.el = h('div.screen.home', null, [
      h('div.sidebar', null, [h('div.brand.small', { text: 'IpFlix' }), this.sidebar.el]),
      this.content,
    ]);
    const last = App.load('section', 'live');
    const index = Math.max(0, SECTIONS.map((s) => s.id).indexOf(last));
    this.sidebar.setItems(SECTIONS, index);
    this.show(SECTIONS[index].id);
    this.zones.activate(this.sidebar);
  }

  HomeScreen.prototype.createPanel = function (id) {
    if (id === 'search') return new SearchPanel(this);
    if (id === 'settings') return new SettingsPanel(this);
    if (id === 'favorites') return new BrowsePanel('Favoriten', favoritesSource(), this);
    const label = SECTIONS.filter((s) => s.id === id)[0].label;
    return new BrowsePanel(label, providerSource(id), this);
  };

  HomeScreen.prototype.show = function (id) {
    if (this.panel && this.panel.id === id) return;
    App.save('section', id);
    let panel = this.panels[id];
    if (!panel) {
      panel = this.panels[id] = this.createPanel(id);
      panel.id = id;
      panel.start();
    } else {
      panel.refresh();
    }
    if (this.panel) this.content.removeChild(this.panel.el);
    this.panel = panel;
    this.content.appendChild(panel.el);
    // Raster messen erst nach dem Einhängen ihre Größe.
    if (panel.grid) panel.grid.render();
  };

  HomeScreen.prototype.reloadAll = function () {
    const current = this.panel && this.panel.id;
    Object.keys(this.panels).forEach((id) => {
      if (id !== current) delete this.panels[id];
    });
    if (this.panel) this.panel.start();
  };

  HomeScreen.prototype.onShow = function () {
    if (this.panel) this.panel.refresh();
  };

  HomeScreen.prototype.onKey = function (key) {
    if (this.zones.onKey(key)) return true;
    if (key === 'back') {
      if (App.isTyping()) {
        document.activeElement.blur();
      } else if (this.zones.active !== this.sidebar) {
        this.zones.activate(this.sidebar);
      } else {
        App.confirm('IpFlix beenden?', '', 'Beenden', () => window.close());
      }
      return true;
    }
    return false;
  };

  App.HomeScreen = HomeScreen;

  // ---------- Film- und Serienseite ----------

  /// Bild-Karte für waagerechte Reihen (Empfehlungen, Darsteller, Filmreihe).
  function card(title, image, subtitle, options) {
    options = options || {};
    return h('div.card' + (options.person ? '.person' : '') + (options.dim ? '.dim' : ''), null, [
      h('div.card-img', null, [h('span.mono', { text: App.monogram(title) }), image ? App.image(image, 'poster-img') : null]),
      h('div.card-title', { text: title }),
      subtitle ? h('div.card-sub', { text: subtitle }) : null,
    ]);
  }

  function displayTitle(item) {
    return item.kind === 'live' || item.kind === 'episode' ? item.name : App.cleanTitle(item.name).title;
  }
  App.displayTitle = displayTitle;

  /// Zonen untereinander: ▲▼ springt zur nächsten nicht leeren Zone.
  function stackZones(zones, list) {
    list.forEach((zone, i) => {
      zones.add(zone, {
        up: () => list.slice(0, i).reverse().filter((z) => z.items.length)[0],
        down: () => list.slice(i + 1).filter((z) => z.items.length)[0],
      });
    });
  }

  /// Hält die aktive Zone im sichtbaren Bereich eines senkrechten Containers.
  function scrollToZone(container, zone, first) {
    if (zone === first) return (container.scrollTop = 0);
    const rem = parseFloat(getComputedStyle(document.documentElement).fontSize) || 16;
    container.scrollTop = Math.max(0, zone.el.offsetTop - 12 * rem);
  }

  function DetailScreen(item) {
    this.item = item;
    this.zones = new App.Zones();
    this.header = h('div.detail-header');
    this.buttons = new App.Row({
      className: 'buttons',
      render: (b) => h('div.button' + (b.primary ? '.primary' : ''), null, [b.icon ? App.icon(b.icon) : null, h('span', { text: b.label })]),
      onActivate: (b) => b.action(),
      onPointer: () => this.zones.activate(this.buttons),
    });
    this.seasons = new App.Row({
      className: 'seasons',
      render: (s) => h('div.segment', { text: 'Staffel ' + s.number }),
      onFocus: (s) => this.showSeason(s),
      onPointer: () => this.zones.activate(this.seasons),
    });
    this.episodes = new App.VList({
      className: 'episodes',
      render: (ep) => episodeRow(ep),
      onActivate: (ep) => App.play(ep, this.season ? this.season.episodes : [ep]),
      onPointer: () => this.zones.activate(this.episodes),
    });
    this.cast = new App.Row({
      className: 'cards',
      render: (c) => card(c.name, c.photo, c.character, { person: true }),
      onActivate: (c) => App.push(new PersonScreen(c)),
      onPointer: () => this.zones.activate(this.cast),
    });
    this.recommended = new App.Row({
      className: 'cards',
      render: (it) => card(displayTitle(it), it.logo, null),
      onActivate: (it) => App.push(new DetailScreen(it)),
      onPointer: () => this.zones.activate(this.recommended),
    });
    stackZones(this.zones, [this.buttons, this.seasons, this.episodes, this.cast, this.recommended]);
    this.zones.onChange = (zone) => scrollToZone(this.body, zone, this.buttons);

    this.castTitle = h('div.section-title', { text: item.kind === 'series' ? 'Besetzung' : 'Darsteller' });
    this.recTitle = h('div.section-title', { text: 'Mehr wie dieses' });
    this.tmdbHint = h('div.tmdb-hint');
    this.body = h('div.detail-body', null, [
      this.header,
      this.buttons.el,
      this.seasons.el,
      this.episodes.el,
      this.tmdbHint,
      this.castTitle,
      this.cast.el,
      this.recTitle,
      this.recommended.el,
      h('div.detail-end'),
    ]);
    this.backdrop = h('div.backdrop');
    this.el = h('div.screen.detail', null, [this.backdrop, h('div.detail-shade'), this.body]);
    this.details = { poster: item.logo, seasons: [] };
    this.tmdb = null;
    this.render();
    this.zones.activate(this.buttons);
    App.provider.details(item).then(
      (d) => {
        this.details = d;
        this.render();
        this.loadTmdb();
      },
      (e) => {
        App.toast('Details nicht geladen: ' + e.message);
        this.loadTmdb();
      }
    );
  }

  DetailScreen.prototype.loadTmdb = function () {
    if (!App.hasTmdb()) {
      this.tmdbHint.textContent = 'Tipp: Mit einem TMDB-Schlüssel (Einstellungen) gibt es hier Darsteller, Filmreihen und Empfehlungen.';
      return;
    }
    App.tmdbFor(this.item, this.details).then(
      (t) => {
        if (!t) return;
        this.tmdb = t;
        this.render();
        this.cast.setItems(t.cast, 0);
        App.findInPlaylist(t.recommendations).then((found) => {
          const seen = {};
          const items = found.filter((it) => {
            if (!it || it.id === this.item.id || seen[it.kind + it.id]) return false;
            seen[it.kind + it.id] = true;
            return true;
          });
          this.recommended.setItems(items.slice(0, 20), 0);
          this.updateSections();
        });
        this.updateSections();
      },
      (e) => App.toast(e.message)
    );
  };

  DetailScreen.prototype.updateSections = function () {
    this.castTitle.style.display = this.cast.items.length ? '' : 'none';
    this.recTitle.style.display = this.recommended.items.length ? '' : 'none';
  };

  function episodeRow(ep) {
    const progress = App.progressOf(ep);
    return h('div.episode', null, [
      h('div.episode-thumb', null, [ep.logo ? App.image(ep.logo, 'thumb-img') : null, progress ? h('div.progress', null, [h('div.bar', { style: 'width:' + Math.round(progress * 100) + '%' })]) : null]),
      h('div.episode-text', null, [
        h('div.episode-title', { text: ep.number + '. ' + ep.name }),
        h('div.episode-meta', { text: ep.duration || '' }),
        ep.plot ? h('div.episode-plot', { text: ep.plot }) : null,
      ]),
    ]);
  }

  DetailScreen.prototype.render = function () {
    const item = this.item;
    const d = this.details;
    const t = this.tmdb || {};
    const clean = App.cleanTitle(item.name);
    const backdrop = d.backdrop || t.backdrop || d.poster || t.poster;
    const poster = item.logo || d.poster || t.poster;
    const rating = t.rating > 0 ? t.rating : d.rating;
    const plot = (t.overviewGerman && t.overview) || d.plot || t.overview;
    const directors = t.directors && t.directors.length ? t.directors.slice(0, 3).join(', ') : d.director;
    const meta = [
      d.year || clean.year,
      t.certification,
      d.genre || (t.genres && t.genres.slice(0, 3).join(', ')),
      d.duration || t.runtime,
      rating ? '★ ' + Number(rating).toFixed(1) + (rating === t.rating ? ' TMDB' : '') : null,
    ]
      .filter(Boolean)
      .join('  ·  ');
    this.backdrop.style.backgroundImage = backdrop ? 'url("' + App.proxied(backdrop) + '")' : '';
    App.clear(this.header);
    this.header.appendChild(h('div.detail-poster', null, [h('span.mono', { text: App.monogram(clean.title) }), poster ? App.image(poster, 'poster-img') : null]));
    this.header.appendChild(
      h('div.detail-info', null, [
        h('div.detail-title', { text: clean.title }),
        t.tagline ? h('div.detail-tagline', { text: t.tagline }) : null,
        meta ? h('div.detail-meta', { text: meta }) : null,
        plot ? h('div.detail-plot', { text: plot }) : null,
        directors ? h('div.detail-credit', { text: (item.kind === 'series' ? 'Von: ' : 'Regie: ') + directors }) : null,
        d.cast && !(t.cast && t.cast.length) ? h('div.detail-credit', { text: 'Mit: ' + d.cast }) : null,
      ])
    );

    const buttons = [];
    if (item.kind === 'movie') {
      const resume = App.resumePosition(item);
      if (resume) buttons.push({ label: 'Fortsetzen ab ' + App.formatTime(resume), icon: 'play', primary: true, action: () => App.play(item, [item]) });
      buttons.push({
        label: resume ? 'Von vorn' : 'Abspielen',
        icon: resume ? null : 'play',
        primary: !resume,
        action: () => {
          App.clearProgress(item);
          App.play(item, [item]);
        },
      });
    } else {
      const last = App.lastEpisodeOf(item.id);
      const first = d.seasons[0] && d.seasons[0].episodes[0];
      const next = last && nextEpisode(d.seasons, last);
      if (next) {
        const ep = next.episode;
        const label = (ep.id === last.item.id ? 'Fortsetzen ' : 'Weiter mit ') + 'S' + ep.season + ' F' + ep.number;
        buttons.push({ label: label, icon: 'play', primary: true, action: () => App.play(ep, next.queue) });
      } else if (first) {
        buttons.push({ label: 'Folge 1 abspielen', icon: 'play', primary: true, action: () => App.play(first, d.seasons[0].episodes) });
      }
    }
    buttons.push({
      label: App.isFavorite(item) ? 'Aus Favoriten' : 'Zu Favoriten',
      icon: 'star',
      action: () => {
        App.toggleFavorite(item);
        this.render();
      },
    });
    if (t.collection) {
      buttons.push({ label: 'Filmreihe', icon: 'movie', action: () => App.push(new CollectionScreen(t.collection)) });
    }
    this.buttons.setItems(buttons, Math.min(this.buttons.index, buttons.length - 1));

    if (d.seasons.length) {
      const keep = this.season ? d.seasons.map((s) => s.number).indexOf(this.season.number) : -1;
      this.seasons.setItems(d.seasons, Math.max(0, keep));
      this.showSeason(this.seasons.current());
    }
    this.updateSections();
  };

  /// Angefangene Folge fortsetzen, sonst die nächste (auch über das Staffelende hinaus).
  function nextEpisode(seasons, last) {
    for (let s = 0; s < seasons.length; s++) {
      const queue = seasons[s].episodes;
      const index = queue.map((e) => e.id).indexOf(last.item.id);
      if (index < 0) continue;
      if (!last.done) return { episode: queue[index], queue: queue };
      if (index < queue.length - 1) return { episode: queue[index + 1], queue: queue };
      const following = seasons[s + 1];
      if (following && following.episodes.length) return { episode: following.episodes[0], queue: following.episodes };
      return { episode: queue[index], queue: queue };
    }
    return null;
  }

  DetailScreen.prototype.showSeason = function (season) {
    this.season = season;
    this.episodes.setItems(season.episodes, 0);
  };

  DetailScreen.prototype.onShow = function () {
    // Nach dem Abspielen Fortschritt und „Weiterschauen“ auffrischen.
    if (this.details) this.render();
    if (this.season) this.episodes.setItems(this.season.episodes, this.episodes.index);
  };

  DetailScreen.prototype.onKey = function (key) {
    if (key === 'red') {
      App.toggleFavorite(this.item);
      this.render();
      return true;
    }
    return this.zones.onKey(key);
  };

  // ---------- Darsteller ----------

  function PersonScreen(person) {
    this.zones = new App.Zones();
    this.header = h('div.detail-header');
    this.status = h('div.section-note', { text: 'Sucht Titel in deiner Liste …' });
    this.titles = new App.Row({
      className: 'cards',
      render: (it) => card(displayTitle(it), it.logo, null),
      onActivate: (it) => App.push(new DetailScreen(it)),
      onPointer: () => this.zones.activate(this.titles),
    });
    this.zones.add(this.titles, {});
    this.body = h('div.detail-body', null, [this.header, h('div.section-title', { text: 'In deiner Liste' }), this.status, this.titles.el]);
    this.el = h('div.screen.detail.person-page', null, [h('div.detail-shade'), this.body]);
    this.render(person, null);
    App.tmdbPerson(person.id).then(
      (p) => {
        this.render(person, p);
        return App.findInPlaylist(p.credits).then((found) => {
          const seen = {};
          const items = found.filter((it) => it && !seen[it.kind + it.id] && (seen[it.kind + it.id] = true));
          this.titles.setItems(items, 0);
          this.zones.activate(this.titles);
          this.status.textContent = items.length
            ? items.length + ' von ' + p.credits.length + ' Titeln gibt es bei deinem Anbieter.'
            : 'Keiner der ' + p.credits.length + ' Titel ist in deiner Liste.';
        });
      },
      (e) => (this.status.textContent = e.message)
    );
  }

  PersonScreen.prototype.render = function (person, p) {
    App.clear(this.header);
    const photo = (p && p.photo) || person.photo;
    const facts = p ? [p.department === 'Acting' ? 'Schauspiel' : p.department, p.birthday ? 'geb. ' + p.birthday.split('-').reverse().join('.') : null, p.place].filter(Boolean).join('  ·  ') : '';
    this.header.appendChild(h('div.detail-poster', null, [h('span.mono', { text: App.monogram(person.name) }), photo ? App.image(photo, 'poster-img') : null]));
    this.header.appendChild(
      h('div.detail-info', null, [
        h('div.detail-title', { text: person.name }),
        facts ? h('div.detail-meta', { text: facts }) : null,
        p && p.biography ? h('div.detail-plot.long', { text: p.biography }) : null,
      ])
    );
  };

  PersonScreen.prototype.onKey = function (key) {
    return this.zones.onKey(key);
  };

  // ---------- Filmreihe ----------

  function CollectionScreen(collection) {
    this.zones = new App.Zones();
    this.title = h('div.detail-title', { text: collection.name });
    this.overview = h('div.detail-plot');
    this.status = h('div.section-note', { text: 'Lädt …' });
    this.parts = new App.Row({
      className: 'cards',
      render: (part) => card(part.title, part.available ? part.available.logo || part.poster : part.poster, part.year ? String(part.year) : null, { dim: !part.available }),
      onActivate: (part) => (part.available ? App.push(new DetailScreen(part.available)) : App.toast('Nicht bei deinem Anbieter')),
      onPointer: () => this.zones.activate(this.parts),
    });
    this.zones.add(this.parts, {});
    this.backdrop = h('div.backdrop');
    this.el = h('div.screen.detail', null, [
      this.backdrop,
      h('div.detail-shade'),
      h('div.detail-body', null, [this.title, this.overview, h('div.section-title', { text: 'Teile' }), this.status, this.parts.el]),
    ]);
    App.tmdbCollection(collection.id).then(
      (c) => {
        this.overview.textContent = c.overview || '';
        if (c.backdrop) this.backdrop.style.backgroundImage = 'url("' + App.proxied(c.backdrop) + '")';
        return App.findInPlaylist(c.parts).then((found) => {
          c.parts.forEach((part, i) => (part.available = found[i]));
          this.parts.setItems(c.parts, 0);
          this.zones.activate(this.parts);
          const count = found.filter(Boolean).length;
          this.status.textContent = count + ' von ' + c.parts.length + ' Teilen gibt es bei deinem Anbieter. Blasse Teile fehlen.';
        });
      },
      (e) => (this.status.textContent = e.message)
    );
  }

  CollectionScreen.prototype.onKey = function (key) {
    return this.zones.onKey(key);
  };

  // ---------- TMDB-Schlüssel per Handy ----------

  function TmdbKeyScreen(onSaved) {
    this.onSaved = onSaved;
    this.phone = h('div.phone-setup');
    this.message = h('div.form-message');
    this.row = new App.Row({
      className: 'buttons',
      render: (b) => h('div.button', { text: b.label }),
      onActivate: (b) => b.action(),
    });
    const buttons = [{ label: 'Zurück', action: () => App.pop() }];
    if (App.hasTmdb()) {
      buttons.push({
        label: 'Schlüssel entfernen',
        action: () => {
          App.save('tmdbKey', null);
          App.toast('TMDB-Schlüssel entfernt');
          App.pop();
        },
      });
    }
    this.row.setItems(buttons, 0);
    this.row.setActive(true);
    this.el = h('div.screen.login', null, [
      this.phone,
      h('div.login-box', null, [
        h('div.panel-title', { text: 'TMDB-Schlüssel' }),
        h('div.login-hint', {
          text:
            'Mit dem Schlüssel zeigt IpFlix Darsteller, Filmreihen und passende Empfehlungen aus deiner Liste. ' +
            'Den kostenlosen Schlüssel gibt es auf themoviedb.org unter Einstellungen → API; derselbe wie in der Mac-App geht auch.',
        }),
        h('div.login-hint', { text: App.hasTmdb() ? 'Ein Schlüssel ist eingerichtet. Ein neuer ersetzt ihn.' : 'Noch kein Schlüssel eingerichtet.' }),
        this.message,
        this.row.el,
      ]),
    ]);
    showPhoneQr(this, '/setup/start-tmdb', 'Schlüssel mit dem Handy eingeben', (account) => this.receive(account.tmdbKey));
  }

  TmdbKeyScreen.prototype.receive = function (key) {
    if (!key) return;
    this.message.textContent = 'Prüfe den Schlüssel …';
    this.message.classList.remove('error');
    App.verifyTmdbKey(key).then(
      () => {
        App.save('tmdbKey', key);
        App.toast('TMDB-Schlüssel gespeichert');
        App.pop();
      },
      (e) => {
        this.message.textContent = e.message + ' Bitte neu scannen.';
        this.message.classList.add('error');
        showPhoneQr(this, '/setup/start-tmdb', 'Schlüssel mit dem Handy eingeben', (account) => this.receive(account.tmdbKey));
      }
    );
  };

  TmdbKeyScreen.prototype.onKey = function (key) {
    return this.row.onKey(key);
  };

  TmdbKeyScreen.prototype.onDestroy = function () {
    this.destroyed = true;
    clearInterval(this.pollTimer);
    fetch('/setup/stop').catch(() => {});
  };

  /// QR-Code für die Handy-Eingabe anzeigen und auf die Daten warten.
  function showPhoneQr(screen, startPath, title, onReceive) {
    clearInterval(screen.pollTimer);
    fetch(startPath)
      .then((r) => r.json())
      .then((data) => {
        if (!data.url || screen.destroyed) return;
        const qr = qrcode(0, 'M');
        qr.addData(data.url);
        qr.make();
        const code = h('div.qr');
        code.innerHTML = qr.createSvgTag({ cellSize: 6, margin: 3 });
        App.clear(screen.phone);
        screen.phone.appendChild(h('div.phone-title', { text: title }));
        screen.phone.appendChild(code);
        screen.phone.appendChild(h('div.phone-text', { text: 'QR-Code mit der Kamera scannen, eintippen und senden. Handy und Fernseher müssen im selben WLAN sein.' }));
        screen.phone.appendChild(h('div.phone-url', { text: data.url }));
        screen.pollTimer = setInterval(() => {
          fetch('/setup/poll')
            .then((r) => r.json())
            .then((result) => {
              if (!result.account || screen.destroyed) return;
              clearInterval(screen.pollTimer);
              onReceive(result.account);
            })
            .catch(() => {});
        }, 2000);
      })
      .catch(() => {
        // Ohne Netzwerk bleibt nur die Eingabe mit der Fernbedienung.
      });
  }

  App.TmdbKeyScreen = TmdbKeyScreen;
  App.DetailScreen = DetailScreen;
})(IpFlix);
