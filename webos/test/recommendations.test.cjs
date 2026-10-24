const { test } = require('node:test');
const assert = require('node:assert/strict');
const { domFixture } = require('./dom_fixture.cjs');
const ids = items => Array.from(items, item => item.id);
const movie = (id, extra = {}) => ({ kind: 'movie', id, name: 'Film ' + id, ...extra });
const series = (id, extra = {}) => ({ kind: 'series', id, name: 'Serie ' + id, ...extra });
const account = { type: 'xtream', server: 'https://provider.test', username: 'one' };
function fixture(saved = {}) {
  const dom = domFixture();
  Object.assign(dom.App, {
    load: (key, fallback) => saved[key] == null ? fallback : JSON.parse(JSON.stringify(saved[key])),
    save: (key, value) => { saved[key] = JSON.parse(JSON.stringify(value)); },
    toast() {},
    provider: { account: { ...account } },
    catalogIdentity: item => item.canonical || null,
    catalogFeatures: item => ({
      identity: item.canonical || null, genres: item.genres || [], cast: item.cast || [], director: item.director || [],
      year: item.year || null, title: item.name,
    }),
  });
  dom.load('library.js');
  dom.load('recommendations.js');
  return { App: dom.App, saved };
}

test('likes seed similar available titles and negative feedback is reversible across quality variants', () => {
  const { App } = fixture();
  const seed = movie('seed', { canonical: 'imdb:tt1111111', genres: ['crime'], director: ['a director'] });
  const match = movie('match', { canonical: 'imdb:tt2222222', genres: ['crime'], director: ['a director'] });
  const other = movie('other', { genres: ['animation'] });
  const alternate = movie('match-4k', { ...match, id: 'match-4k' });
  App.setFeedback(seed, 'like');
  let row = App.recommendations([seed, match, alternate, other]);
  assert.equal(row.personalized, true);
  assert.deepEqual(ids(row.items), ['match']);
  assert.equal(row.seedCount, 1);
  App.setFeedback(alternate, 'dislike');
  assert.equal(App.feedbackOf(match), 'dislike');
  assert.deepEqual(ids(App.recommendations([seed, match, alternate, other]).items), ['other']);
  App.setFeedback(match, null);
  assert.equal(App.feedbackOf(alternate), null);
  assert.deepEqual(ids(App.recommendations([seed, match, alternate, other]).items), ['match']);
  assert.deepEqual(ids(App.recommendations([other]).items), ['other'], 'missing provider titles never reappear');
});

test('preferences persist per playlist and M3U reordering keeps identity without storing stream addresses', () => {
  const { App, saved } = fixture();
  const first = movie('row1', { url: 'https://stream.test/private/film.mp4', genres: ['crime'] });
  const reordered = movie('row99', { url: first.url, genres: ['crime'] });
  App.setFeedback(first, 'like');
  assert.equal(App.feedbackOf(reordered), 'like');
  App.provider.account.username = 'two';
  assert.equal(App.feedbackOf(reordered), null);
  App.provider.account.username = 'one';
  assert.equal(fixture(saved).App.feedbackOf(reordered), 'like');
  const stored = Object.keys(saved).filter(key => key.startsWith('feedback.')).map(key => saved[key]);
  assert.equal(JSON.stringify(stored).includes('stream.test'), false);
});

test('actual viewing supplies weak positive signals; seeking to the end cannot mark a recommendation watched', () => {
  const { App } = fixture();
  const seed = movie('seed', { genres: ['drama'] });
  const similar = movie('similar', { genres: ['drama'] });
  App.saveProgress(seed, 599, 600);
  assert.equal(App.recommendations([seed, similar]).personalized, false);
  App.recordVodWatch(seed, 5, 600, 599);
  assert.equal(App.vodWatchOf(seed).completed, false);
  assert.equal(App.recommendations([seed, similar]).personalized, false);
  App.recordVodWatch(seed, 120, 600, 125);
  assert.equal(App.recommendations([seed, similar]).personalized, true);
  assert.deepEqual(ids(App.recommendations([seed, similar]).items), ['similar']);
  App.recordVodWatch(seed, 400, 600, 599);
  assert.equal(App.vodWatchOf(seed).completed, true);
  assert.deepEqual(ids(App.recommendations([seed, similar]).items), ['similar']);
});

test('unknown title-only content stays honest discovery and excluded titles remain hidden without inferred genres', () => {
  const { App } = fixture();
  const unknown = movie('unknown');
  const other = movie('other');
  App.setFeedback(unknown, 'like');
  const row = App.recommendations([unknown, other]);
  assert.equal(row.personalized, false);
  assert.equal(row.seedCount, 0);
  assert.match(row.reason, /Filminformationen/);
  assert.deepEqual(ids(row.items), ['other']);
  App.setFeedback(other, 'dislike');
  assert.deepEqual(ids(App.recommendations([unknown, other]).items), []);
});

test('verified detail metadata is retained as a seed when list items only contain a title', () => {
  const { App, saved } = fixture();
  App.setFeedback(movie('seed', { genres: ['crime'], cast: ['actor'] }), 'like');
  const current = [movie('seed'), movie('match', { genres: ['crime'] }), movie('other', { genres: ['comedy'] })];
  assert.deepEqual(ids(fixture(saved).App.recommendations(current).items), ['match']);
});

test('series feedback and real episode viewing work without marking an entire show completed', () => {
  const { App } = fixture();
  const seed = series('show', { genres: ['drama'] });
  const episode = { kind: 'episode', id: 'episode-1', seriesId: 'show', seriesName: seed.name };
  const similar = series('another-show', { genres: ['drama'] });
  App.recordVodWatch(episode, 1200, 1200, 1200);
  assert.equal(App.vodWatchOf(seed).completed, false);
  assert.equal(App.vodWatchOf(seed).seconds, 1200);
  assert.deepEqual(ids(App.recommendations([seed, similar]).items), ['another-show']);
});

test('scoped favorites and progress survive reorder and captured late writes never leak to a new account', () => {
  const { App } = fixture();
  const original = movie('row1', { url: 'https://stream.test/film.mp4', genres: ['crime'] });
  const moved = movie('row9', { url: original.url, genres: ['crime'] });
  const scope = App.libraryScope();
  App.toggleFavorite(original);
  App.saveProgress(original, 60, 600, scope);
  assert.equal(App.isFavorite(moved), true);
  assert.equal(App.resumePosition(moved), 60);
  App.provider.account.username = 'two';
  App.saveProgress(original, 80, 600, scope);
  App.recordVodWatch(original, 50, 600, 80, scope);
  assert.equal(App.isFavorite(moved), false);
  assert.equal(App.resumePosition(moved), 0);
  assert.equal(App.vodWatchOf(moved).seconds, 0);
  App.provider.account.username = 'one';
  assert.equal(App.resumePosition(moved), 80);
  assert.equal(App.vodWatchOf(moved).seconds, 50);
});

test('legacy history is adopted once for the saved login, never a later current provider', () => {
  const old = movie('old');
  const saved = {
    account: { ...account }, favorites: [old], recent: [],
    progress: { 'movie:old': { item: old, pos: 42, dur: 600, at: 1 } },
  };
  const { App } = fixture(saved);
  App.provider.account.username = 'two';
  assert.equal(App.isFavorite(old), false);
  assert.equal(App.resumePosition(old), 0);
  App.provider.account.username = 'one';
  assert.equal(App.isFavorite(old), true);
  assert.equal(App.resumePosition(old), 42);
  const unowned = { favorites: [old] };
  fixture(unowned);
  unowned.account = { ...account };
  assert.equal(fixture(unowned).App.isFavorite(old), false, 'unowned backup is not adopted by a later sign-in');
  assert.deepEqual(unowned.favorites, [old], 'backup is preserved');
});

test('feedback before metadata loads follows later canonical matches regardless of quality-variant order', () => {
  const { App, saved } = fixture();
  const early = movie('original', { name: 'Unique film' });
  App.setFeedback(early, 'like');
  App.catalogIdentity = item => item.name === 'Unique film' ? 'imdb:tt1111111' : null;
  App.catalogFeatures = item => ({ identity: App.catalogIdentity(item), genres: ['crime'], cast: [], director: [], title: item.name });
  const alternate = movie('4k', { name: 'Unique film' });
  assert.equal(App.feedbackOf(alternate), 'like');
  assert.deepEqual(ids(App.recommendations([alternate, early, movie('other')]).items), ['other']);
  App.setFeedback(alternate, null);
  assert.equal(App.feedbackOf(early), null);
  assert.equal(Object.values(saved).some(value => JSON.stringify(value).includes('https://')), false);
});

test('cold start mixes content kinds and categories instead of filling the row with the first provider group', () => {
  const { App } = fixture();
  const firstGroup = Array.from({ length: 30 }, (_, i) => movie('first-' + i, { catId: 'first' }));
  const candidates = firstGroup.concat([
    movie('second', { catId: 'second' }), movie('known', { catId: 'third', genres: ['crime'] }),
    series('show', { catId: 'shows' }),
  ]);
  const row = App.recommendations(candidates, { limit: 4 });
  assert.equal(row.personalized, false);
  assert.deepEqual(ids(row.items), ['known', 'show', 'first-0', 'second']);
});

test('metadata arriving after rating, favoriting or watching survives reload without renewing a preference', () => {
  const { App, saved } = fixture();
  const liked = movie('liked');
  const favored = movie('favored');
  const watched = movie('watched');
  App.setFeedback(liked, 'like');
  App.toggleFavorite(favored);
  App.recordVodWatch(watched, 120, 600, 120);
  const feedbackKey = Object.keys(saved).find(key => key.startsWith('feedback.'));
  const original = Object.values(saved[feedbackKey])[0];
  [liked, favored, watched].forEach(item => App.rememberRecommendationMetadata({ ...item, genres: ['crime'] }));
  const enriched = Object.values(saved[feedbackKey])[0];
  assert.equal(enriched.value, 'like');
  assert.equal(enriched.at, original.at);
  const next = fixture(saved).App;
  const match = movie('match', { genres: ['crime'] });
  [liked, favored, watched].forEach(seed => {
    const row = next.recommendations([seed, match]);
    assert.equal(row.personalized, true);
    assert.deepEqual(ids(row.items), ['match']);
  });
});

test('late metadata enrichment uses its captured playlist and never creates an unsolicited rating', () => {
  const { App, saved } = fixture();
  const item = movie('item');
  const scope = App.libraryScope();
  App.setFeedback(item, 'like');
  App.provider.account.username = 'two';
  App.rememberRecommendationMetadata({ ...item, genres: ['crime'] }, scope);
  assert.equal(App.feedbackOf(item), null);
  assert.equal(App.recommendations([item, movie('match', { genres: ['crime'] })]).personalized, false);
  App.rememberRecommendationMetadata(movie('new', { genres: ['crime'] }));
  assert.equal(App.feedbackOf(movie('new')), null);
  assert.equal(Object.keys(saved).filter(key => key.startsWith('feedback.')).length, 1);
  App.provider.account.username = 'one';
  assert.equal(App.recommendations([item, movie('match', { genres: ['crime'] })]).personalized, true);
});
