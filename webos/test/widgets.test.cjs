const { test } = require('node:test');
const assert = require('node:assert/strict');
const { Element, domFixture } = require('./dom_fixture.cjs');

function fixture() {
  const dom = domFixture();
  dom.load('widgets.js');
  return dom;
}

for (const type of ['VList', 'Row', 'Grid']) {
  test(type + ': clicking an item without prior hover activates the clicked item', () => {
    const { App } = fixture();
    let selected;
    const options = {
      render: () => new Element(), tile: () => new Element(),
      width: 11, height: 15, gap: 1,
      onActivate(item) { selected = item; },
    };
    const widget = new App[type](options);
    widget.setItems(['first', 'second', 'third'], 0);
    widget.nodes[2].fire('click');
    assert.equal(selected, 'third');
    assert.equal(widget.index, 2);
  });
}

test('episode lists allow the outer page to handle wheel events', () => {
  const { App } = fixture();
  const container = new Element();
  const list = new App.VList({ scrollContainer: () => container });
  let prevented = false;
  list.el.fire('wheel', { deltaY: 100, preventDefault() { prevented = true; } });
  assert.equal(prevented, false);
  assert.equal(list.el.scrollTop, 0);
});

test('grid rendering repairs zero-sized tiles after a hidden panel becomes visible', () => {
  const { App } = fixture();
  const grid = new App.Grid({ width: 11, height: 15, gap: 1, tile: () => new Element() });
  grid.el.clientWidth = 0;
  grid.el.clientHeight = 0;
  grid.setItems(['first', 'second', 'third'], 0);
  assert.equal(grid.nodes[0].style.width, '0px');
  grid.el.clientWidth = 960;
  grid.el.clientHeight = 400;
  grid.render();
  assert.ok(parseFloat(grid.nodes[0].style.width) > 0);
  assert.ok(parseFloat(grid.nodes[0].style.height) > 0);
  grid.el.clientWidth = 600;
  grid.render();
  assert.equal(parseFloat(grid.nodes[0].style.width), grid.metrics().w);
});

test('keyboard focus reveals later episodes while pointer focus preserves scrolling', () => {
  const { App } = fixture();
  const container = new Element();
  container.bounds = { top: 0, bottom: 200, height: 200 };
  const list = new App.VList({ render: () => new Element(), scrollContainer: () => container });
  list.setItems(['first', 'last'], 0);
  list.nodes[1].bounds = { top: 280, bottom: 330, height: 50 };
  list.focusIndex(1, true);
  assert.equal(container.scrollTop, 0);
  list.focusIndex(1);
  assert.equal(container.scrollTop, 142);
});

test('a stationary pointer cannot reset the episode selected with the keyboard', () => {
  const { App } = fixture();
  const list = new App.VList({ render: () => new Element() });
  list.setItems(['first', 'second', 'last'], 2);
  App.usingKeyboard = true;
  list.nodes[0].fire('mouseover');
  list.nodes[0].fire('mousemove');
  assert.equal(list.index, 2);
  App.usingKeyboard = false;
  list.nodes[0].fire('mousemove');
  assert.equal(list.index, 0);
});

test('pointer activation is distinguished from keyboard zone changes', () => {
  const { App } = fixture();
  const container = new Element();
  container.bounds = { top: 0, bottom: 200, height: 200 };
  const row = new App.Row({ render: () => new Element(), scrollContainer: () => container });
  row.setItems(['item'], 0);
  row.nodes[0].bounds = { top: 280, bottom: 330, height: 50 };
  const zones = new App.Zones();
  zones.add(row, {});
  let fromPointer;
  zones.onChange = (zone, pointer) => { fromPointer = pointer; };
  zones.activate(row, true);
  assert.equal(fromPointer, true);
  assert.equal(container.scrollTop, 0);
});

test('horizontal rows stay under the pointer while keyboard navigation reveals later items', () => {
  const { App } = fixture();
  const row = new App.Row({ render: () => new Element() });
  row.setItems(['first', 'last']);
  row.el.clientWidth = 300;
  row.el.scrollWidth = 800;
  row.el.scrollLeft = 40;
  row.nodes[1].offsetLeft = 600;
  row.nodes[1].offsetWidth = 100;
  row.nodes[1].fire('mousemove');
  assert.equal(row.index, 1);
  assert.equal(row.el.scrollLeft, 40, 'hover must not move the pending click target');
  row.focusIndex(1);
  assert.equal(row.el.scrollLeft, 500);
});
