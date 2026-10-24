const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

test('the TV client obtains one session token and sends it on every setup request', async () => {
  const requests = [];
  const context = vm.createContext({
    window: {}, localStorage: { getItem() { return null; } },
    fetch(url, options) {
      requests.push({ url, headers: options.headers });
      return Promise.resolve({ ok: true, json: () => Promise.resolve(url === '/session' ? { token: 'capability' } : { account: null }) });
    },
  });
  vm.runInContext(fs.readFileSync(path.resolve(__dirname, '../tv/js/core.js'), 'utf8'), context);
  await context.IpFlix.setupRequest('/setup/start');
  await context.IpFlix.setupRequest('/setup/poll');
  await context.IpFlix.setupRequest('/setup/stop');
  assert.deepEqual(requests.map(r => r.url), ['/session', '/setup/start', '/setup/poll', '/setup/stop']);
  assert.equal(requests[0].headers['X-IpFlix-Client'], 'tv');
  for (const request of requests.slice(1)) assert.equal(request.headers['X-IpFlix-Token'], 'capability');
});
