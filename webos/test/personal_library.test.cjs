const { test } = require('node:test');
const assert = require('node:assert/strict');
const { domFixture } = require('./dom_fixture.cjs');

const NOW = Date.UTC(2026, 9, 24, 12);
const DAY = 86400000;
const movie = (id, extra = {}) => ({ kind: 'movie', id, name: 'Film ' + id, ...extra });
const live = (id, extra = {}) => ({ kind: 'live', id, name: 'Sender ' + id, ...extra });
const ids = items => Array.from(items, item => item.id);

function fixture(saved = {}) {
  const dom = domFixture();
  Object.assign(dom.App, {
    load: (key, fallback) => saved[key] == null ? fallback : JSON.parse(JSON.stringify(saved[key])),
    save: (key, data) => { saved[key] = JSON.parse(JSON.stringify(data)); },
    provider: { account: { type: 'xtream', server: 'https://provider.test', username: 'test', password: 'secret' } },
  });
  dom.load('library.js');
  return { App: dom.App, saved };
}

test('most watched ranks actual seconds, excludes quick zaps, missing channels and other playlists', () => {
  const { App, saved } = fixture();
  const a = live('a'), b = live('b'), c = live('c');
  const scope = App.libraryScope();
  App.recordLiveWatch(a, 100, scope);
  App.recordLiveWatch(b, 55, scope);
  App.recordLiveWatch(b, 60, scope);
  App.recordLiveWatch(c, 29, scope);
  App.recordLiveWatch(movie('movie'), 500, scope);
  assert.deepEqual(ids(App.mostWatched([a, b, c, movie('movie')])), ['b', 'a']);
  assert.deepEqual(ids(App.mostWatched([a, c])), ['a']);
  App.provider.account.username = 'other';
  assert.deepEqual(ids(App.mostWatched([a, b, c])), []);
  App.recordLiveWatch(a, 5, scope); // late flush remains attached to original playlist
  App.provider.account.username = 'test';
  assert.deepEqual(ids(App.mostWatched([a, b])), ['b', 'a']);
  assert.equal(JSON.stringify(saved).includes('secret'), false);
  assert.equal(JSON.stringify(saved).includes('provider.test'), false);
  assert.deepEqual(ids(fixture(saved).App.mostWatched([a, b])), ['b', 'a']);
});

test('M3U reordering preserves watch totals and movie identity without storing stream URLs', () => {
  const { App, saved } = fixture();
  const first = live('m0', { url: 'https://stream.test/user/private/token.ts' });
  App.recordLiveWatch(first, 35);
  assert.deepEqual(ids(App.mostWatched([live('m99', { url: first.url })])), ['m99']);
  const original = movie('m1', { url: 'https://stream.test/private/film.mp4' });
  App.observeMovieCatalog([original], null, NOW);
  const moved = movie('m88', { url: original.url });
  App.observeMovieCatalog([moved], null, NOW + DAY);
  assert.deepEqual(ids(App.newMovies([moved], 20, null, NOW + DAY)), []);
  assert.equal(JSON.stringify(saved).includes('stream.test'), false);
  assert.equal(JSON.stringify(saved).includes('private'), false);
});

test('initial unknown-date catalog is baseline; only later additions are new and persisted', () => {
  const { App, saved } = fixture();
  const a = movie('old'), b = movie('new');
  App.observeMovieCatalog([a], null, NOW);
  assert.deepEqual(ids(App.newMovies([a], 20, null, NOW)), []);
  App.observeMovieCatalog([a, b], null, NOW + DAY);
  assert.deepEqual(ids(App.newMovies([a, b], 20, null, NOW + DAY)), ['new']);
  const next = fixture(saved).App;
  next.observeMovieCatalog([a, b], null, NOW + 2 * DAY);
  assert.deepEqual(ids(next.newMovies([a, b], 20, null, NOW + 2 * DAY)), ['new']);
  assert.deepEqual(ids(next.newMovies([a, b], 20, null, NOW + 32 * DAY)), []);
  next.provider.account.server = 'https://second-provider.test';
  next.observeMovieCatalog([a, b], null, NOW + 2 * DAY);
  assert.deepEqual(ids(next.newMovies([a, b], 20, null, NOW + 2 * DAY)), []);
});

test('provider added dates use seconds, milliseconds or ISO dates, never release year or future values', () => {
  const { App } = fixture();
  const items = [
    movie('seconds', { addedAt: String((NOW - DAY) / 1000), year: '1972' }),
    movie('millis', { addedAt: NOW - 2 * DAY }),
    movie('iso', { addedAt: new Date(NOW - 3 * DAY).toISOString() }),
    movie('old', { addedAt: (NOW - 60 * DAY) / 1000, year: '2026' }),
    movie('future', { addedAt: (NOW + DAY) / 1000 }),
    movie('invalid', { addedAt: 'not-a-date' }),
  ];
  App.observeMovieCatalog(items, null, NOW);
  assert.deepEqual(ids(App.newMovies(items, 20, null, NOW)), ['seconds', 'millis', 'iso']);
  assert.deepEqual(ids(App.newMovies(items.slice(1), 1, null, NOW)), ['millis']);
  App.observeMovieCatalog(items.concat(movie('late-old', { addedAt: NOW - 60 * DAY })), null, NOW + DAY);
  assert.equal(App.newMovies([movie('late-old', { addedAt: NOW - 60 * DAY })], 20, null, NOW + DAY).length, 0);
});

test('invalid or non-live watch samples do not create history', () => {
  const { App } = fixture();
  [0, -5, NaN, Infinity].forEach(seconds => App.recordLiveWatch(live('a'), seconds));
  App.recordLiveWatch(movie('a'), 100);
  assert.deepEqual(ids(App.mostWatched([live('a'), movie('a')])), []);
});

test('watching does not rewrite a large movie snapshot and unchanged catalogs do not rewrite it either', () => {
  const { App } = fixture();
  const writes = [];
  App.save = (key, data) => writes.push({ key, size: JSON.stringify(data).length });
  const catalog = Array.from({ length: 5000 }, (_, i) => movie(String(i)));
  App.observeMovieCatalog(catalog, null, NOW);
  assert.ok(writes[0].size > 100000);
  App.observeMovieCatalog(catalog.slice().reverse(), null, NOW + DAY);
  assert.equal(writes.length, 1);
  App.recordLiveWatch(live('station'), 15);
  assert.equal(writes.length, 2);
  assert.ok(writes[1].key.startsWith('personal-watch.'));
  assert.ok(writes[1].size < 200);
});
