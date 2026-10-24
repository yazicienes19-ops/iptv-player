const { test } = require('node:test');
const assert = require('node:assert/strict');
const { domFixture } = require('./dom_fixture.cjs');

function fixture(saved = {}, details) {
  saved.account = saved.account || { type: 'xtream', server: 'https://feedback.test', username: 'user' };
  const dom = domFixture();
  const { App, context } = dom;
  const make = App.h;
  App.h = (selector, props, children) => {
    const node = make(selector, props, children);
    node.focus = () => { context.document.activeElement = node; node.fire('focus'); };
    return node;
  };
  Object.assign(App, {
    load: (key, fallback) => saved[key] || fallback,
    save: (key, value) => { saved[key] = value; },
    toast() {}, icon: () => App.h('span'), image: () => App.h('img'),
    monogram: () => 'F', proxied: value => value, hasTmdb: () => false,
    cleanTitle: value => ({ title: value }), formatTime: String,
    provider: { account: saved.account, details: () => details || Promise.resolve({ seasons: [] }) },
  });
  dom.load('widgets.js');
  dom.load('library.js');
  dom.load('catalog.js');
  dom.load('recommendations.js');
  dom.load('screens.js');
  return Object.assign(dom, { saved });
}

const settle = () => new Promise(resolve => setImmediate(resolve));

test('detail feedback toggles, excludes recommendations, persists and can be undone with TV keys', async () => {
  const f = fixture();
  const movie = { kind: 'movie', id: '1', name: 'Crime movie', genres: ['Crime'] };
  const other = { kind: 'movie', id: '2', name: 'Related movie', genres: ['Crime'] };
  const screen = new f.App.DetailScreen(movie);
  await settle();
  assert.equal(screen.feedbackButtons.nodes[0].tagName, 'BUTTON');
  assert.equal(screen.feedbackButtons.nodes[0]['aria-pressed'], 'false');
  screen.onKey('down');
  assert.equal(screen.zones.active, screen.feedbackButtons);
  screen.onKey('ok');
  assert.equal(f.App.feedbackOf(movie), 'like');
  assert.equal(screen.feedbackButtons.nodes[0]['aria-pressed'], 'true');
  assert.equal(f.App.recommendations([movie, other]).items[0].id, '2');
  screen.onKey('right');
  screen.onKey('ok');
  assert.equal(f.App.feedbackOf(movie), 'dislike');
  assert.equal(screen.feedbackButtons.nodes[0]['aria-pressed'], 'false');
  assert.equal(screen.feedbackButtons.nodes[1]['aria-pressed'], 'true');
  assert.match(screen.feedbackHint.textContent, /rückgängig/);
  assert.equal(fixture(f.saved).App.feedbackOf(movie), 'dislike');
  screen.onKey('ok');
  assert.equal(f.App.feedbackOf(movie), null);
  assert.equal(screen.feedbackButtons.nodes[1]['aria-pressed'], 'false');
});

test('tab focus and asynchronous detail loading keep the active rating button and use supplied metadata', async () => {
  let finishDetails;
  const f = fixture({}, new Promise(resolve => { finishDetails = resolve; }));
  const movie = { kind: 'series', id: '1', name: 'Title only' };
  const screen = new f.App.DetailScreen(movie);
  screen.feedbackButtons.nodes[1].focus();
  assert.equal(screen.zones.active, screen.feedbackButtons);
  assert.equal(screen.feedbackButtons.index, 1);
  finishDetails({ genre: 'Crime', director: 'Known Director', seasons: [] });
  await settle();
  assert.equal(f.context.document.activeElement, screen.feedbackButtons.nodes[1]);
  screen.feedbackButtons.nodes[0].fire('click');
  assert.equal(f.App.feedbackOf(movie), 'like');
  assert.equal(movie.genres, 'Crime');
});

test('a like before details arrive learns verified metadata and stays useful after reload', async () => {
  let finishDetails;
  const f = fixture({}, new Promise(resolve => { finishDetails = resolve; }));
  const movie = { kind: 'movie', id: 'late', name: 'Unknown title' };
  const screen = new f.App.DetailScreen(movie);
  screen.feedbackButtons.nodes[0].fire('click');
  finishDetails({ genre: 'Crime', seasons: [] });
  await settle();
  const restored = fixture(f.saved);
  const suggestions = restored.App.recommendations([
    { kind: 'movie', id: 'late', name: 'Unknown title' },
    { kind: 'movie', id: 'related', name: 'Related', genres: ['Crime'] },
  ]);
  assert.equal(suggestions.personalized, true);
  assert.equal(suggestions.items[0].id, 'related');
});

test('hidden detail recommendations repair focus and return after feedback is undone', async () => {
  const f = fixture();
  const other = { kind: 'movie', id: '2', name: 'Other' };
  f.App.hasTmdb = () => true;
  f.App.tmdbFor = () => Promise.resolve({ cast: [], recommendations: [other] });
  f.App.findInPlaylist = () => Promise.resolve([other]);
  const screen = new f.App.DetailScreen({ kind: 'movie', id: '1', name: 'Seed' });
  await settle();
  assert.equal(screen.recommended.items[0].id, '2');
  screen.zones.activate(screen.recommended, true);
  f.App.setFeedback(other, 'dislike');
  screen.onShow();
  assert.equal(screen.recommended.items.length, 0);
  assert.equal(screen.zones.active, screen.buttons);
  f.App.setFeedback(other, null);
  screen.onShow();
  assert.equal(screen.recommended.items[0].id, '2');
});

test('late detail responses from a closed screen cannot enrich another playlist or show an error', async () => {
  let finishDetails;
  const f = fixture({}, new Promise(resolve => { finishDetails = resolve; }));
  let remembered = 0;
  f.App.rememberRecommendationMetadata = () => { remembered++; };
  const movie = { kind: 'movie', id: 'late', name: 'Unknown title' };
  const screen = new f.App.DetailScreen(movie);
  screen.onDestroy();
  f.App.provider = { account: { type: 'xtream', server: 'https://other.test', username: 'other' } };
  finishDetails({ genre: 'Crime', seasons: [] });
  await settle();
  assert.equal(remembered, 0);
  assert.equal(movie.genres, undefined);
});
