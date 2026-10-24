const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const zlib = require('node:zlib');
const { spawnSync } = require('node:child_process');

const source = fs.readFileSync(path.join(__dirname, '../tv/js/catalog.js'), 'utf8');
const data = () => ({
  schemaVersion: 1, generatedAt: '2026-10-24T10:00:00Z', minVotes: 25000,
  movies: [
    { id: 'tt0000001', title: 'The First Crime', originalTitle: 'Il Primo Crimine', year: 1990, genres: ['Crime', 'Drama'], rating: 8.8, votes: 100000 },
    { id: 'tt0000002', title: 'The Second Crime', originalTitle: 'The Second Crime', year: 2000, genres: ['Crime'], rating: 9.0, votes: 80000 },
    { id: 'tt0000003', title: 'Tomorrow', originalTitle: 'Tomorrow', year: 1990, genres: ['Sci-Fi'], rating: 8.8, votes: 200000 },
    { id: 'tt0000004', title: 'Tomorrow', originalTitle: 'Tomorrow', year: 2010, genres: ['Drama'], rating: 8.0, votes: 26000 },
    { id: 'tt0000005', title: 'Unclear', originalTitle: 'Unclear', year: 1999, genres: ['Drama'], rating: 8.2, votes: 26000 },
    { id: 'tt0000006', title: 'Unclear', originalTitle: 'Unklar', year: 1999, genres: ['Drama'], rating: 8.4, votes: 30000 },
  ],
});

function fixture(response = data()) {
  let calls = 0;
  const App = {};
  vm.runInNewContext(source, {
    IpFlix: App, Promise, WeakMap, fetch: () => {
      calls++;
      return Promise.resolve({ ok: response != null, json: () => Promise.resolve(response) });
    },
  });
  return { App, calls: () => calls };
}

const item = (name, year, extra = {}) => ({ name, year, id: name + year, kind: 'movie', ...extra });

test('IMDb lookup requires explicit identity or unambiguous title and year', async () => {
  const { App } = fixture();
  await App.imdbCatalog.load();
  assert.equal(App.imdbCatalog.match(item('Unrelated translation', 2020, { imdbId: 'tt0000001' })).id, 'tt0000001');
  assert.equal(App.imdbCatalog.match(item('DE | The First Crime (1990) 4K')).id, 'tt0000001');
  assert.equal(App.imdbCatalog.match(item('Il Primo Crimine', 1990)).id, 'tt0000001');
  assert.equal(App.imdbCatalog.match(item('Tomorrow', 2010)).id, 'tt0000004');
  assert.equal(App.imdbCatalog.match(item('Tomorrow')), null, 'remakes need a year');
  assert.equal(App.imdbCatalog.match(item('Unclear', 1999)), null, 'same-year ambiguity must remain unrated');
  assert.equal(App.imdbCatalog.match(item('The First Crime', 1991)), null);
  assert.equal(App.imdbCatalog.match(item('The First Crime', 1990, { imdbId: 'tt9999999' })), null, 'unknown explicit IDs must not fall back');
  assert.equal(App.imdbCatalog.match(item('The First Crime', 1990, { kind: 'series' })), null);
});

test('IMDb matching integrates existing cleanTitle objects and cache follows metadata updates', async () => {
  const { App } = fixture();
  App.cleanTitle = () => ({ title: 'The First Crime', year: 1990 });
  await App.imdbCatalog.load();
  const movie = item('DE - The First Crime - 1990 HD');
  assert.equal(App.imdbCatalog.match(movie).id, 'tt0000001');
  movie.imdbId = 'tt0000002';
  assert.equal(App.imdbCatalog.match(movie).id, 'tt0000002');
});

test('ranking uses actual IMDb ratings, vote tie breaks, genre aliases and unique movies', async () => {
  const { App } = fixture();
  await App.imdbCatalog.load();
  const originals = [item('The First Crime', 1990, { rating: 10 }), item('The Second Crime', 2000, { rating: 1 }),
    item('Tomorrow', 1990), item('Duplicate', 1990, { imdbId: 'tt0000001' }), item('Unknown', 1999, { rating: 9.9 })];
  const ranked = App.rankedMovies(originals);
  assert.deepEqual(Array.from(ranked.items, row => row.imdb.id), ['tt0000002', 'tt0000003', 'tt0000001']);
  assert.equal(ranked.items[0].rating, 1, 'provider data stays separate');
  assert.equal(originals[1].imdb, undefined, 'ranking does not mutate playlist items');
  assert.equal(ranked.minVotes, 25000);
  assert.equal(ranked.generatedAt, '2026-10-24T10:00:00Z');
  assert.deepEqual(Array.from(App.rankedMovies(originals, 'Krimi', { limit: 1 }).items, row => row.imdb.id), ['tt0000002']);
  assert.deepEqual(Array.from(App.rankedMovies(originals, 'Science Fiction').items, row => row.imdb.id), ['tt0000003']);
});

test('missing or invalid catalog never relabels provider ratings and concurrent loads share a request', async () => {
  for (const response of [null, { movies: [] }]) {
    const { App, calls } = fixture(response);
    const states = await Promise.all([App.imdbCatalog.load(), App.imdbCatalog.load()]);
    assert.equal(calls(), 1);
    assert.equal(states[0].available, false);
    assert.equal(App.rankedMovies([item('Title', 2000, { rating: 9.9 })]).items.length, 0);
  }
  const bad = data();
  bad.movies.push({ id: 'tt0000009', title: 'Too few votes', year: 1999, genres: [], rating: 9.9, votes: 5 });
  const { App } = fixture(bad);
  await App.imdbCatalog.load();
  assert.equal(App.imdbCatalog.match(item('Too few votes', 1999)), null);
});

test('search ranks title matches, accepts accents, tokens, small typos and actor/genre queries', () => {
  const { App } = fixture();
  const movies = [item('Interstellar', 2014, { genres: ['Sci-Fi', 'Adventure'], cast: 'Anne Hathaway' }),
    item('München', 2005, { genres: ['Crime', 'Drama'] }), item('Other Movie', 2012, { genres: ['Drama'], cast: 'Anne Hathaway' })];
  assert.equal(App.catalogSearch(movies, 'interstelalr')[0], movies[0]);
  assert.equal(App.catalogSearch(movies, 'MUNCHEN')[0], movies[1]);
  assert.equal(App.catalogSearch(movies, 'Krimi')[0], movies[1]);
  assert.equal(App.catalogSearch(movies, 'Science Fiction')[0], movies[0]);
  assert.equal(App.catalogSearch(movies, 'Hathaway', { limit: 1 })[0], movies[0]);
  assert.equal(App.catalogSearch(movies, 'adventure 2014')[0], movies[0]);
  assert.equal(App.catalogSearch(movies, 'completely absent').length, 0);
});

test('similar-title queries use known metadata and return only available related titles', async () => {
  const { App } = fixture();
  await App.imdbCatalog.load();
  const movies = [item('The First Crime', 1990), item('The Second Crime', 2000), item('Tomorrow', 1990), item('Unrelated', 2010)];
  for (const query of ['ähnlich wie The First Crime', 'aehnlich wie The First Crime', 'ähnliche Filme wie The First Crime',
    'aehnliche Filme wie The First Crime', 'Filme ähnlich wie The First Crime', 'Filme wie The First Crime', 'wie The First Crime']) {
    assert.deepEqual(Array.from(App.catalogSearch(movies, query), row => row.name), ['The Second Crime']);
  }
  assert.deepEqual(Array.from(App.catalogSearch(movies, '', { similarTo: movies[0] }), row => row.name), ['The Second Crime']);
  assert.equal(App.catalogSearch(movies, 'ähnlich wie Missing Title').length, 0);
  assert.equal(App.catalogSearch(movies, 'wie Unrelated').length, 0, 'missing similarity metadata must not invent results');
});

test('shared similarity parser preserves the title and handles umlaut, ASCII and series spellings', () => {
  const { App } = fixture();
  for (const prefix of ['ähnlich wie', 'aehnlich wie', 'ÄHNLICHE FILME WIE', 'ähnliche Serien wie',
    'aehnliche Serie zu', 'Serien ähnlich wie', 'Serie wie', 'Serien wie', 'Filme wie', 'wie', 'zu']) {
    assert.equal(App.parseSimilarQuery('  ' + prefix + '  Dark  '), 'Dark', prefix);
  }
  for (const query of ['', 'ähnlich wie', 'aehnliche Filme wie ', 'Dark', 'Krimi']) {
    assert.equal(App.parseSimilarQuery(query), null, query);
  }
  const series = [{ kind: 'series', id: 'a', name: 'Dark', genres: ['Sci-Fi', 'Mystery'] },
    { kind: 'series', id: 'b', name: '1899', genres: ['Mystery'] },
    { kind: 'movie', id: 'c', name: 'A movie', genres: ['Mystery'] }];
  assert.deepEqual(Array.from(App.catalogSearch(series, 'aehnliche Serien wie Dark'), item => item.name), ['1899']);
});

test('catalog builder streams gzip fixtures, excludes adult/series/low votes, and preserves output on bad input', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'ipflix-imdb-'));
  const output = path.join(directory, 'catalog.json');
  const basics = 'tconst\ttitleType\tprimaryTitle\toriginalTitle\tisAdult\tstartYear\tendYear\truntimeMinutes\tgenres\n' +
    'tt0000001\tmovie\tFirst\tFirst\t0\t1990\t\\N\t100\tCrime,Drama\n' +
    'tt0000002\tmovie\tLow\tLow\t0\t1991\t\\N\t100\tDrama\n' +
    'tt0000003\tmovie\tAdult\tAdult\t1\t1992\t\\N\t100\tAdult\n' +
    'tt0000004\ttvSeries\tSeries\tSeries\t0\t1993\t\\N\t100\tCrime\n' +
    'tt0000005\tmovie\tSecond\tSecond\t0\t1994\t\\N\t100\tCrime\n';
  const ratings = 'tconst\taverageRating\tnumVotes\n' +
    'tt0000001\t8.5\t30000\ntt0000002\t9.9\t20\ntt0000003\t9.0\t30000\n' +
    'tt0000004\t9.1\t40000\ntt0000005\t8.8\t50000\n';
  try {
    fs.writeFileSync(path.join(directory, 'title.basics.tsv.gz'), zlib.gzipSync(basics));
    fs.writeFileSync(path.join(directory, 'title.ratings.tsv.gz'), zlib.gzipSync(ratings));
    const aliases = 'titleId\tordering\ttitle\tregion\tlanguage\ttypes\tattributes\tisOriginalTitle\n' +
      'tt0000001\t1\tErster Film\tDE\tde\t\\N\t\\N\t0\n' +
      'tt0000001\t2\tErster Film\tAT\tde\t\\N\t\\N\t0\n' +
      'tt0000001\t3\tOther language\tES\tes\t\\N\t\\N\t0\n' +
      'tt0000001\t4\tWorking Collision\tUS\ten\tworking\t\\N\t0\n' +
      'tt0000001\t5\tFake Collision\tUS\ten\talternative\tfake working title\t0\n' +
      'tt0000001\t6\tPromo Collision\tUS\ten\talternative\tpromotional title\t0\n' +
      'tt9999999\t1\tAbsent Film\tDE\tde\t\\N\t\\N\t0\n';
    fs.writeFileSync(path.join(directory, 'title.akas.tsv.gz'), zlib.gzipSync(aliases));
    const command = [path.join(__dirname, '../../scripts/build_imdb_catalog.py'), '--cache-dir', directory, '--output', output, '--with-aliases'];
    const result = spawnSync('python3', command, { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    const catalog = JSON.parse(fs.readFileSync(output, 'utf8'));
    assert.deepEqual(catalog.movies.map(movie => movie.id), ['tt0000005', 'tt0000001']);
    assert.equal(catalog.isOfficialTop250, false);
    assert.deepEqual(catalog.movies.find(movie => movie.id === 'tt0000001').aliases, ['Erster Film']);
    const before = fs.readFileSync(output, 'utf8');
    fs.writeFileSync(path.join(directory, 'title.basics.tsv.gz'), 'broken gzip');
    assert.notEqual(spawnSync('python3', command).status, 0);
    assert.equal(fs.readFileSync(output, 'utf8'), before);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});


test('title-only matching supports localized aliases, decoration and numeric film titles without guessing', async () => {
  const catalog = data();
  catalog.movies[0].aliases = ['Das erste Verbrechen', 'İlk Suç'];
  catalog.movies[2].aliases = ['Morgen'];
  catalog.movies[3].aliases = ['Morgen'];
  ['1917', '2001: A Space Odyssey', 'Blade Runner 2049', '[REC]', 'Class of 1984'].forEach((title, index) => {
    catalog.movies.push({ id: 'tt100000' + index, title, year: 2000 + index, genres: ['Drama'], rating: 8, votes: 30000 });
  });
  const { App } = fixture(catalog);
  await App.imdbCatalog.load();
  for (const name of ['The First Crime', 'Das erste Verbrechen', '(V|DE) DE: Das erste Verbrechen FHD HEVC',
    'DE | Das erste Verbrechen 1990 WEB-DL x265', 'DE | FHD | Das erste Verbrechen', '[4K] Das erste Verbrechen', 'Das erste Verbrechen [1990] [FHD]']) {
    assert.equal(App.imdbCatalog.match(item(name)).id, 'tt0000001', name);
  }
  assert.equal(App.imdbCatalog.match(item('İlk Suç')).id, 'tt0000001');
  assert.equal(App.imdbCatalog.match(item('Morgen')), null, 'localized remakes also need a year');
  assert.equal(App.imdbCatalog.match(item('Morgen 2010')).id, 'tt0000004');
  assert.equal(App.imdbCatalog.match(item('Unknown film HD')), null);
  assert.equal(App.imdbCatalog.match(item('Das erste Verbrechen 1991')), null);
  ['1917', '2001: A Space Odyssey', 'Blade Runner 2049', '[REC]', 'Class of 1984'].forEach((title, index) => {
    assert.equal(App.imdbCatalog.match(item(title)).id, 'tt100000' + index, title);
  });
  const mutated = item('The First Crime');
  assert.equal(App.imdbCatalog.match(mutated).id, 'tt0000001');
  mutated.imdbId = 'not-an-id';
  assert.equal(App.imdbCatalog.match(mutated), null, 'invalid explicit identity must not reuse a title cache entry');
  const features = App.catalogFeatures(item('Das erste Verbrechen', null, {genres: []}));
  assert.equal(features.identity, 'imdb:tt0000001');
  assert.deepEqual(Array.from(features.genres), ['crime', 'drama']);
});

test('TMDB matching rejects unrelated results and ambiguous remakes instead of taking the first result', async () => {
  const { App } = fixture();
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../tv/js/tmdb.js'), 'utf8'), {IpFlix:App,Promise});
  const results = [{id:1,title:'Dune',year:1984}, {id:2,title:'Dune: Part Two',year:2024}, {id:3,title:'Dune',year:2021}];
  assert.equal(App.pickTmdbMatch(results,'Dune',2021).id,3);
  assert.equal(App.pickTmdbMatch(results,'Dune'),null);
  assert.equal(App.pickTmdbMatch(results,'Dune',2020),null);
  assert.equal(App.pickTmdbMatch(results,'Dune: Part Two').id,2);
  assert.equal(App.pickTmdbMatch(results,'Something else'),null);
  assert.equal(App.cleanTitle('DE: [REC] HEVC').title,'[REC]');
});


test('feature cache follows metadata edits and catalog replacement without exposing mutable arrays', async () => {
  const catalog = data();
  const { App } = fixture(catalog);
  const title = item('The First Crime', null, {genres: [], cast:['Person One']});
  const noCatalog = App.catalogFeatures(title);
  assert.equal(noCatalog.identity,null);
  await App.imdbCatalog.load();
  const first = App.catalogFeatures(title);
  assert.equal(first.identity,'imdb:tt0000001');
  assert.equal(App.catalogFeatures(title),first);
  assert.throws(()=>first.genres.push('fake'));
  title.cast.push('Person Two');
  const castChanged = App.catalogFeatures(title);
  assert.notEqual(castChanged,first);
  assert.deepEqual(Array.from(castChanged.cast),['person one','person two']);
  title.genres.push('Comedy');
  assert.deepEqual(Array.from(App.catalogFeatures(title).genres),['comedy']);
  title.imdbId='tt0000002';
  assert.equal(App.catalogFeatures(title).identity,'imdb:tt0000002');
  const beforeReload=App.catalogFeatures(title);
  await App.imdbCatalog.load(true);
  assert.notEqual(App.catalogFeatures(title),beforeReload);
});


test('sequel Roman suffixes match Arabic aliases conservatively and collisions stay unresolved', async () => {
  const catalog=data();
  const extra=(id,title,year=2000)=>({id,title,year,genres:['Drama'],rating:8,votes:30000});
  catalog.movies.push(extra('tt2000001','Der Pate 2'),extra('tt2000002','Story VIII'),
    extra('tt2000003','Conflict II'),extra('tt2000004','Conflict 2'),
    extra('tt2000005','II'),extra('tt2000006','Malcolm X'),extra('tt2000007','Rocky V'));
  const {App}=fixture(catalog);
  await App.imdbCatalog.load();
  assert.equal(App.imdbCatalog.match(item('Der Pate II')).id,'tt2000001');
  assert.equal(App.imdbCatalog.match(item('Story 8')).id,'tt2000002');
  assert.equal(App.catalogTitle('Der Pate II').title,'Der Pate II','display spelling unchanged');
  assert.equal(App.imdbCatalog.match(item('Conflict II')),null);
  assert.equal(App.imdbCatalog.match(item('Conflict 2',2000)),null,'even same-year collisions remain ambiguous');
  assert.equal(App.imdbCatalog.match(item('II')).id,'tt2000005');
  assert.equal(App.imdbCatalog.match(item('2')),null);
  assert.equal(App.imdbCatalog.match(item('Malcolm 10')),null);
  assert.equal(App.imdbCatalog.match(item('Rocky 5')),null);
  assert.equal(App.catalogTitleKey('I'),'i');
});


test('TMDB recommendations resolve playlist availability only when title and year are unambiguous', async () => {
  const {App}=fixture();
  vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../tv/js/tmdb.js'),'utf8'),{IpFlix:App,Promise});
  const movies=[item('Dune (1984)',null,{id:'old'}),item('Dune (2021)',null,{id:'new'}),
    item('Unique',null,{id:'unique'}),item('Ein Titel',2000,{id:'translation'}),item('An Original',2000,{id:'original'}),
    item('Der Pate II',null,{id:'sequel'}),item('Dune (2021)',null,{kind:'series',id:'tv'})];
  App.provider={allItems:kind=>Promise.resolve(movies.filter(movie=>movie.kind===kind))};
  const refs=[{type:'movie',title:'Dune',year:2021},{type:'movie',title:'Dune'},
    {type:'movie',title:'Dune',year:2020},{type:'movie',title:'Dune',year:2025},
    {type:'movie',title:'Unique',year:2020},{type:'movie',title:'Ein Titel',originalTitle:'An Original',year:2000},
    {type:'movie',title:'Der Pate 2',year:1974}];
  const result=await App.findInPlaylist(refs);
  assert.deepEqual(Array.from(result,match=>match&&match.id),['new',null,'new',null,'unique',null,'sequel']);
  movies.push(item('Dune',null,{id:'unknown'}));
  App.resetTmdbIndex();
  const withUnknown=await App.findInPlaylist([{type:'movie',title:'Dune',year:2020}]);
  assert.equal(withUnknown[0],null,'one nearby-year remake and one unknown-year candidate remain ambiguous');
});
