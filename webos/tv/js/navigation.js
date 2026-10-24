// Bildschirmstapel mit sichtbarem Zurück-Knopf und Browser-Zurück/Vorwärts.
'use strict';

(function (App) {
  const stack = [];
  let entries = {};
  let serial = 0;
  let session = '';
  let pendingBack = null;
  let useHistory = !!(window.history && window.history.pushState && window.addEventListener);
  const root = () => document.getElementById('app');

  function mount(record) {
    if (!record.screen) record.screen = record.create();
    const screen = record.screen;
    const top = stack.length && stack[stack.length - 1].screen;
    if (top && !screen.isOverlay) {
      top.el.style.display = 'none';
      if (top.onHide) top.onHide();
    }
    if (top && !screen.isOverlay && !screen.backButton) {
      screen.backButton = App.h('button.screen-back', {
        type: 'button', text: '← Zurück', 'aria-label': 'Zurück',
        onclick: (event) => { event.stopPropagation(); App.pop(); },
      });
      screen.el.classList.add('has-back');
      screen.el.appendChild(screen.backButton);
    }
    stack.push(record);
    root().appendChild(screen.el);
    if (screen.onShow) screen.onShow();
  }

  function unmount() {
    const record = stack.pop();
    const screen = record.screen;
    if (screen.onDestroy) screen.onDestroy();
    root().removeChild(screen.el);
    // Vorwärts baut Player neu auf, statt einen zerstörten Decoder zu benutzen.
    if (record.create) record.screen = null;
  }

  function showTop() {
    const screen = stack[stack.length - 1].screen;
    screen.el.style.display = '';
    if (screen.onShow) screen.onShow();
  }

  function remember(replace) {
    if (!useHistory) return;
    const id = ++serial;
    entries[id] = stack.slice();
    try {
      window.history[replace ? 'replaceState' : 'pushState']({ ipflix: session, entry: id }, '');
    } catch (e) {
      useHistory = false;
    }
  }

  App.push = function (screen) {
    mount({ screen: screen, create: screen.recreate || null });
    remember(stack.length === 1);
  };

  App.pop = function (afterPop) {
    if (stack.length < 2 || pendingBack) return false;
    if (useHistory && window.history.state && window.history.state.ipflix === session) {
      pendingBack = { complete: afterPop };
      window.history.back();
    } else {
      unmount();
      showTop();
      if (afterPop) afterPop();
    }
    return true;
  };

  App.reset = function (screen) {
    while (stack.length) unmount();
    App.clear(root());
    entries = {};
    pendingBack = null;
    session = Date.now().toString(36) + '-' + (++serial);
    App.push(screen);
  };

  App.dispatchKey = function (key) {
    const screen = stack.length && stack[stack.length - 1].screen;
    if (screen && screen.onKey && screen.onKey(key)) return;
    if (key === 'back') App.pop();
  };

  if (useHistory) window.addEventListener('popstate', (event) => {
    const state = event.state;
    const pending = pendingBack;
    pendingBack = null;
    if (!state || state.ipflix !== session || !entries[state.entry]) return;
    const target = entries[state.entry];
    let common = 0;
    while (common < stack.length && common < target.length && stack[common] === target[common]) common++;
    while (stack.length > common) unmount();
    if (common === target.length) showTop();
    else for (let i = common; i < target.length; i++) mount(target[i]);
    if (pending && pending.complete) pending.complete();
  });

  if (window.addEventListener) window.addEventListener('resize', () => {
    const screen = stack.length && stack[stack.length - 1].screen;
    if (screen && screen.onResize) screen.onResize();
  });
})(IpFlix);
