const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

// Exercise the production key map and document handler together. Dispatch is
// observed at the screen boundary; native browser actions must stay unblocked.
function fixture() {
  const listeners = {};
  const document = {
    activeElement: null,
    addEventListener(name, callback) { listeners[name] = callback; },
  };
  const context = vm.createContext({
    document, window: {}, localStorage: { getItem() { return null; } },
    setInterval() {},
  });
  const load = file => vm.runInContext(fs.readFileSync(path.resolve(__dirname, '../tv/js', file), 'utf8'), context);
  load('core.js');
  const App = context.IpFlix;
  const dispatched = [];
  App.LoginScreen = function () {};
  App.reset = () => {};
  App.dispatchKey = key => dispatched.push(key);
  load('main.js');
  return {
    App, document, dispatched,
    focus(tagName, properties = {}) {
      const element = Object.assign({
        tagName, type: 'text', blurCalls: 0,
        blur() { this.blurCalls++; document.activeElement = null; },
        closest() { return null; },
      }, properties);
      document.activeElement = element;
      return element;
    },
    key(keyCode, extra = {}) {
      const event = Object.assign({ keyCode, prevented: false, preventDefault() { this.prevented = true; } }, extra);
      listeners.keydown(event);
      return event;
    },
    move(x, y) { listeners.mousemove({ clientX: x, clientY: y }); },
  };
}

test('Tab enters keyboard mode while preserving native focus traversal', () => {
  const f = fixture();
  f.move(20, 30);
  assert.equal(f.App.usingKeyboard, false);
  assert.equal(f.key(9, { key: 'Tab' }).prevented, false);
  assert.equal(f.App.usingKeyboard, true);
  assert.deepEqual(f.dispatched, []);
  f.move(20, 30);
  assert.equal(f.App.usingKeyboard, true, 'stationary-pointer events must not clear keyboard mode');
  f.move(21, 30);
  assert.equal(f.App.usingKeyboard, false);
});

test('range arrows stay native and visible; Down and Escape still reach the player', () => {
  const f = fixture();
  const range = f.focus('INPUT', { type: 'range' });
  f.move(0, 0);
  for (const key of [37, 39]) {
    assert.equal(f.key(key).prevented, false);
    assert.equal(f.App.usingKeyboard, true);
    assert.equal(f.document.activeElement, range);
  }
  assert.deepEqual(f.dispatched, []);
  assert.equal(f.key(40).prevented, true);
  assert.equal(f.key(27).prevented, true);
  assert.deepEqual(f.dispatched, ['down', 'back']);
});

test('native player buttons keep Enter and Space activation and preserve focus for arrows', () => {
  const f = fixture();
  const button = f.focus('BUTTON', { closest(selector) { return selector === '.player' ? {} : null; } });
  assert.equal(f.key(13).prevented, false);
  assert.equal(f.key(32).prevented, false);
  assert.deepEqual(f.dispatched, []);
  assert.equal(f.key(39).prevented, true);
  assert.equal(button.blurCalls, 0);
  assert.equal(f.document.activeElement, button);
  assert.equal(f.key(27).prevented, true);
  assert.deepEqual(f.dispatched, ['right', 'back']);
});

test('ordinary buttons hand arrow navigation back to virtual screen focus', () => {
  const f = fixture();
  const button = f.focus('BUTTON');
  assert.equal(f.key(39).prevented, true);
  assert.equal(button.blurCalls, 1);
  assert.deepEqual(f.dispatched, ['right']);
});

test('playback shortcuts do not hijack search text or browser shortcut combinations', () => {
  const f = fixture();
  f.focus('INPUT', { type: 'search' });
  for (const key of [32, 70, 77, 37, 39]) assert.equal(f.key(key).prevented, false);
  assert.deepEqual(f.dispatched, []);
  f.document.activeElement = null;
  assert.equal(f.key(70, { metaKey: true }).prevented, false);
  assert.equal(f.key(70, { ctrlKey: true }).prevented, false);
  assert.deepEqual(f.dispatched, []);
  for (const key of [32, 70, 77]) assert.equal(f.key(key).prevented, true);
  assert.deepEqual(f.dispatched, ['space', 'fullscreen', 'mute']);
});
