// IpFlix-Hilfsdienst für LG webOS.
//
// Der Browser auf dem Fernseher sperrt Anfragen an fremde Server (CORS), und
// IPTV-Anbieter erlauben sie fast nie. Dieser Dienst läuft auf dem Fernseher
// selbst und erledigt deshalb zwei Dinge unter http://127.0.0.1:47823:
//   /        liefert die Oberfläche aus www/ aus (webos/tv, gleicher Ursprung wie /p)
//   /p?u=…   holt eine fremde Adresse (API, M3U, Logos, Video) und reicht sie
//            mit dem gewählten User-Agent durch; HLS-Listen werden so
//            umgeschrieben, dass auch Segmente und Tonspuren hier durchlaufen.
//
// Nur ES5 und alte Node-APIs: ältere Fernseher bringen Node 0.12 bzw. 8 mit.
// Am Mac zum Testen: `node webos/service/proxy.js` (ohne webos-service).

var http = require('http');
var https = require('https');
var url = require('url');
var fs = require('fs');
var path = require('path');
var zlib = require('zlib');
var crypto = require('crypto');
var setup = require('./setup');

var PORT = Number(process.env.IPFLIX_PORT) || 47823;
var HOST = '127.0.0.1';
var WWW = path.join(__dirname, 'www');
// Direkt aus dem Checkout starten; im TV-Paket liegt die Oberfläche in www/.
if (!fs.existsSync(WWW)) WWW = path.resolve(__dirname, '../tv');
var SESSION_TOKEN = crypto.randomBytes(24).toString('hex');
var MAX_REDIRECTS = 5;
var UPSTREAM_TIMEOUT_MS = 30000;
// Ohne Lebenszeichen der App (alle 60 s) beendet sich der Dienst.
var IDLE_MS = 5 * 60 * 1000;

// Ältere Fernseher bringen veraltete Stammzertifikate mit (HTTPS scheitert mit
// „self signed certificate in certificate chain“). Deshalb liegt eine aktuelle
// Liste bei (cacert.pem, aus scripts/build_webos.sh).
var CA = loadCertificates(path.join(__dirname, 'cacert.pem'));

function loadCertificates(file) {
  try {
    return fs.readFileSync(file, 'utf8').match(/-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----/g) || undefined;
  } catch (e) {
    return undefined;
  }
}

var MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.css': 'text/css',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.ico': 'image/x-icon',
  '.bin': 'application/octet-stream'
};

var server = null;
var listening = false;
var waiting = [];
var lastSeen = Date.now();
var onIdle = null;

function sendError(res, status, text) {
  if (res.headersSent) return res.end();
  res.writeHead(status, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end(text);
}

function proxiedUrl(address, ua) {
  return '/p?u=' + encodeURIComponent(address) + (ua ? '&ua=' + encodeURIComponent(ua) : '');
}

function isPlaylist(address, contentType) {
  return /mpegurl/i.test(contentType || '') || /\.m3u8(\?|$)/i.test(url.parse(address).pathname || '');
}

// Alle Adressen einer HLS-Liste (Zeilen und URI="…") absolut machen und über /p
// leiten. Direkt kann der Abspieler des Fernsehers HTTPS nicht laden (veraltete
// Zertifikate). Über HTTPS schafft das alte Node allerdings nur etwa 4 Mbit/s,
// über HTTP rund 28 Mbit/s.
function rewritePlaylist(text, base, ua) {
  return text.split(/\r?\n/).map(function (line) {
    var trimmed = line.trim();
    if (!trimmed) return line;
    if (trimmed.charAt(0) === '#') {
      return line.replace(/URI="([^"]+)"/g, function (_, uri) {
        return 'URI="' + proxiedUrl(url.resolve(base, uri), ua) + '"';
      });
    }
    return proxiedUrl(url.resolve(base, trimmed), ua);
  }).join('\n');
}

function sendPlaylist(res, response, address, ua) {
  var body = response;
  if (/gzip/i.test(response.headers['content-encoding'] || '')) body = response.pipe(zlib.createGunzip());
  var chunks = [];
  body.on('data', function (chunk) { chunks.push(chunk); });
  body.on('error', function (e) { sendError(res, 502, 'Liste defekt: ' + e.message); });
  body.on('end', function () {
    var text = rewritePlaylist(Buffer.concat(chunks).toString('utf8'), address, ua);
    res.writeHead(response.statusCode, {
      'Content-Type': 'application/vnd.apple.mpegurl',
      'Cache-Control': 'no-cache'
    });
    res.end(text);
  });
}

function proxy(req, res, query) {
  var target = query.u;
  if (typeof target !== 'string' || !/^https?:\/\//i.test(target)) return sendError(res, 400, 'Ungültige Stream-Adresse');
  if (req.method !== 'GET' && req.method !== 'HEAD') return sendError(res, 405, 'Nur GET');
  if (query.ua && (typeof query.ua !== 'string' || /[\r\n]/.test(query.ua))) return sendError(res, 400, 'Ungültiger User-Agent');

  var headers = { 'Accept': req.headers.accept || '*/*', 'Accept-Encoding': 'gzip' };
  if (query.ua) headers['User-Agent'] = query.ua;
  if (req.headers.range) headers['Range'] = req.headers.range;
  // TMDB-Lesetoken (v4) kommt als Bearer-Kopf.
  if (req.headers.authorization) headers['Authorization'] = req.headers.authorization;

  function fetch(address, redirects) {
    var options;
    try {
      options = url.parse(address);
      if (!/^https?:$/.test(options.protocol) || !options.hostname ||
          (options.port && (!/^\d+$/.test(options.port) || Number(options.port) > 65535))) {
        return sendError(res, redirects ? 502 : 400, 'Ungültige Stream-Adresse');
      }
    } catch (e) {
      return sendError(res, redirects ? 502 : 400, 'Ungültige Stream-Adresse');
    }
    options.method = req.method;
    options.headers = headers;
    if (CA && options.protocol === 'https:') options.ca = CA;
    var client = options.protocol === 'https:' ? https : http;
    var upstream;
    try {
      upstream = client.request(options, function (response) {
        var location = response.headers.location;
        if (response.statusCode >= 300 && response.statusCode < 400 && location) {
          response.resume();
          if (redirects >= MAX_REDIRECTS) return sendError(res, 508, 'Zu viele Weiterleitungen');
          var nextAddress;
          try {
            nextAddress = url.resolve(address, location);
          } catch (e) {
            return sendError(res, 502, 'Ungültige Weiterleitung');
          }
          return fetch(nextAddress, redirects + 1);
        }
        if (response.statusCode < 300 && isPlaylist(address, response.headers['content-type'])) {
          return sendPlaylist(res, response, address, query.ua);
        }
        var out = {};
        ['content-type', 'content-length', 'content-encoding', 'content-range', 'accept-ranges', 'last-modified']
          .forEach(function (name) {
            if (response.headers[name]) out[name] = response.headers[name];
          });
        res.writeHead(response.statusCode, out);
        response.on('error', function () { sendError(res, 502, 'Stream wurde unterbrochen'); });
        response.pipe(res);
      });
    } catch (e) {
      return sendError(res, 400, 'Ungültige Stream-Anfrage');
    }
    upstream.setTimeout(UPSTREAM_TIMEOUT_MS, function () {
      upstream.abort();
      sendError(res, 504, 'Zeitüberschreitung');
    });
    upstream.on('error', function (e) {
      sendError(res, 502, 'Server nicht erreichbar: ' + e.message);
    });
    // Bricht die App ab (z. B. Logo nicht mehr sichtbar), auch oben abbrechen.
    res.on('close', function () { upstream.abort(); });
    upstream.end();
  }

  fetch(target, 0);
}

function serveFile(req, res, pathname) {
  if (req.method !== 'GET' && req.method !== 'HEAD') return sendError(res, 405, 'Nur GET');
  var relative;
  try {
    relative = decodeURIComponent(pathname).replace(/^\/+/, '') || 'index.html';
  } catch (e) {
    return sendError(res, 400, 'Ungültiger Dateipfad');
  }
  if (relative.indexOf('\0') !== -1) return sendError(res, 400, 'Ungültiger Dateipfad');
  var file = path.normalize(path.join(WWW, relative));
  if (file.indexOf(WWW + path.sep) !== 0) return sendError(res, 403, 'Verboten');
  fs.stat(file, function (err, stat) {
    if (err || !stat.isFile()) return sendError(res, 404, 'Nicht gefunden');
    res.writeHead(200, {
      'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream',
      'Content-Length': stat.size,
      // Nie zwischenspeichern, damit ein Update sofort greift (liegt ja lokal).
      'Cache-Control': 'no-cache'
    });
    if (req.method === 'HEAD') return res.end();
    var stream = fs.createReadStream(file);
    stream.on('error', function () { sendError(res, 500, 'Datei konnte nicht gelesen werden'); });
    stream.pipe(res);
  });
}

function handle(req, res) {
  // Host-Prüfung verhindert auch DNS-Rebinding auf die lokale Schnittstelle.
  var host = req.headers.host;
  if (host !== HOST + ':' + PORT && host !== 'localhost:' + PORT) return sendError(res, 403, 'Verbotener Host');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  lastSeen = Date.now();
  var parsed;
  try {
    parsed = url.parse(req.url, true);
  } catch (e) {
    return sendError(res, 400, 'Ungültige Anfrage');
  }
  if (parsed.pathname === '/ping') {
    // Die webOS-Startschale kommt von einem anderen Ursprung. Nur dieser
    // inhaltslose Lebenszeichen-Endpunkt darf von dort gelesen werden.
    if (req.method !== 'GET' && req.method !== 'HEAD') return sendError(res, 405, 'Nur GET');
    res.writeHead(204, { 'Access-Control-Allow-Origin': '*' });
    return res.end();
  }
  if ((req.headers.origin && req.headers.origin !== 'http://' + host) ||
      req.headers['sec-fetch-site'] === 'cross-site') return sendError(res, 403, 'Fremder Ursprung');
  if (parsed.pathname === '/session') {
    if (req.method !== 'GET' || req.headers['x-ipflix-client'] !== 'tv') return sendError(res, 403, 'Verboten');
    res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
    return res.end(JSON.stringify({ token: SESSION_TOKEN }));
  }
  if (parsed.pathname === '/p') return proxy(req, res, parsed.query);
  if ((parsed.pathname || '').indexOf('/setup/') === 0) {
    if (req.method !== 'GET' || req.headers['x-ipflix-token'] !== SESSION_TOKEN) return sendError(res, 403, 'Verboten');
    return handleSetup(parsed.pathname, res);
  }
  serveFile(req, res, parsed.pathname || '/');
}

// Nur über 127.0.0.1 erreichbar: Der Login-Bildschirm öffnet, fragt ab und schließt
// die Handy-Eingabeseite (setup.js).
function handleSetup(pathname, res) {
  function json(status, data) {
    res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
    res.end(JSON.stringify(data));
  }
  if (pathname === '/setup/start' || pathname === '/setup/start-tmdb') {
    return setup.start(pathname === '/setup/start-tmdb' ? 'tmdb' : 'login', function (err, address) {
      if (err) json(503, { error: err.message });
      else json(200, { url: address });
    });
  }
  if (pathname === '/setup/poll') return json(200, { account: setup.poll() });
  if (pathname === '/setup/stop') {
    setup.stop();
    return json(200, {});
  }
  sendError(res, 404, 'Nicht gefunden');
}

// Startet den Server einmal; weitere Aufrufe warten nur auf ihn.
function ensureServer(callback) {
  if (listening) return callback(null);
  waiting.push(callback);
  if (server) return;
  server = http.createServer(handle);
  server.on('error', function (e) {
    server = null;
    var pending = waiting;
    waiting = [];
    pending.forEach(function (cb) { cb(e); });
  });
  server.listen(PORT, HOST, function () {
    listening = true;
    var pending = waiting;
    waiting = [];
    pending.forEach(function (cb) { cb(null); });
  });
  setInterval(function () {
    if (Date.now() - lastSeen > IDLE_MS && onIdle) onIdle();
  }, 30000);
}

var Service;
try {
  Service = require('webos-service');
} catch (e) {
  Service = null;
}

if (Service) {
  var service = new Service('com.enesyazici.ipflix.proxy');
  var keepAlive = null;

  // Ohne Aktivität beendet webOS einen Dienst nach wenigen Sekunden.
  onIdle = function () {
    if (keepAlive) service.activityManager.complete(keepAlive, function () { process.exit(0); });
    else process.exit(0);
  };

  service.register('start', function (message) {
    lastSeen = Date.now();
    if (!keepAlive) {
      service.activityManager.create('ipflix-proxy', function (activity) {
        keepAlive = activity;
      });
    }
    ensureServer(function (err) {
      if (err) message.respond({ returnValue: false, errorText: 'Port ' + PORT + ': ' + err.message });
      else message.respond({ returnValue: true, port: PORT });
    });
  });
} else {
  ensureServer(function (err) {
    if (err) throw err;
    console.log('IpFlix-Hilfsdienst auf http://' + HOST + ':' + PORT + '/ (www: ' + WWW + ')');
  });
}
