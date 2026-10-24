const { test } = require('node:test');
const assert = require('node:assert/strict');
const { Element, domFixture } = require('./dom_fixture.cjs');

function fixture(provider, saved = {}) {
  if (!saved.account) saved.account = { type: 'xtream', server: 'https://fixture.test', username: 'test' };
  const dom = domFixture();
  const { App } = dom;
  Object.assign(App, {
    provider,
    load: (key, fallback) => saved[key] || fallback,
    save: (key, value) => { saved[key] = value; },
    toast() {},
    passesCountryFilter: name => !name.startsWith('TR |'),
    displayTitle: item => item.name,
    image: () => new Element('img'),
    icon: () => new Element('span'),
    openItem() {},
  });
  dom.load('widgets.js');
  dom.load('library.js');
  dom.load('catalog.js');
  dom.load('recommendations.js');
  App.tile = () => new Element('div.tile-poster');
  dom.load('discover.js');
  const sidebar = new App.VList({ render: () => new Element() });
  sidebar.setItems(['Startseite']);
  const home = { sidebar, zones: new App.Zones() };
  home.zones.activate(sidebar);
  const panel = new App.DiscoverPanel(home);
  return { App, home, panel };
}

function item(kind, id) { return { kind, id: String(id), name: kind + ' ' + id }; }
function providerWithMovies(items) {
  return {
    categories: kind => Promise.resolve(kind === 'movie' ? [{ id: 'one', name: 'DE | Filme' }] : []),
    items: () => Promise.resolve(items),
    details: () => Promise.resolve({}),
  };
}
const settle = () => new Promise(resolve => setImmediate(resolve));

test('discovery samples both matching categories fairly and limits each real catalog row', async () => {
  const requests = [];
  const provider = {
    categories: () => Promise.resolve([
      { id: 'tr', name: 'TR | Filme' },
      { id: 'a', name: 'DE | Filme' },
      { id: 'b', name: 'DE | Weitere' },
      { id: 'c', name: 'DE | Noch mehr' },
    ]),
    items(kind, category) {
      requests.push([kind, category]);
      return Promise.resolve(Array.from({ length: 40 }, (_, i) => item(kind, category + i)));
    },
    allItems() { throw new Error('must not fetch the entire catalog'); },
    details: () => Promise.resolve({}),
  };
  const { panel, home } = fixture(provider);
  await panel.start();
  assert.equal(requests.length, 6);
  assert.ok(requests.every(([, category]) => category === 'a' || category === 'b'));
  for (const kind of ['movie', 'series', 'live']) {
    const ids = Array.from(panel.sections[kind].row.items, value => value.id);
    assert.equal(ids.length, 16);
    assert.deepEqual(ids.slice(0, 4), ['a0', 'b0', 'a1', 'b1']);
    assert.equal(ids.filter(id => id.startsWith('a')).length, 8);
    assert.equal(ids.filter(id => id.startsWith('b')).length, 8);
  }
  assert.equal(home.zones.active, home.sidebar, 'loading content must not take focus from navigation');
});

test('overlapping and uneven categories fill the row with unique titles up to the cap', async () => {
  const provider = providerWithMovies([]);
  provider.categories = kind => Promise.resolve(kind === 'movie' ? [
    { id: 'short', name: 'DE | Auswahl' }, { id: 'long', name: 'DE | Mehr' },
  ] : []);
  provider.items = (kind, category) => Promise.resolve(Array.from(
    { length: category === 'short' ? 3 : 40 }, (_, i) => item(kind, i)
  ));
  const { panel } = fixture(provider);
  await panel.start();
  const ids = Array.from(panel.sections.movie.row.items, value => value.id);
  assert.equal(ids.length, 16);
  assert.equal(new Set(ids).size, 16);
  assert.ok(ids.includes('15'), 'remaining category keeps filling the row after the short one ends');
});

test('one failed category or entire section does not suppress available sections', async () => {
  const provider = {
    categories: kind => kind === 'live' ? Promise.reject(new Error('offline')) : Promise.resolve([
      { id: 'a', name: 'DE | Erste' }, { id: 'b', name: 'DE | Zweite' },
    ]),
    items: (kind, category) => category === 'a' ? Promise.reject(new Error('offline')) : Promise.resolve([item(kind, 2)]),
    details: () => Promise.reject(new Error('details offline')),
  };
  const { panel } = fixture(provider);
  await panel.start();
  await settle();
  assert.equal(panel.sections.movie.row.items[0].id, '2');
  assert.equal(panel.sections.series.row.items.length, 1);
  assert.match(panel.sections.movie.note.textContent, /Teil/);
  assert.match(panel.sections.live.status.textContent, /nicht erreichbar/);
  assert.equal(panel.actions.items[0].label, 'Details ansehen');
});

test('empty playlists do not invent recommendations or continue-watching entries', async () => {
  const { panel, home } = fixture(providerWithMovies([]));
  await panel.start();
  assert.equal(panel.heroItem, null);
  assert.equal(panel.sections.continue.row.items.length, 0);
  assert.equal(panel.sections.favorites.el.style.display, 'none');
  assert.equal(panel.actions.items.length, 0);
  assert.equal(panel.entryZone(), home.sidebar);
  assert.match(panel.sections.movie.status.textContent, /Keine passenden/);
});

test('personal homepage rows use whole available catalogs, respect country filters and refresh after playback', async () => {
  const movie = Object.assign(item('movie', 'recent'), { catId: 'de', addedAt: Math.floor(Date.now() / 1000) - 86400 });
  const old = item('movie', 'old');
  const de = Object.assign(item('live', 'de'), { catId: 'de' });
  const tr = Object.assign(item('live', 'tr'), { catId: 'tr' });
  const provider = {
    account: { type: 'xtream', server: 'https://personal.test', username: 'user' },
    categories: () => Promise.resolve([{ id: 'de', name: 'DE | Filme' }, { id: 'tr', name: 'TR | Filme' }]),
    allItems: kind => Promise.resolve(kind === 'movie' ? [movie, old] : [de, tr]),
    items: () => Promise.resolve([]),
    details: () => Promise.resolve({}),
  };
  const { panel, App } = fixture(provider);
  App.recordLiveWatch(de, 31);
  App.recordLiveWatch(tr, 300);
  await panel.start();
  assert.deepEqual(Array.from(panel.sections['new-movies'].row.items, value => value.id), ['recent']);
  assert.deepEqual(Array.from(panel.sections['most-watched'].row.items, value => value.id), ['de']);
  App.recordLiveWatch(de, 15);
  panel.refresh();
  assert.equal(panel.sections['most-watched'].row.current().id, 'de');
});

test('failed catalog refresh does not reset first-seen baseline or mark existing movies new', async () => {
  let fail = false;
  const existing = item('movie', 'old');
  const provider = providerWithMovies([existing]);
  provider.allItems = kind => fail ? Promise.reject(new Error('offline')) : Promise.resolve(kind === 'movie' ? [existing] : []);
  const { panel } = fixture(provider);
  await panel.start();
  assert.equal(panel.sections['new-movies'].row.items.length, 0);
  fail = true;
  await panel.start();
  assert.match(panel.sections['new-movies'].status.textContent, /nicht erreichbar/);
  fail = false;
  await panel.start();
  assert.equal(panel.sections['new-movies'].row.items.length, 0);
});

test('recommendation row reacts to feedback, keeps only available language-filtered titles and supports undo', async () => {
  const seed = { kind: 'movie', id: 'seed', name: 'Seed', catId: 'de', genres: ['Crime'] };
  const related = { kind: 'movie', id: 'related', name: 'Related', catId: 'de', genres: ['Crime'] };
  const hiddenLanguage = { kind: 'movie', id: 'tr', name: 'Unavailable language', catId: 'tr', genres: ['Crime'] };
  const other = { kind: 'movie', id: 'other', name: 'Other', catId: 'de', genres: ['Animation'] };
  const provider = {
    categories: () => Promise.resolve([{ id: 'de', name: 'DE | Filme' }, { id: 'tr', name: 'TR | Filme' }]),
    allItems: kind => Promise.resolve(kind === 'movie' ? [seed, related, hiddenLanguage, other] : []),
    items: () => Promise.resolve([]), details: () => Promise.resolve({}),
  };
  const { panel, App, home } = fixture(provider);
  await panel.start();
  const section = panel.sections.recommended;
  assert.ok(section.row.items.length);
  assert.match(section.note.textContent, /Entdecken/);
  App.setFeedback(seed, 'like');
  panel.refresh();
  assert.equal(section.row.items[0].id, 'related');
  assert.equal(section.row.items.some(value => value.id === 'tr'), false);
  assert.match(section.note.textContent, /Geschmack/);
  home.zones.activate(section.row, true);
  App.setFeedback(related, 'dislike');
  panel.refresh();
  assert.equal(section.row.items.some(value => value.id === 'related'), false);
  assert.ok(home.zones.active.items.length, 'removed recommendation cannot leave an empty active zone');
  App.setFeedback(related, null);
  panel.refresh();
  assert.equal(section.row.items[0].id, 'related');
});

test('IMDb rows update favorite indicators without losing selection or scroll', () => {
  const { panel, App } = fixture(providerWithMovies([]));
  App.tile = movie => {
    const node = new Element('div');
    node.favorite = App.isFavorite(movie);
    return node;
  };
  const section = panel.sections['imdb-crime'];
  panel.setRow(section, [item('movie', 'rated')]);
  section.row.el.scrollLeft = 30;
  section.row.onKey('red');
  assert.equal(section.row.nodes[0].favorite, true);
  assert.equal(section.row.current().id, 'rated');
  assert.equal(section.row.el.scrollLeft, 30);
});

test('continue-watching uses actual unfinished progress and updates on return without moving scroll or focus', async () => {
  const first = item('movie', 1);
  const second = item('movie', 2);
  const finished = item('movie', 3);
  const { panel, App, home } = fixture(providerWithMovies([first, second]), {
    progress: {
      'movie:1': { pos: 100, dur: 1000, at: 2, item: first },
      'movie:2': { pos: 200, dur: 1000, at: 3, item: second },
      'movie:3': { done: true, at: 4, item: finished },
    },
  });
  await panel.start();
  const row = panel.sections.continue.row;
  assert.deepEqual(Array.from(row.items, value => value.id), ['2', '1']);
  home.zones.activate(row, true);
  row.focusIndex(1, true);
  panel.el.scrollTop = 420;
  row.el.scrollLeft = 150;
  App.toggleFavorite(first);
  panel.refresh();
  assert.equal(row.current().id, '1');
  assert.equal(row.el.scrollLeft, 150);
  assert.equal(panel.el.scrollTop, 420);
  assert.equal(home.zones.active, row);
  assert.equal(panel.sections.favorites.row.items[0].id, '1');
  App.saveProgress(first, 1000, 1000);
  panel.refresh();
  assert.equal(row.items.length, 1, 'completed titles leave the real continue-watching row');
});

test('late catalog and hero details from previous loads cannot replace newer data', async () => {
  let resolveOldItems;
  const oldProvider = providerWithMovies([]);
  oldProvider.items = () => new Promise(resolve => { resolveOldItems = resolve; });
  const { panel, App } = fixture(oldProvider);
  const oldLoad = panel.start();
  await settle();
  let resolveDetails;
  App.provider = providerWithMovies([item('movie', 'new')]);
  App.provider.details = () => new Promise(resolve => { resolveDetails = resolve; });
  await panel.start();
  await settle();
  resolveOldItems([item('movie', 'old')]);
  await oldLoad;
  assert.equal(panel.heroItem.id, 'new');
  App.provider = providerWithMovies([item('movie', 'newer')]);
  await panel.start();
  resolveDetails({ plot: 'outdated plot' });
  await settle();
  assert.equal(panel.heroItem.id, 'newer');
  assert.notEqual(panel.plot.textContent, 'outdated plot');
});

test('hero metadata arrival keeps existing action buttons and current zone intact', async () => {
  let resolveDetails;
  const provider = providerWithMovies([item('movie', 1)]);
  provider.details = () => new Promise(resolve => { resolveDetails = resolve; });
  const { panel, home } = fixture(provider);
  await panel.start();
  await settle();
  const button = panel.actions.nodes[0];
  home.zones.activate(panel.actions, true);
  panel.el.scrollTop = 300;
  resolveDetails({ plot: 'Actual provider plot', year: '2025', backdrop: 'https://example.test/backdrop.jpg' });
  await settle();
  assert.equal(panel.plot.textContent, 'Actual provider plot');
  assert.equal(panel.actions.nodes[0], button, 'metadata cannot remove a focused native button');
  assert.equal(home.zones.active, panel.actions);
  assert.equal(panel.el.scrollTop, 300);
});

test('remote navigation skips empty rows and pointer activation does not scroll', async () => {
  const { panel, home } = fixture(providerWithMovies([item('movie', 1)]));
  await panel.start();
  home.zones.activate(panel.actions, true);
  assert.equal(home.zones.onKey('down'), true);
  assert.equal(home.zones.active, panel.sections.movie.row);
  assert.equal(home.zones.onKey('left'), true);
  assert.equal(home.zones.active, home.sidebar);
  panel.el.scrollTop = 200;
  panel.sections.movie.row.nodes[0].fire('mousemove');
  assert.equal(home.zones.active, panel.sections.movie.row);
  assert.equal(panel.el.scrollTop, 200);
});
