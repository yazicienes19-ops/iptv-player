const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

class Element {
  constructor(selector = 'div') {
    const [tag, ...classes] = selector.split('.');
    this.tagName = tag.toUpperCase();
    const values = new Set(classes);
    this.classList = {
      add: value => values.add(value),
      contains: value => values.has(value),
      toggle(value, active) { if (active) values.add(value); else values.delete(value); },
    };
    this.children = [];
    this.style = {};
    this.listeners = {};
    this.scrollTop = this.scrollLeft = this.scrollWidth = 0;
    this.clientWidth = 960;
    this.clientHeight = 400;
    this.bounds = { top: 0, bottom: 40, height: 40 };
  }
  get firstChild() { return this.children[0]; }
  appendChild(node) { this.children.push(node); }
  removeChild(node) { this.children.splice(this.children.indexOf(node), 1); }
  addEventListener(name, callback) { (this.listeners[name] ||= []).push(callback); }
  fire(name, event = { stopPropagation() {} }) {
    for (const callback of this.listeners[name] || []) callback(event);
  }
  getBoundingClientRect() { return this.bounds; }
}

function domFixture() {
  const root = new Element();
  const App = {
    h(selector, props, children) {
      const element = new Element(selector);
      for (const [name, value] of Object.entries(props || {})) {
        if (name.startsWith('on')) element.addEventListener(name.slice(2), value);
        else element[name] = value;
      }
      for (const child of children || []) if (child) element.appendChild(child);
      return element;
    },
    clear(element) { element.children = []; },
  };
  const context = vm.createContext({
    IpFlix: App,
    document: { getElementById() { return root; }, documentElement: {} },
    getComputedStyle() { return { fontSize: '16px' }; },
  });
  return {
    App, root, context,
    load(file) { vm.runInContext(fs.readFileSync(path.resolve(__dirname, '../tv/js', file), 'utf8'), context); },
  };
}

module.exports = { Element, domFixture };
