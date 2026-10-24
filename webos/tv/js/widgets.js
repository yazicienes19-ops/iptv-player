// Fokus-Bausteine für die Fernbedienung: Liste, Raster (virtualisiert), Knopfreihe.
// Jede Zone hat setActive(bool) und onKey(name) → true, wenn sie die Taste nutzt.
// Unbenutzte Pfeiltasten reicht die Seite an die Nachbarzone weiter.
// Die Magic Remote (Zeiger) wählt per Überfahren und Klicken.
'use strict';

(function (App) {
  const h = App.h;

  function remPx() {
    return parseFloat(getComputedStyle(document.documentElement).fontSize) || 16;
  }

  // Nur so weit scrollen, dass der fokussierte Eintrag ganz sichtbar bleibt.
  // Zeigerbewegungen dürfen die vom Nutzer gewählte Scrollposition nicht ändern.
  App.revealIn = function (container, node) {
    if (!container || !node) return;
    const area = container.getBoundingClientRect();
    const item = node.getBoundingClientRect();
    const top = area.top + 12;
    const bottom = area.bottom - 12;
    if (item.top < top || item.height > bottom - top) container.scrollTop += item.top - top;
    else if (item.bottom > bottom) container.scrollTop += item.bottom - bottom;
  };

  // ---------- Senkrechte Liste ----------

  function VList(options) {
    this.options = options;
    this.el = h('div.vlist' + (options.className ? '.' + options.className : ''));
    this.items = [];
    this.index = 0;
    this.active = false;
    this.nodes = [];
    this.el.addEventListener('wheel', (e) => {
      if (this.options.scrollContainer) return;
      this.el.scrollTop += e.deltaY;
      e.preventDefault();
    });
  }

  VList.prototype.setItems = function (items, index) {
    this.items = items;
    this.index = Math.max(0, Math.min(index || 0, items.length - 1));
    App.clear(this.el);
    this.nodes = items.map((item, i) => {
      const node = this.options.render(item, i);
      node.classList.add('vitem');
      node.addEventListener('mousemove', () => {
        if (App.usingKeyboard || (this.active && this.index === i)) return;
        if (this.options.onPointer) this.options.onPointer();
        this.focusIndex(i, true);
      });
      node.addEventListener('click', () => {
        App.usingKeyboard = false;
        if (this.options.onPointer) this.options.onPointer();
        this.focusIndex(i, true);
        this.activate();
      });
      this.el.appendChild(node);
      return node;
    });
    this.refresh(false);
  };

  VList.prototype.current = function () {
    return this.items[this.index];
  };

  VList.prototype.setActive = function (active, fromPointer) {
    this.active = active;
    this.refresh(active && !fromPointer);
  };

  VList.prototype.focusIndex = function (index, fromPointer) {
    if (!this.items.length) return;
    index = Math.max(0, Math.min(index, this.items.length - 1));
    const changed = index !== this.index;
    this.index = index;
    this.refresh(!fromPointer);
    if (changed && this.options.onFocus) this.options.onFocus(this.current(), index);
  };

  VList.prototype.refresh = function (scroll) {
    this.nodes.forEach((node, i) => {
      node.classList.toggle('focused', this.active && i === this.index);
      node.classList.toggle('selected', i === this.index);
    });
    const node = this.nodes[this.index];
    if (node && scroll !== false) {
      if (this.options.scrollContainer) App.revealIn(this.options.scrollContainer(), node);
      else {
        const target = node.offsetTop - (this.el.clientHeight - node.offsetHeight) / 2;
        this.el.scrollTop = Math.max(0, target);
      }
    }
  };

  VList.prototype.activate = function () {
    if (this.options.onActivate && this.items.length) this.options.onActivate(this.current(), this.index);
  };

  VList.prototype.onKey = function (key) {
    if (key === 'up' && this.index > 0) return this.focusIndex(this.index - 1), true;
    if (key === 'down' && this.index < this.items.length - 1) return this.focusIndex(this.index + 1), true;
    if (key === 'chup') return this.focusIndex(this.index - 8), true;
    if (key === 'chdown') return this.focusIndex(this.index + 8), true;
    if (key === 'ok') return this.activate(), true;
    return false;
  };

  // ---------- Raster (nur sichtbare Zeilen im DOM) ----------

  function Grid(options) {
    // options: tile(item) → Element, width/height/gap in rem, onActivate, onFocus, onPointer, onSecondary
    this.options = options;
    this.el = h('div.grid');
    this.inner = h('div.grid-inner');
    this.counter = h('div.grid-counter');
    this.el.appendChild(this.inner);
    this.el.appendChild(this.counter);
    this.items = [];
    this.index = 0;
    this.top = 0;
    this.active = false;
    this.nodes = {};
    this.el.addEventListener('wheel', (e) => {
      this.scrollRows(e.deltaY > 0 ? 1 : -1);
      e.preventDefault();
    });
  }

  Grid.prototype.setLayout = function (layout) {
    this.options.width = layout.width;
    this.options.height = layout.height;
    this.options.gap = layout.gap;
  };

  Grid.prototype.metrics = function () {
    const rem = remPx();
    const gap = this.options.gap * rem;
    const cols = Math.max(1, Math.floor((this.el.clientWidth + gap) / (this.options.width * rem + gap)));
    // Kacheln strecken, damit die Spalten die volle Breite füllen (Seitenverhältnis bleibt).
    const w = (this.el.clientWidth - (cols - 1) * gap) / cols;
    const hgt = (w * this.options.height) / this.options.width;
    const rows = Math.max(1, Math.floor((this.el.clientHeight + gap) / (hgt + gap)));
    return { w: w, h: hgt, gap: gap, cols: cols, rows: rows };
  };

  Grid.prototype.setItems = function (items, index) {
    this.items = items;
    this.index = Math.max(0, Math.min(index || 0, items.length - 1));
    this.top = 0;
    this.nodes = {};
    App.clear(this.inner);
    this.ensureVisible();
    this.render();
  };

  Grid.prototype.current = function () {
    return this.items[this.index];
  };

  Grid.prototype.setActive = function (active) {
    this.active = active;
    this.render();
  };

  Grid.prototype.ensureVisible = function () {
    const m = this.metrics();
    const row = Math.floor(this.index / m.cols);
    if (row < this.top) this.top = row;
    if (row >= this.top + m.rows) this.top = row - m.rows + 1;
  };

  Grid.prototype.scrollRows = function (delta) {
    const m = this.metrics();
    const maxTop = Math.max(0, Math.ceil(this.items.length / m.cols) - m.rows);
    this.top = Math.max(0, Math.min(this.top + delta, maxTop));
    this.render();
  };

  Grid.prototype.render = function () {
    const m = this.metrics();
    const first = this.top * m.cols;
    const last = Math.min(this.items.length, (this.top + m.rows + 1) * m.cols);
    const keep = {};
    for (let i = first; i < last; i++) {
      let node = this.nodes[i];
      if (!node) {
        node = this.options.tile(this.items[i]);
        node.classList.add('tile');
        this.bindPointer(node, i);
        this.inner.appendChild(node);
      }
      // Versteckte Bereiche messen zunächst 0 px. Beim Einblenden und nach
      // einer Fensteränderung auch bereits vorhandene Kacheln neu bemessen.
      node.style.width = m.w + 'px';
      node.style.height = m.h + 'px';
      const col = i % m.cols;
      const row = Math.floor(i / m.cols) - this.top;
      node.style.transform = 'translate(' + col * (m.w + m.gap) + 'px,' + row * (m.h + m.gap) + 'px)';
      node.classList.toggle('focused', this.active && i === this.index);
      keep[i] = node;
    }
    Object.keys(this.nodes).forEach((i) => {
      if (!keep[i]) this.inner.removeChild(this.nodes[i]);
    });
    this.nodes = keep;
    this.counter.textContent = this.items.length ? this.index + 1 + ' / ' + this.items.length : '';
  };

  Grid.prototype.bindPointer = function (node, i) {
    node.addEventListener('mousemove', () => {
      if (App.usingKeyboard || (this.active && this.index === i)) return;
      if (this.options.onPointer) this.options.onPointer();
      if (i !== this.index) {
        this.index = i;
        this.render();
        if (this.options.onFocus) this.options.onFocus(this.current(), i);
      }
    });
    node.addEventListener('click', () => {
      App.usingKeyboard = false;
      if (this.options.onPointer) this.options.onPointer();
      this.focusIndex(i);
      this.activate();
    });
  };

  Grid.prototype.focusIndex = function (index) {
    if (!this.items.length) return;
    this.index = Math.max(0, Math.min(index, this.items.length - 1));
    this.ensureVisible();
    this.render();
    if (this.options.onFocus) this.options.onFocus(this.current(), this.index);
  };

  Grid.prototype.activate = function () {
    if (this.options.onActivate && this.items.length) this.options.onActivate(this.current(), this.index);
  };

  Grid.prototype.onKey = function (key) {
    const cols = this.metrics().cols;
    const col = this.index % cols;
    const n = this.items.length;
    if (!n) return false;
    if (key === 'left' && col > 0) return this.focusIndex(this.index - 1), true;
    if (key === 'right' && col < cols - 1 && this.index < n - 1) return this.focusIndex(this.index + 1), true;
    if (key === 'up' && this.index >= cols) return this.focusIndex(this.index - cols), true;
    if (key === 'down' && this.index + cols < n) return this.focusIndex(this.index + cols), true;
    // Letzte, unvollständige Zeile: nach unten springt auf das letzte Element.
    if (key === 'down' && Math.floor(this.index / cols) < Math.floor((n - 1) / cols)) return this.focusIndex(n - 1), true;
    if (key === 'chup') return this.focusIndex(this.index - cols * this.metrics().rows), true;
    if (key === 'chdown') return this.focusIndex(this.index + cols * this.metrics().rows), true;
    if (key === 'ok') return this.activate(), true;
    if (key === 'red' && this.options.onSecondary) return this.options.onSecondary(this.current()), true;
    return false;
  };

  // ---------- Waagerechte Knopfreihe ----------

  function Row(options) {
    this.options = options;
    this.el = h('div.row' + (options.className ? '.' + options.className : ''));
    this.items = [];
    this.nodes = [];
    this.index = 0;
    this.active = false;
  }

  Row.prototype.setItems = function (items, index) {
    this.items = items;
    this.index = Math.max(0, Math.min(index || 0, items.length - 1));
    App.clear(this.el);
    this.nodes = items.map((item, i) => {
      const node = this.options.render(item, i);
      node.addEventListener('mousemove', () => {
        if (App.usingKeyboard || (this.active && this.index === i)) return;
        if (this.options.onPointer) this.options.onPointer();
        this.focusIndex(i, true);
      });
      node.addEventListener('click', () => {
        App.usingKeyboard = false;
        if (this.options.onPointer) this.options.onPointer();
        this.focusIndex(i, true);
        this.activate();
      });
      this.el.appendChild(node);
      return node;
    });
    this.refresh(false);
  };

  Row.prototype.current = function () {
    return this.items[this.index];
  };

  Row.prototype.setActive = function (active, fromPointer) {
    this.active = active;
    this.refresh(active && !fromPointer);
  };

  Row.prototype.focusIndex = function (index, fromPointer) {
    const changed = index !== this.index;
    this.index = Math.max(0, Math.min(index, this.items.length - 1));
    this.refresh(!fromPointer);
    if (changed && this.options.onFocus) this.options.onFocus(this.current(), this.index);
  };

  Row.prototype.refresh = function (scroll) {
    this.nodes.forEach((node, i) => {
      node.classList.toggle('focused', this.active && i === this.index);
      node.classList.toggle('selected', i === this.index);
    });
    // Nur waagerecht mitscrollen; senkrecht kümmert sich die Seite.
    const node = this.nodes[this.index];
    if (node && scroll !== false && this.el.scrollWidth > this.el.clientWidth) {
      this.el.scrollLeft = Math.max(0, node.offsetLeft - (this.el.clientWidth - node.offsetWidth) / 2);
    }
    if (node && scroll !== false && this.options.scrollContainer) App.revealIn(this.options.scrollContainer(), node);
  };

  Row.prototype.activate = function () {
    if (this.options.onActivate && this.items.length) this.options.onActivate(this.current(), this.index);
  };

  Row.prototype.onKey = function (key) {
    if (key === 'left' && this.index > 0) return this.focusIndex(this.index - 1), true;
    if (key === 'right' && this.index < this.items.length - 1) return this.focusIndex(this.index + 1), true;
    if (key === 'ok') return this.activate(), true;
    return false;
  };

  // ---------- Zonen einer Seite ----------

  /// Verwaltet, welche Zone aktiv ist, und die Nachbarn je Richtung.
  /// links/rechts/hoch/runter: Funktionen, die die nächste Zone liefern (oder null).
  function Zones() {
    this.list = [];
    this.active = null;
  }

  Zones.prototype.add = function (zone, neighbours) {
    zone.neighbours = neighbours || {};
    this.list.push(zone);
    return zone;
  };

  Zones.prototype.activate = function (zone, fromPointer) {
    if (!zone || zone === this.active) return;
    if (this.active) this.active.setActive(false);
    this.active = zone;
    zone.setActive(true, fromPointer);
    if (this.onChange) this.onChange(zone, fromPointer);
  };

  Zones.prototype.onKey = function (key) {
    const zone = this.active;
    if (!zone) return false;
    if (zone.onKey(key)) return true;
    const next = zone.neighbours[key] && zone.neighbours[key]();
    if (next && next.items && next.items.length) {
      this.activate(next);
      return true;
    }
    return false;
  };

  App.VList = VList;
  App.Grid = Grid;
  App.Row = Row;
  App.Zones = Zones;

  // ---------- Kacheln ----------

  App.LAYOUTS = {
    live: { width: 15, height: 11, gap: 1.25 },
    poster: { width: 11.5, height: 19.5, gap: 1.25 },
  };

  App.layoutFor = function (item) {
    return item && item.kind === 'live' ? App.LAYOUTS.live : App.LAYOUTS.poster;
  };

  App.tile = function (item) {
    const favorite = App.isFavorite(item);
    if (item.kind === 'live') {
      return h('div.tile-live', null, [
        h('div.logo', null, [item.logo ? App.image(item.logo, 'logo-img') : null, h('span.mono', { text: App.monogram(item.name) })]),
        h('div.name', { text: item.name }),
        favorite ? h('div.fav-dot') : null,
      ]);
    }
    const progress = App.progressOf(item);
    return h('div.tile-poster', null, [
      h('div.poster', null, [h('span.mono', { text: App.monogram(item.name) }), item.logo ? App.image(item.logo, 'poster-img') : null]),
      h('div.name', { text: App.displayTitle(item) }),
      favorite ? h('div.fav-dot') : null,
      item.imdb ? h('div.imdb-badge', { text: 'IMDb ' + Number(item.imdb.rating).toFixed(1) }) : null,
      progress ? h('div.progress', null, [h('div.bar', { style: 'width:' + Math.round(progress * 100) + '%' })]) : null,
    ]);
  };
})(IpFlix);
