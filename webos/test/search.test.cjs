const { test } = require('node:test');
const assert = require('node:assert/strict');
const { domFixture } = require('./dom_fixture.cjs');

const movies = [
  { kind: 'movie', id: '1', name: 'Inception', year: '2010', imdbId: 'tt1375666', catId: 'de' },
  { kind: 'movie', id: '2', name: 'Matrix', year: '1999', imdbId: 'tt0133093', catId: 'de' },
  { kind: 'movie', id: '3', name: 'The Godfather', year: '1972', imdbId: 'tt0068646', catId: 'de' },
  { kind: 'movie', id: '4', name: 'Hidden', year: '2000', catId: 'tr' },
];
const metadata = { schemaVersion: 1, generatedAt: '2026-10-24', minVotes: 25000, movies: [
  { id: 'tt1375666', title: 'Inception', year: 2010, rating: 8.8, votes: 2000000, genres: ['Action', 'Sci-Fi'] },
  { id: 'tt0133093', title: 'The Matrix', year: 1999, rating: 8.7, votes: 2000000, genres: ['Action', 'Sci-Fi'] },
  { id: 'tt0068646', title: 'The Godfather', year: 1972, rating: 9.2, votes: 2000000, genres: ['Crime', 'Drama'] },
] };

function fixture(provider = {}) {
  const f = domFixture();
  const { App, context } = f;
  const h = App.h;
  App.h = (selector, props, children) => {
    const el = h(selector, props, children);
    el.value = el.value || '';
    el.setAttribute = (key, value) => { el[key] = value; };
    el.focus = () => { context.document.activeElement = el; };
    el.blur = () => { context.document.activeElement = null; };
    return el;
  };
  Object.assign(context, { setTimeout, clearTimeout, fetch: () => Promise.resolve({ ok: true, json: () => Promise.resolve(metadata) }) });
  Object.assign(App, {
    displayTitle: item => item.name, icon: () => App.h('span'),
    cleanTitle: name => ({ title: name }), passesCountryFilter: name => !name.startsWith('TR'),
    isFavorite: () => false, progressOf: () => 0, hasTmdb: () => false,
    provider: Object.assign({
      categories: () => Promise.resolve([{ id: 'de', name: 'DE | Filme' }, { id: 'tr', name: 'TR | Filme' }]),
      allItems: kind => Promise.resolve(kind === 'movie' ? movies : kind === 'live' ? [{ kind: 'live', id: 'live', name: 'News' }] : []),
    }, provider),
  });
  f.load('widgets.js');
  App.tile = item => App.h('div.tile-poster', { text: item.name });
  f.load('catalog.js');
  f.load('search.js');
  const home = { zones: new App.Zones(), sidebar: { items: [1], setActive() {} } };
  const panel = new App.SearchPanel(home);
  return { ...f, panel, home };
}

test('search loads allowed playlist titles and IMDb genre selection uses only verified ratings', async () => {
  const { panel } = fixture();
  await panel.start();
  assert.equal(panel.items.some(item => item.name === 'Hidden'), false);
  panel.collections.focusIndex(2);
  panel.collections.activate();
  assert.deepEqual(Array.from(panel.grid.items, item => item.name), ['The Godfather']);
  assert.match(panel.source.textContent, /IMDb-Nutzerbewertungen/);
  assert.match(panel.source.textContent, /25/);
  assert.equal(panel.type, 'movie');
});

test('narrow search results keep cover titles visible and selected item through resizing', async () => {
  const { panel, context } = fixture();
  await panel.start();
  context.getComputedStyle = () => ({ fontSize: '12px' });
  panel.grid.el.clientWidth = 299;
  panel.grid.el.clientHeight = 405;
  panel.grid.focusIndex(2);
  panel.resize();
  assert.equal(panel.grid.metrics().cols, 2);
  assert.ok(panel.grid.metrics().h < 405);
  assert.equal(panel.grid.current().id, '3');
});

test('typos, similar queries and clearing search update real available results', async () => {
  const { panel } = fixture();
  await panel.start();
  panel.field.value = 'Inceptoin';
  panel.search();
  assert.equal(panel.grid.current().name, 'Inception');
  panel.field.value = 'Filme wie Inception';
  panel.search();
  assert.deepEqual(Array.from(panel.grid.items, item => item.name), ['Matrix']);
  panel.clearButton.fire('click');
  assert.equal(panel.field.value, '');
  assert.equal(panel.grid.items.length, 4);
});

test('partial provider errors retain available sections and expose retry', async () => {
  const { panel } = fixture({ allItems: kind => kind === 'series' ? Promise.reject(new Error('offline')) : Promise.resolve(kind === 'movie' ? movies : []) });
  await panel.start();
  assert.equal(panel.grid.items.length, 3);
  assert.equal(panel.retry.style.display, '');
  assert.match(panel.source.textContent, /nicht erreichbar/);
});

test('late recommendation results cannot replace a cleared or changed query', async () => {
  const { App, panel } = fixture();
  let resolve;
  App.hasTmdb = () => true;
  App.tmdbFor = () => new Promise(done => { resolve = done; });
  App.findInPlaylist = () => Promise.resolve([movies[1]]);
  await panel.start();
  panel.field.value = 'Filme wie Inception';
  panel.search();
  panel.clearButton.fire('click');
  resolve({ recommendations: [1] });
  await new Promise(done => setImmediate(done));
  assert.equal(panel.grid.items.length, 4);
  assert.equal(panel.resultTitle.textContent, 'In deiner Mediathek');
});

test('TMDB recommendations retain active IMDb genre constraints and source attribution', async () => {
  const { App, panel } = fixture();
  App.hasTmdb = () => true;
  App.tmdbFor = () => Promise.resolve({ recommendations: [1] });
  App.findInPlaylist = () => Promise.resolve([movies[1], movies[2], movies[3]]);
  await panel.start();
  panel.collections.focusIndex(2);
  panel.collections.activate();
  panel.field.value = 'Filme wie Inception';
  panel.search();
  await new Promise(done => setImmediate(done));
  assert.deepEqual(Array.from(panel.grid.items, item => item.name), ['The Godfather']);
  assert.match(panel.source.textContent, /IMDb-Nutzerbewertungen/);
  assert.match(panel.source.textContent, /TMDB/);
});

test('similar query spellings share catalog matching and TMDB enrichment', async () => {
  for (const query of ['ähnlich wie Inception', 'aehnlich wie Inception', 'ähnliche Filme wie Inception', 'aehnliche Filme wie Inception']) {
    const { App, panel } = fixture();
    const requested = [];
    App.hasTmdb = () => true;
    App.tmdbFor = item => { requested.push(item.id); return Promise.resolve({ recommendations: [1] }); };
    App.findInPlaylist = () => Promise.resolve([movies[1]]);
    await panel.start();
    panel.field.value = query;
    panel.search();
    await new Promise(done => setImmediate(done));
    assert.deepEqual(requested, ['1'], query);
    assert.deepEqual(Array.from(panel.grid.items, item => item.name), ['Matrix'], query);
    assert.equal(panel.resultTitle.textContent, 'Ähnlich wie „Inception“');
    assert.match(panel.source.textContent, /TMDB/);
  }
});

test('series similarity queries and the similar button keep series-specific labels and enrichment', async () => {
  const series = [{ kind: 'series', id: 'a', name: 'Dark', genres: ['Sci-Fi', 'Mystery'], catId: 'de' },
    { kind: 'series', id: 'b', name: '1899', genres: ['Mystery'], catId: 'de' }];
  const { App, panel } = fixture({ allItems: kind => Promise.resolve(kind === 'series' ? series : []) });
  const requested = [];
  App.hasTmdb = () => true;
  App.tmdbFor = item => { requested.push(item.id); return Promise.resolve({ recommendations: [1] }); };
  App.findInPlaylist = () => Promise.resolve([series[1]]);
  await panel.start();
  panel.field.value = 'aehnliche Serien wie Dark';
  panel.search();
  await new Promise(done => setImmediate(done));
  assert.deepEqual(requested, ['a']);
  assert.deepEqual(Array.from(panel.grid.items, item => item.name), ['1899']);
  panel.similar(series[0]);
  assert.equal(panel.field.value, 'Serien wie Dark');
  assert.equal(panel.type, 'series');
  await new Promise(done => setImmediate(done));
  assert.deepEqual(requested, ['a', 'a']);
});
