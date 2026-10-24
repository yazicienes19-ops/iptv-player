const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function proxyFixture() {
  const directory = path.resolve(__dirname, '../service');
  let polls = 0;
  const account = { username: 'test', password: 'secret' };
  const server = { on() { return this; }, listen(port, host, cb) { cb(); } };
  const context = vm.createContext({
    __dirname: directory, Buffer, process: { env: {} },
    setInterval() {}, console: { log() {} },
    require(name) {
      if (name === 'http') return {
        createServer() { return server; },
        request() { throw new TypeError('Invalid request'); },
      };
      if (name === './setup') return { poll() { polls++; return account; }, stop() {} };
      if (name === 'webos-service') throw new Error('Not on a TV');
      return require(name);
    },
  });
  vm.runInContext(fs.readFileSync(path.join(directory, 'proxy.js'), 'utf8'), context);
  function request(url, headers = {}, method = 'GET') {
    const response = {
      status: null, headers: {},
      setHeader(name, value) { this.headers[name.toLowerCase()] = value; },
      writeHead(status, headers) {
        this.status = status;
        for (const [name, value] of Object.entries(headers)) this.setHeader(name, value);
      },
      end(body) { this.body = body; },
    };
    context.handle({ url, method, headers: { host: '127.0.0.1:47823', ...headers } }, response);
    return response;
  }
  return { request, polls: () => polls };
}

test('setup credentials require a same-origin session token', () => {
  const app = proxyFixture();
  assert.equal(app.request('/setup/poll').status, 403);
  assert.equal(app.request('/setup/poll', { origin: 'http://other.example' }).status, 403);
  assert.equal(app.request('/session').status, 403);
  assert.equal(app.request('/session', { origin: 'http://other.example', 'x-ipflix-client': 'tv' }).status, 403);
  assert.equal(app.polls(), 0);

  const session = app.request('/session', { 'x-ipflix-client': 'tv' });
  assert.equal(session.status, 200);
  assert.equal(session.headers['access-control-allow-origin'], undefined);
  const token = JSON.parse(session.body).token;
  assert.equal(token.length, 48);
  assert.equal(app.request('/setup/poll', { 'x-ipflix-token': 'wrong' }).status, 403);
  const headers = { 'x-ipflix-token': token };
  assert.equal(app.request('/setup/poll', { ...headers, origin: 'http://other.example' }).status, 403);
  assert.equal(app.request('/setup/poll', { ...headers, 'sec-fetch-site': 'cross-site' }).status, 403);
  assert.equal(app.polls(), 0);
  const result = app.request('/setup/poll', headers);
  assert.equal(result.status, 200);
  assert.equal(JSON.parse(result.body).account.password, 'secret');
  assert.equal(result.headers['access-control-allow-origin'], undefined);
  assert.equal(app.polls(), 1);
});

test('only the empty bootstrap ping allows cross-origin reads', () => {
  const app = proxyFixture();
  const ping = app.request('/ping', { origin: 'null' });
  assert.equal(ping.status, 204);
  assert.equal(ping.headers['access-control-allow-origin'], '*');
  assert.equal(app.request('/setup/start', {}, 'OPTIONS').status, 403);
  assert.equal(app.request('/ping', { host: 'rebound.example:47823' }).status, 403);
});

test('malformed file paths return an error and leave the service usable', () => {
  const app = proxyFixture();
  for (const pathname of ['/%', '/%E0%A4%A', '/%00', '/%2e%2e/service/proxy.js', '/%2e%2e/tv-secret/password']) {
    const response = app.request(pathname);
    assert.ok([400, 403].includes(response.status), pathname);
  }
  assert.equal(app.request('/ping').status, 204);
});

test('malformed upstream URLs and headers return errors instead of throwing', () => {
  const app = proxyFixture();
  for (const target of ['http://[invalid', 'http://media.example:99999/a', 'http://media.example/a']) {
    assert.equal(app.request('/p?u=' + encodeURIComponent(target)).status, 400);
  }
  assert.equal(app.request('/p?u=http%3A%2F%2Fexample.com&ua=hello%0D%0AInjected%3Ayes').status, 400);
  assert.equal(app.request('/ping').status, 204);
});
