const { test } = require('node:test');
const assert = require('node:assert/strict');
const { Element, domFixture } = require('./dom_fixture.cjs');

function fixture(withHistory = true) {
  const dom = domFixture();
  const events = {};
  const entries = [];
  const queue = [];
  let position = -1;
  const history = {
    get state() { return entries[position]; },
    replaceState(state) { if (position < 0) position = 0; entries[position] = state; },
    pushState(state) { entries.splice(++position); entries.push(state); },
    back() { if (position > 0) queue.push(entries[--position]); },
    forward() { if (position < entries.length - 1) queue.push(entries[++position]); },
    flush() { while (queue.length) events.popstate({ state: queue.shift() }); },
  };
  dom.context.window = { addEventListener(name, callback) { events[name] = callback; } };
  if (withHistory) dom.context.window.history = history;
  dom.load('navigation.js');
  const created = {};
  const destroyed = {};
  function screen(name, overlay = false) {
    created[name] = (created[name] || 0) + 1;
    return {
      el: new Element(), isOverlay: overlay,
      recreate: () => screen(name, overlay),
      onKey() { return false; },
      onDestroy() { destroyed[name] = (destroyed[name] || 0) + 1; },
    };
  }
  return { ...dom, history, screen, created, destroyed };
}

test('visible back button returns to the same parent and preserves its position', () => {
  const app = fixture();
  const home = app.screen('home');
  const details = app.screen('details');
  app.App.reset(home);
  app.App.push(details);
  details.el.scrollTop = 500;
  const player = app.screen('player');
  app.App.push(player);
  assert.equal(home.backButton, undefined);
  assert.equal(player.backButton.tagName, 'BUTTON');
  player.backButton.fire('click');
  app.history.flush();
  assert.equal(app.root.children.length, 2);
  assert.equal(app.root.children[1], details.el);
  assert.equal(details.el.scrollTop, 500);
  assert.equal(details.el.style.display, '');
  assert.equal(app.destroyed.player, 1);
});

test('browser back and forward recreate destroyed child screens', () => {
  const app = fixture();
  const home = app.screen('home');
  app.App.reset(home);
  app.App.push(app.screen('details'));
  app.history.back();
  app.history.flush();
  assert.equal(app.root.children.length, 1);
  app.history.forward();
  app.history.flush();
  assert.equal(app.root.children.length, 2);
  assert.equal(app.created.details, 2);
  assert.equal(app.destroyed.details, 1);
});

test('confirmation actions execute after the dialog has been removed', () => {
  const app = fixture();
  app.App.reset(app.screen('home'));
  app.App.push(app.screen('confirm', true));
  let completed = false;
  app.App.pop(() => { assert.equal(app.root.children.length, 1); completed = true; });
  assert.equal(completed, false);
  app.history.flush();
  assert.equal(completed, true);
});

test('Escape uses the same back navigation and rapid repeats do not skip screens', () => {
  const app = fixture();
  app.App.reset(app.screen('home'));
  app.App.push(app.screen('details'));
  app.App.push(app.screen('player'));
  app.App.dispatchKey('back');
  app.App.dispatchKey('back');
  app.history.flush();
  assert.equal(app.root.children.length, 2);
  assert.equal(app.destroyed.player, 1);
  assert.equal(app.destroyed.details, undefined);
});

test('navigation still works without browser history support', () => {
  const app = fixture(false);
  app.App.reset(app.screen('home'));
  app.App.push(app.screen('details'));
  app.App.dispatchKey('back');
  assert.equal(app.root.children.length, 1);
});
