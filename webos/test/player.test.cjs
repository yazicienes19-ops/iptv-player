const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function classes() {
  const values = new Set();
  return { add(v) { values.add(v); }, remove(v) { values.delete(v); }, contains(v) { return values.has(v); } };
}

function fixture() {
  const App = { h() {}, saveProgress() {} };
  const timers = new Map();
  let timerId = 0;
  vm.runInNewContext(fs.readFileSync(path.resolve(__dirname, '../tv/js/player.js'), 'utf8'), {
    IpFlix: App,
    setTimeout(cb) { timers.set(++timerId, cb); return timerId; },
    clearTimeout(id) { timers.delete(id); }, setInterval() {}, clearInterval() {},
  });
  const player = Object.create(App.PlayerScreen.prototype);
  Object.assign(player, {
    started: true, retries: 0, lastTime: 1,
    video: { currentTime: 2 },
    spinner: { classList: classes() }, error: { classList: classes() }, overlay: { classList: classes() },
    showError() { this.error.classList.add('show'); },
    opens: 0, open() { this.opens++; }, isLive() { return true; },
  });
  return { player, timers };
}

for (const event of ['onPlaying', 'onTime']) {
  test('stream recovery through ' + event + ' cancels the pending restart and error', () => {
    const { player, timers } = fixture();
    player.fail('Simulated stall');
    assert.ok(player.retryTimer);
    player[event]();
    assert.equal(player.retryTimer, null);
    assert.equal(player.retries, 0);
    assert.equal(player.error.classList.contains('show'), false);
    assert.equal(timers.size, 0);
    assert.equal(player.opens, 0);
  });
}

test('a stream that remains stalled still retries', () => {
  const { player, timers } = fixture();
  player.fail('Simulated stall');
  for (let i = 0; i < 5 && timers.size; i++) {
    const [id, callback] = timers.entries().next().value;
    timers.delete(id);
    callback();
  }
  assert.equal(player.opens, 1);
});
