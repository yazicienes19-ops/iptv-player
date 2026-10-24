const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

async function parse(content) {
  const App = { fetchText: () => Promise.resolve(content) };
  vm.runInNewContext(fs.readFileSync(path.resolve(__dirname, '../tv/js/providers.js'), 'utf8'), { IpFlix: App });
  const provider = App.createProvider({ type: 'm3u', url: 'http://playlist.example/list.m3u' });
  const result = {};
  for (const section of ['live', 'movie', 'series']) {
    result[section] = JSON.parse(JSON.stringify(await provider.allItems(section)));
    result[section + 'Categories'] = JSON.parse(JSON.stringify(await provider.categories(section)));
  }
  return result;
}

test('M3U names retain commas and ignore commas inside quoted attributes', async () => {
  const data = await parse('#EXTM3U\n#EXTINF:-1 tvg-name="Fallback" group-title="DE, TV",ZDF, HD\nhttp://example.com/1.ts\n');
  assert.equal(data.live[0].name, 'ZDF, HD');
  assert.equal(data.liveCategories[0].name, 'DE, TV');
});

test('VOD file extensions and groups are classified without misclassifying 24/7 TV', async () => {
  const data = await parse(`#EXTM3U
#EXTINF:-1 group-title="VOD",A film
http://example.com/videos/film.MP4?token=abc
#EXTINF:-1 group-title="VOD | Drama",HLS film
http://example.com/vod/master.m3u8
#EXTINF:-1 group-title="Serien",Show S01E01
http://example.com/video/episode.mkv
#EXTINF:-1 group-title="Movies",24/7 Movies
http://example.com/live/master.m3u8
#EXTINF:-1,No group
#EXTGRP:Other
http://example.com/other.ts
`);
  assert.deepEqual(data.movie.map(i => i.name), ['A film', 'HLS film']);
  assert.deepEqual(data.series.map(i => i.name), ['Show S01E01']);
  assert.deepEqual(data.live.map(i => i.name), ['24/7 Movies', 'No group']);
  assert.equal(data.liveCategories[1].name, 'Other');
});

test('additional VOD files are recognized while streaming suffixes and query parameters stay live', async () => {
  const movies = [
    'https://cdn.example/film.WEBM?token=test',
    'https://cdn.example/film.ogv',
    'https://cdn.example/film.mpg',
    'https://cdn.example/film.mpeg',
    'https://cdn.example/film.m2ts',
    'https://cdn.example/film.vob',
    'https://cdn.example/film.mp4#t=30',
  ];
  const live = [
    'https://cdn.example/channel.ts',
    'https://cdn.example/master.m3u8',
    'https://cdn.example/manifest.mpd',
    'https://cdn.example/stream?poster=cover.mp4',
  ];
  const content = ['#EXTM3U'];
  for (const url of movies.concat(live)) content.push('#EXTINF:-1 group-title="Movies",' + url, url);
  content.push('#EXTINF:-1 group-title="Serien",Webserie S01E01', 'https://cdn.example/episode.webm');
  const data = await parse(content.join('\n'));
  assert.deepEqual(data.movie.map(i => i.url), movies);
  assert.deepEqual(data.live.map(i => i.url), live);
  assert.equal(data.series[0].url, 'https://cdn.example/episode.webm');
});
