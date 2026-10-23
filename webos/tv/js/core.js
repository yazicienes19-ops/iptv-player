// IpFlix für LG webOS 4 (Chrome 53): Grundbausteine.
// Erlaubt ist ES2015 ohne async/await, Object.values/entries, Objekt-Spread,
// optional chaining und padStart. CSS ohne Grid und ohne `gap`.
'use strict';

var IpFlix = (window.IpFlix = {});

(function (App) {
  // ---------- Speicher ----------

  const PREFIX = 'ipflix.';

  App.load = function (key, fallback) {
    try {
      const raw = localStorage.getItem(PREFIX + key);
      return raw == null ? fallback : JSON.parse(raw);
    } catch (e) {
      return fallback;
    }
  };

  App.save = function (key, value) {
    try {
      if (value == null) localStorage.removeItem(PREFIX + key);
      else localStorage.setItem(PREFIX + key, JSON.stringify(value));
    } catch (e) {
      // Speicher voll oder gesperrt: nur diese Sitzung merkt es sich.
    }
  };

  App.wipe = function () {
    try {
      Object.keys(localStorage)
        .filter((k) => k.indexOf(PREFIX) === 0)
        .forEach((k) => localStorage.removeItem(k));
    } catch (e) {
      // nichts zu tun
    }
  };

  // ---------- Einstellungen ----------

  App.USER_AGENTS = [
    { label: 'IPTV Smarters', value: 'IPTVSmartersPlayer' },
    { label: 'VLC', value: 'VLC/3.0.20 LibVLC/3.0.20' },
    { label: 'Apple TV', value: 'AppleCoreMedia/1.0.0.21A342 (Apple TV; U; CPU OS 17_0 like Mac OS X)' },
    { label: 'Fernseher (ohne Tarnung)', value: '' },
  ];

  const DEFAULT_SETTINGS = {
    userAgent: 'IPTVSmartersPlayer',
    liveFormat: 'm3u8',
    // Kürzel wie "DE", "TR"; leer = alle Länder zeigen.
    countries: [],
  };

  App.settings = Object.assign({}, DEFAULT_SETTINGS, App.load('settings', {}));

  App.updateSettings = function (patch) {
    App.settings = Object.assign({}, App.settings, patch);
    App.save('settings', App.settings);
  };

  // ---------- Netz ----------

  /// Leitet über den Hilfsdienst (webos/service/proxy.js) mit getarntem User-Agent.
  App.proxied = function (url) {
    if (!url || !/^https?:\/\//i.test(url)) return url || '';
    const ua = App.settings.userAgent;
    return '/p?u=' + encodeURIComponent(url) + (ua ? '&ua=' + encodeURIComponent(ua) : '');
  };

  function withTimeout(promise, ms) {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Server antwortet nicht (Zeitüberschreitung).')), ms);
      promise.then(
        (v) => {
          clearTimeout(timer);
          resolve(v);
        },
        (e) => {
          clearTimeout(timer);
          reject(e);
        }
      );
    });
  }

  App.fetchText = function (url, timeoutMs) {
    return withTimeout(
      fetch(App.proxied(url)).then((r) => {
        if (!r.ok) throw new Error(describeStatus(r.status));
        return r.text();
      }),
      timeoutMs || 60000
    );
  };

  App.fetchJson = function (url, timeoutMs) {
    return App.fetchText(url, timeoutMs).then((text) => {
      try {
        return JSON.parse(text);
      } catch (e) {
        throw new Error('Ungültige Antwort vom Server.');
      }
    });
  };

  function describeStatus(status) {
    if (status === 401 || status === 403) return 'Zugriff verweigert (' + status + '). Abo abgelaufen oder zu viele Verbindungen?';
    if (status === 404) return 'Nicht gefunden (404).';
    if (status === 502) return 'Server nicht erreichbar.';
    if (status === 504) return 'Server antwortet nicht (Zeitüberschreitung).';
    return 'Server-Fehler ' + status + '.';
  }

  // ---------- Tasten ----------

  const KEYS = {
    13: 'ok',
    37: 'left',
    38: 'up',
    39: 'right',
    40: 'down',
    461: 'back',
    27: 'back',
    33: 'chup',
    34: 'chdown',
    403: 'red',
    404: 'green',
    405: 'yellow',
    406: 'blue',
    415: 'play',
    19: 'pause',
    413: 'stop',
    417: 'ff',
    412: 'rw',
    457: 'info',
  };

  App.keyName = function (event) {
    // Rücktaste nur außerhalb von Eingabefeldern als „Zurück“ werten.
    if (event.keyCode === 8 && !isTyping()) return 'back';
    return KEYS[event.keyCode] || null;
  };

  function isTyping() {
    const el = document.activeElement;
    return !!el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA');
  }
  App.isTyping = isTyping;

  // ---------- DOM ----------

  /// h('div.tile.focus', {text: 'x', onclick: fn}, [kinder])
  App.h = function (selector, props, children) {
    const parts = selector.split('.');
    const el = document.createElement(parts[0] || 'div');
    if (parts.length > 1) el.className = parts.slice(1).join(' ');
    if (props) {
      Object.keys(props).forEach((key) => {
        const value = props[key];
        if (value == null) return;
        if (key === 'text') el.textContent = value;
        else if (key === 'html') el.innerHTML = value;
        else if (key === 'style') el.setAttribute('style', value);
        else if (key.indexOf('on') === 0) el.addEventListener(key.slice(2), value);
        else if (key in el && key !== 'list') el[key] = value;
        else el.setAttribute(key, value);
      });
    }
    (children || []).forEach((child) => {
      if (child == null || child === false) return;
      el.appendChild(typeof child === 'string' ? document.createTextNode(child) : child);
    });
    return el;
  };

  App.clear = function (el) {
    while (el.firstChild) el.removeChild(el.firstChild);
  };

  /// Bild über den Hilfsdienst laden; bei Fehler bleibt der Platzhalter sichtbar.
  App.image = function (url, className) {
    const img = App.h('img.' + (className || 'img'), { alt: '' });
    if (!url) {
      img.style.visibility = 'hidden';
      return img;
    }
    img.style.opacity = '0';
    img.onload = function () {
      img.style.opacity = '1';
      // Initialen dahinter ausblenden, sonst scheinen sie durch transparente Logos.
      if (img.parentNode) img.parentNode.classList.add('has-img');
    };
    img.onerror = function () {
      img.style.visibility = 'hidden';
    };
    img.src = App.proxied(url);
    return img;
  };

  /// Initialen als Ersatz für fehlende Logos.
  App.monogram = function (name) {
    const words = (name || '?').replace(/[^\wäöüÄÖÜçğışÇĞİŞ ]/g, ' ').trim().split(/\s+/);
    return ((words[0] || '?').charAt(0) + (words[1] ? words[1].charAt(0) : '')).toUpperCase();
  };

  const ICONS = {
    search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="M15.5 15.5L21 21"/>',
    live: '<rect x="3" y="6" width="18" height="12" rx="2"/><path d="M8 21h8M9 2l3 4 3-4"/>',
    movie: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 4v16M17 4v16M3 9h4M3 15h4M17 9h4M17 15h4"/>',
    series: '<rect x="6" y="3" width="15" height="12" rx="2"/><path d="M3 7v12a2 2 0 0 0 2 2h12"/>',
    star: '<path d="M12 3l2.8 5.8 6.2.9-4.5 4.4 1 6.2L12 17.4l-5.5 2.9 1-6.2L3 9.7l6.2-.9z"/>',
    settings: '<path d="M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12M20 18h0"/><circle cx="16" cy="6" r="2"/><circle cx="10" cy="12" r="2"/><circle cx="18" cy="18" r="2"/>',
    play: '<path d="M7 4l13 8-13 8z" fill="currentColor"/>',
    check: '<path d="M4 12l5 5L20 6"/>',
  };

  App.icon = function (name) {
    const span = App.h('span.icon');
    span.innerHTML =
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
      (ICONS[name] || '') +
      '</svg>';
    return span;
  };

  // ---------- Text ----------

  App.formatTime = function (seconds) {
    seconds = Math.max(0, Math.floor(seconds || 0));
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = seconds % 60;
    const two = (n) => (n < 10 ? '0' : '') + n;
    return (h > 0 ? h + ':' + two(m) : m) + ':' + two(s);
  };

  App.clock = function (date) {
    const two = (n) => (n < 10 ? '0' : '') + n;
    return two(date.getHours()) + ':' + two(date.getMinutes());
  };

  App.normalize = function (text) {
    return (text || '')
      .toLowerCase()
      .replace(/ä/g, 'a')
      .replace(/ö/g, 'o')
      .replace(/ü/g, 'u')
      .replace(/ß/g, 'ss')
      .replace(/ç/g, 'c')
      .replace(/ğ/g, 'g')
      .replace(/ı/g, 'i')
      .replace(/ş/g, 's');
  };

  /// Länderkürzel am Anfang eines Kategorienamens: "DE | Sport", "|TR| Film", "UK: News".
  App.countryOf = function (name) {
    const match = /^\s*[|[(]?\s*([A-Za-z]{2,3})\s*[|\])}:\-]/.exec(name || '');
    return match ? match[1].toUpperCase() : null;
  };

  App.passesCountryFilter = function (categoryName) {
    const wanted = App.settings.countries;
    if (!wanted || !wanted.length) return true;
    const country = App.countryOf(categoryName);
    // Kategorien ohne Kürzel bleiben sichtbar, sonst verschwinden ganze Listen.
    return !country || wanted.indexOf(country) >= 0;
  };

  // ---------- Hinweise ----------

  let toastTimer = null;
  App.toast = function (text) {
    let el = document.getElementById('toast');
    if (!el) {
      el = App.h('div.toast', { id: 'toast' });
      document.body.appendChild(el);
    }
    el.textContent = text;
    el.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.remove('show'), 3000);
  };
})(IpFlix);
