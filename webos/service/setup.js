// Zugangsdaten vom Handy: Der Login-Bildschirm zeigt einen QR-Code auf
// http://<fernseher>:47824/<einmal-code>. Dort gibt man die Daten ein, der
// Fernseher holt sie über /setup/poll ab und meldet sich an.
//
// Die Seite ist nur offen, solange der Login-Bildschirm sie anfordert, höchstens
// 15 Minuten, nimmt genau eine Eingabe an und kennt nur den zufälligen Pfad.
// Nur ES5 (Node 0.12 auf älteren Fernsehern).

var http = require('http');
var os = require('os');
var fs = require('fs');
var path = require('path');
var crypto = require('crypto');
var querystring = require('querystring');

var PORT = 47824;
var LIFETIME_MS = 15 * 60 * 1000;
var MAX_BODY = 8192;
var PAGE = path.join(__dirname, 'setup.html');

var state = null;

function lanAddress() {
  var interfaces = os.networkInterfaces();
  var names = Object.keys(interfaces);
  for (var i = 0; i < names.length; i++) {
    var list = interfaces[names[i]];
    for (var j = 0; j < list.length; j++) {
      if (list[j].family === 'IPv4' && !list[j].internal) return list[j].address;
    }
  }
  return null;
}

function page(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(body);
}

function message(title, text) {
  return '<!DOCTYPE html><html lang="de"><head><meta charset="utf-8">' +
    '<meta name="viewport" content="width=device-width,initial-scale=1">' +
    '<title>IpFlix</title><style>body{margin:0;min-height:100vh;display:flex;align-items:center;' +
    'justify-content:center;background:#0a0c10;color:#f2f3f5;font-family:-apple-system,system-ui,sans-serif;' +
    'text-align:center;padding:24px;box-sizing:border-box}h1{color:#e50914;font-size:26px}p{color:#9aa0ac;font-size:17px}</style>' +
    '</head><body><div><h1>' + title + '</h1><p>' + text + '</p></div></body></html>';
}

function clean(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function accountFrom(form) {
  var tmdbKey = clean(form.tmdbKey);
  if (form.type === 'tmdb') return tmdbKey ? { type: 'tmdb', tmdbKey: tmdbKey } : null;
  var account = loginFrom(form);
  if (account && tmdbKey) account.tmdbKey = tmdbKey;
  return account;
}

function loginFrom(form) {
  if (form.type === 'm3u') {
    var address = clean(form.url);
    return /^https?:\/\//i.test(address) ? { type: 'm3u', url: address } : null;
  }
  var server = clean(form.server);
  var username = clean(form.username);
  var password = typeof form.password === 'string' ? form.password : '';
  if (!server || !username || !password) return null;
  return { type: 'xtream', server: server, username: username, password: password };
}

function handle(req, res) {
  if (!state || req.url.split('?')[0] !== '/' + state.token) return page(res, 404, message('Nicht gefunden', 'Bitte den QR-Code am Fernseher neu scannen.'));
  if (state.account) return page(res, 200, message('Schon übertragen', 'Der Fernseher hat die Daten bereits.'));
  if (req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
    return fs.createReadStream(PAGE).pipe(res);
  }
  if (req.method !== 'POST') return page(res, 405, message('Nicht erlaubt', ''));

  var body = '';
  var tooLarge = false;
  req.setEncoding('utf8');
  req.on('data', function (chunk) {
    body += chunk;
    if (body.length > MAX_BODY) {
      tooLarge = true;
      req.destroy();
    }
  });
  req.on('end', function () {
    if (tooLarge || !state) return;
    var account = accountFrom(querystring.parse(body));
    if (!account) return page(res, 400, message('Unvollständig', 'Bitte alle Felder ausfüllen und erneut senden.'));
    state.account = account;
    page(res, 200, message('Gesendet', 'Der Fernseher meldet sich jetzt an. Stimmt etwas nicht, zeigt er einen neuen QR-Code zum erneuten Versuch.'));
  });
}

/// Öffnet die Eingabeseite im WLAN; callback(err, adresse).
/// mode 'tmdb' zeigt nur das Feld für den TMDB-Schlüssel.
exports.start = function (mode, callback) {
  var ip = lanAddress();
  if (!ip) return callback(new Error('Der Fernseher ist mit keinem Netzwerk verbunden.'));
  var address = function () { return 'http://' + ip + ':' + PORT + '/' + state.token + (state.mode === 'tmdb' ? '?nur=tmdb' : ''); };
  if (state && state.mode !== mode) exports.stop();
  if (state) return callback(null, address());

  var done = false;
  var finish = function (err) {
    if (done) return;
    done = true;
    if (err) return callback(err);
    callback(null, address());
  };
  var server = http.createServer(handle);
  state = { token: crypto.randomBytes(6).toString('hex'), server: server, account: null, mode: mode };
  server.on('error', function (e) {
    exports.stop();
    finish(e);
  });
  server.listen(PORT, '0.0.0.0', function () {
    if (state) state.timer = setTimeout(exports.stop, LIFETIME_MS);
    finish(null);
  });
};

/// Liefert eingegebene Daten genau einmal und schließt die Seite danach.
exports.poll = function () {
  var account = state && state.account;
  if (account) exports.stop();
  return account || null;
};

exports.stop = function () {
  if (!state) return;
  clearTimeout(state.timer);
  try {
    state.server.close();
  } catch (e) {
    // schon geschlossen
  }
  state = null;
};
