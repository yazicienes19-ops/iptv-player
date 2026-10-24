const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function fixture(item = { kind: 'movie', name: 'A film', id: 'film' }, queue) {
  const timers = new Map();
  const intervals = new Map();
  let timerId = 0;
  let watchNow = 0;
  let libraryScope = 'playlist-a';
  const watched = [];
  const vodWatched = [];
  const document = {
    activeElement: null, listeners: {},
    addEventListener(name, listener) { this.listeners[name] = listener; },
    removeEventListener(name) { delete this.listeners[name]; },
  };
  const pageWindow = {
    listeners: {},
    addEventListener(name, listener) { this.listeners[name] = listener; },
    removeEventListener(name) { delete this.listeners[name]; },
  };
  class Element {
    constructor(selector) {
      const [tag, ...classes] = selector.split('.');
      this.tagName = tag.toUpperCase();
      const values = new Set(classes);
      this.classList = {
        add: name => values.add(name), remove: name => values.delete(name), contains: name => values.has(name),
        toggle(name, enabled) { if (enabled) values.add(name); else values.delete(name); },
      };
      this.style = {};
      this.children = [];
      this.listeners = {};
      this.attributes = {};
      this.offsetWidth = this.offsetHeight = 50;
      if (tag === 'video') {
        this.paused = true;
        this.currentTime = 0;
        this.duration = 100;
        this.volume = 1;
        this.muted = false;
        this.playbackRate = 1;
        this.audioTracks = [];
        this.textTracks = [];
      }
    }
    setAttribute(name, value) { this.attributes[name] = value; }
    getAttribute(name) { return this.attributes[name]; }
    removeAttribute(name) { delete this[name]; delete this.attributes[name]; }
    addEventListener(name, fn) { (this.listeners[name] ||= []).push(fn); }
    fire(name, event = {}) {
      event.target ||= this;
      event.stopPropagation ||= () => { event.stopped = true; };
      for (const listener of this.listeners[name] || []) listener(event);
      return event;
    }
    appendChild(child) { this.children.push(child); child.parentElement = this; }
    removeChild(child) { this.children.splice(this.children.indexOf(child), 1); child.parentElement = null; }
    get firstChild() { return this.children[0]; }
    contains(target) { return target === this || this.children.some(child => child.contains(target)); }
    focus() { document.activeElement = this; }
    querySelectorAll(selector) {
      const names = selector.split(',').map(name => name.trim().toUpperCase());
      const result = [];
      for (const child of this.children) {
        if (names.includes(child.tagName)) result.push(child);
        result.push(...child.querySelectorAll(selector));
      }
      return result;
    }
    querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
    play() { this.paused = false; this.fire('play'); return Promise.resolve(); }
    pause() { this.paused = true; this.fire('pause'); }
    load() { this.loaded = true; }
  }
  const saved = [];
  let popped = 0;
  const App = {
    usingKeyboard: false,
    h(selector, props, children) {
      const element = new Element(selector);
      for (const [name, value] of Object.entries(props || {})) {
        if (name.startsWith('on')) element.addEventListener(name.slice(2), value);
        else if (name.startsWith('aria-')) element.setAttribute(name, value);
        else element[name] = value;
      }
      for (const child of children || []) if (child) element.appendChild(child);
      return element;
    },
    clear(element) { while (element.firstChild) element.removeChild(element.firstChild); },
    pop() { popped++; }, toast() {}, resumePosition() { return 0; },
    provider: { streamUrl(item) { return '/stream/' + item.id; }, shortEpg() { return Promise.resolve([]); } },
    proxied(url) { return url; }, addRecent() {}, saveProgress(...args) { saved.push(args); },
    formatTime(seconds) { return String(seconds); }, clock() { return '20:15'; },
    libraryScope() { return libraryScope; },
    recordLiveWatch(item, seconds, scope) { watched.push({ id: item.id, seconds, scope }); },
    recordVodWatch(item, seconds, duration, position, scope) { vodWatched.push({ id: item.id, seconds, duration, position, scope }); },
  };
  vm.runInNewContext(fs.readFileSync(path.resolve(__dirname, '../tv/js/player.js'), 'utf8'), {
    IpFlix: App, document, window: pageWindow, performance: { now() { return watchNow; } },
    setTimeout(callback) { timers.set(++timerId, callback); return timerId; },
    clearTimeout(id) { timers.delete(id); },
    setInterval(callback) { intervals.set(++timerId, callback); return timerId; },
    clearInterval(id) { intervals.delete(id); },
  });
  const player = new App.PlayerScreen(item, queue);
  return {
    player, App, document, timers, intervals, saved, watched, vodWatched, pageWindow, popped: () => popped,
    run(id) { const callback = timers.get(id); timers.delete(id); if (callback) callback(); },
    tick(seconds, mediaSeconds = seconds) {
      watchNow += seconds * 1000;
      player.video.currentTime += mediaSeconds;
      player.video.fire('timeupdate');
    },
    scope(value) { libraryScope = value; },
  };
}

test('live watch time requires actual advancing playback and persists periodically plus on exit', () => {
  const f = fixture({ kind: 'live', name: 'Station', id: 'live' });
  for (let i = 0; i < 3; i++) f.tick(1, 0);
  assert.equal(f.watched.length, 0, 'opening an offline station is not watching');
  f.player.onPlaying();
  for (let i = 0; i < 16; i++) f.tick(1);
  assert.deepEqual(f.watched, [{ id: 'live', seconds: 15, scope: 'playlist-a' }]);
  f.player.onDestroy();
  assert.equal(f.watched.reduce((sum, entry) => sum + entry.seconds, 0), 16);
});

test('live watch time excludes pauses, buffering, errors and start retries', () => {
  const f = fixture({ kind: 'live', name: 'Station', id: 'live' });
  const p = f.player;
  p.onPlaying();
  f.tick(3);
  p.video.pause();
  f.tick(4, 0);
  p.video.play();
  f.tick(2, 0);
  p.onPlaying();
  f.tick(2);
  p.video.fire('waiting');
  f.tick(4, 0);
  p.onPlaying();
  f.tick(1);
  p.fail('offline');
  f.tick(4, 0);
  p.onDestroy();
  assert.equal(f.watched.reduce((sum, entry) => sum + entry.seconds, 0), 6);
});

test('live watch time rejects seeks and clock gaps and measures real time at changed playback rates', () => {
  const f = fixture({ kind: 'live', name: 'Station', id: 'live' });
  const p = f.player;
  p.onPlaying();
  f.tick(1);
  f.tick(1, 80);
  f.tick(20, 20);
  p.video.fire('seeking');
  f.tick(1, 50);
  p.video.fire('seeked');
  p.video.playbackRate = 2;
  f.tick(2, 4);
  p.onDestroy();
  assert.equal(f.watched.reduce((sum, entry) => sum + entry.seconds, 0), 3);
});

test('channel switches preserve watched station and playlist identity; pagehide flushes only once', () => {
  const first = { kind: 'live', id: 'a', name: 'A' };
  const second = { kind: 'live', id: 'b', name: 'B' };
  const f = fixture(first, [first, second]);
  const p = f.player;
  p.onPlaying();
  f.tick(4);
  f.scope('playlist-b');
  p.switchChannel(1);
  p.onPlaying();
  f.tick(2);
  f.pageWindow.listeners.pagehide();
  p.onDestroy();
  assert.deepEqual(f.watched, [
    { id: 'a', seconds: 4, scope: 'playlist-a' },
    { id: 'b', seconds: 2, scope: 'playlist-b' },
  ]);
  assert.equal(f.pageWindow.listeners.pagehide, undefined);
  assert.equal(f.document.listeners.visibilitychange, undefined);
});

test('hidden tabs and suspended time do not inflate station rankings', () => {
  const f = fixture({ kind: 'live', name: 'Station', id: 'live' });
  const p = f.player;
  p.onPlaying();
  f.tick(2);
  f.document.hidden = true;
  f.document.listeners.visibilitychange();
  f.tick(30, 30);
  f.document.hidden = false;
  f.document.listeners.visibilitychange();
  f.tick(1);
  p.onDestroy();
  assert.equal(f.watched.reduce((sum, entry) => sum + entry.seconds, 0), 3);
});

test('movies never contribute to the live station rankings', () => {
  const f = fixture();
  f.player.onPlaying();
  for (let i = 0; i < 20; i++) f.tick(1);
  f.player.onDestroy();
  assert.deepEqual(f.watched, []);
  assert.equal(f.vodWatched.reduce((sum, entry) => sum + entry.seconds, 0), 20);
});

test('VOD recommendation time excludes pauses, buffering and seeks and keeps the playing account', () => {
  const f = fixture();
  const p = f.player;
  p.onPlaying();
  f.tick(4);
  p.video.pause();
  f.tick(10, 0);
  p.video.play();
  p.onPlaying();
  f.tick(3);
  p.video.fire('seeking');
  f.tick(1, 60);
  p.video.fire('seeked');
  f.tick(2);
  p.video.fire('waiting');
  f.tick(4, 0);
  p.onPlaying();
  f.tick(1);
  f.scope('playlist-b');
  p.onDestroy();
  assert.equal(f.vodWatched.reduce((sum, entry) => sum + entry.seconds, 0), 10);
  assert.ok(f.vodWatched.every(entry => entry.scope === 'playlist-a'));
  assert.ok(f.saved.every(entry => entry[3] === 'playlist-a'));
});

test('episode auto-advance flushes genuine viewing to the previous episode and playlist', () => {
  const first = { kind: 'episode', id: 'first', name: 'First', seriesId: 'show' };
  const second = { kind: 'episode', id: 'second', name: 'Second', seriesId: 'show' };
  const f = fixture(first, [first, second]);
  f.player.onPlaying();
  f.tick(4);
  f.player.onEnded();
  assert.deepEqual(f.vodWatched.map(entry => ({ id: entry.id, seconds: entry.seconds, scope: entry.scope })), [
    { id: 'first', seconds: 4, scope: 'playlist-a' },
  ]);
  assert.equal(f.player.item().id, 'second');
});

test('10 second buttons accumulate seeks, clamp safely and timeline seeks directly', () => {
  const f = fixture();
  const p = f.player;
  p.video.currentTime = 20;
  assert.equal(p.forwardButton.fire('click').stopped, true);
  p.forwardButton.fire('click');
  assert.equal(p.video.currentTime, 20);
  assert.equal(p.pendingSeek, 40);
  f.run(p.seekTimer);
  assert.equal(p.video.currentTime, 40);
  p.timeline.value = 73;
  p.timeline.fire('input');
  assert.equal(p.video.currentTime, 73);
  p.seek(-1000);
  f.run(p.seekTimer);
  assert.equal(p.video.currentTime, 0);
  p.video.duration = 0.2;
  p.seek(10);
  f.run(p.seekTimer);
  assert.ok(p.video.currentTime >= 0 && p.video.currentTime < 0.2);
  p.video.duration = Infinity;
  p.seek(10);
  assert.equal(p.pendingSeek, null);
});

test('screen lock blocks controls and shortcuts; back unlocks before leaving', () => {
  const f = fixture();
  const p = f.player;
  p.seek(10);
  const seekTimer = p.seekTimer;
  p.lockButton.fire('click');
  assert.equal(f.timers.has(seekTimer), false);
  assert.equal(p.locked, true);
  assert.equal(p.playButton.disabled, true);
  assert.equal(p.overlay.classList.contains('show'), false);
  p.playButton.fire('click');
  p.video.fire('click');
  p.forwardButton.fire('click');
  p.onKey('space');
  p.onKey('right');
  assert.equal(p.video.paused, false);
  assert.equal(p.pendingSeek, null);
  assert.equal(p.video.currentTime, 0);
  p.backButton.fire('click');
  assert.equal(f.popped(), 0);
  p.onKey('back');
  assert.equal(p.locked, false);
  assert.equal(f.popped(), 0);
  assert.equal(p.playButton.disabled, false);
  p.onKey('back');
  assert.equal(f.popped(), 1);
  p.lockButton.fire('click');
  p.unlockButton.fire('click');
  assert.equal(p.locked, false);
});

test('control nodes and keyboard focus survive progress and overlay updates', () => {
  const f = fixture();
  const p = f.player;
  const timeline = p.timeline;
  const playButton = p.playButton;
  p.playButton.focus();
  p.renderOverlay();
  p.video.currentTime = 42;
  p.onTime();
  p.el.fire('mousemove');
  assert.equal(p.playButton, playButton);
  assert.equal(p.timeline, timeline);
  assert.equal(f.document.activeElement, playButton);
  assert.equal(p.timeline.value, 42);
});

test('controls hide during playback but stay visible while paused or keyboard focused', () => {
  const f = fixture();
  const p = f.player;
  f.run(p.hideTimer);
  assert.equal(p.overlay.classList.contains('show'), false);
  p.togglePause();
  f.run(p.hideTimer);
  assert.equal(p.overlay.classList.contains('show'), true);
  p.togglePause();
  f.App.usingKeyboard = true;
  p.playButton.focus();
  f.run(p.hideTimer);
  assert.equal(p.overlay.classList.contains('show'), true);
});

test('mute and volume controls update actual media volume and accessible state', () => {
  const { player: p } = fixture();
  p.muteButton.fire('click');
  assert.equal(p.video.muted, true);
  assert.equal(p.muteButton.getAttribute('aria-label'), 'Ton einschalten');
  p.volume.value = 0.35;
  p.volume.fire('input');
  assert.equal(p.video.volume, 0.35);
  assert.equal(p.video.muted, false);
  p.onKey('mute');
  assert.equal(p.video.muted, true);
});

test('track menu only offers detected tracks and applies the chosen subtitle', () => {
  const { player: p } = fixture();
  assert.equal(p.tracksButton.style.display, 'none');
  p.video.audioTracks = [{ label: 'Deutsch', enabled: true }, { label: 'English', enabled: false }];
  p.video.textTracks = [{ label: 'Deutsch', mode: 'disabled' }];
  p.updateTracks();
  assert.equal(p.tracksButton.style.display, '');
  p.tracksButton.fire('click');
  const choices = p.trackMenu.querySelectorAll('button');
  assert.deepEqual(choices.map(button => button.textContent), ['✓  Deutsch', 'English', '✓  Untertitel aus', 'Deutsch']);
  choices[3].fire('click');
  assert.equal(p.video.textTracks[0].mode, 'showing');
  assert.equal(p.trackMenu.style.display, 'none');
  p.cycleAudio();
  assert.equal(p.video.audioTracks[0].enabled, false);
  assert.equal(p.video.audioTracks[1].enabled, true);
});

test('next episode saves position, resets a pending seek and opens the next stream', () => {
  const first = { kind: 'episode', id: 'a', name: 'One', seriesName: 'Show', season: 1, number: 1 };
  const second = { kind: 'episode', id: 'b', name: 'Two', seriesName: 'Show', season: 1, number: 2 };
  const f = fixture(first, [first, second]);
  const p = f.player;
  p.video.currentTime = 30;
  p.seek(10);
  const oldSeek = p.seekTimer;
  p.nextButton.fire('click');
  assert.equal(p.item(), second);
  assert.equal(p.video.src, '/stream/b');
  assert.equal(p.pendingSeek, null);
  assert.equal(f.timers.has(oldSeek), false);
  assert.equal(f.saved[0][0], first);
  assert.equal(f.saved[0][1], 30);
  assert.equal(p.nextButton.style.display, 'none');
});

test('fullscreen button reflects supported APIs and calls the correct target', () => {
  const f = fixture();
  const p = f.player;
  assert.equal(p.fullscreenButton.style.display, 'none');
  p.el.requestFullscreen = function () { assert.equal(this, p.el); f.document.fullscreenElement = p.el; };
  f.document.exitFullscreen = function () { assert.equal(this, f.document); f.document.fullscreenElement = null; };
  p.renderFullscreen();
  assert.equal(p.fullscreenButton.style.display, '');
  p.fullscreenButton.fire('click');
  p.renderFullscreen();
  assert.equal(p.fullscreenButton.getAttribute('aria-label'), 'Vollbild verlassen');
  p.fullscreenButton.fire('click');
  assert.equal(f.document.fullscreenElement, null);
});

test('destroying the player cancels timers, detaches listeners and frees decoder', () => {
  const f = fixture();
  const p = f.player;
  p.onPlaying();
  p.seek(10);
  p.onDestroy();
  assert.equal(f.timers.size, 0);
  assert.equal(f.intervals.size, 0);
  assert.equal(Object.keys(f.document.listeners).length, 0);
  assert.equal(p.video.src, undefined);
  assert.equal(p.video.paused, true);
  assert.equal(p.video.loaded, true);
});
