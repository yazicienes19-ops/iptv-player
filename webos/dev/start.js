// Lokale Browser-Vorschau: node webos/dev/start.js (Node 18+, Python 3).
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const { spawn, spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '../..');
const children = [];
let stopping = false;

function stop(code) {
  if (stopping) return;
  stopping = true;
  for (const child of children) child.kill('SIGTERM');
  process.exitCode = code;
}

function start(command, args, env) {
  const child = spawn(command, args, { cwd: root, env: { ...process.env, ...env }, stdio: 'inherit' });
  children.push(child);
  child.on('error', (error) => { console.error(error.message); stop(1); });
  child.on('exit', (code, signal) => {
    if (!stopping) {
      console.error(command + ' wurde beendet (' + (signal || code) + ').');
      stop(code || 1);
    }
  });
}

function waitFor(address) {
  const deadline = Date.now() + 10000;
  return new Promise((resolve, reject) => {
    function attempt() {
      if (stopping) return reject(new Error('Vorschau wurde beendet.'));
      const request = http.get(address, (response) => {
        response.resume();
        if (response.statusCode < 400) resolve();
        else reject(new Error(address + ': HTTP ' + response.statusCode));
      });
      request.setTimeout(1000, () => request.destroy());
      request.on('error', (error) => {
        if (Date.now() >= deadline) reject(new Error('Server startet nicht: ' + address + ' (' + error.message + ')'));
        else setTimeout(attempt, 150);
      });
    }
    attempt();
  });
}

async function main() {
  const mediaFile = path.join(root, 'build/webos-dev/demo-90s.mp4');
  // Mit ffmpeg gibt es ein lokales Testvideo; ohne ffmpeg bleibt das freie
  // Internet-Testvideo des Mock-Servers verfügbar.
  if (!fs.existsSync(mediaFile)) {
    fs.mkdirSync(path.dirname(mediaFile), { recursive: true });
    const generated = spawnSync('ffmpeg', [
      '-hide_banner', '-loglevel', 'error', '-y',
      '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24',
      '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=44100',
      '-t', '90', '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
      '-c:a', 'aac', '-movflags', '+faststart', mediaFile,
    ], { stdio: 'ignore' });
    if (generated.status !== 0 && fs.existsSync(mediaFile)) fs.unlinkSync(mediaFile);
  }
  const mockPort = process.env.MOCK_PORT || '8766';
  const proxyPort = process.env.IPFLIX_PORT || '47823';
  start('python3', ['-u', 'webos/dev/mock_xtream.py'], {
    MOCK_HOST: '127.0.0.1', MOCK_PORT: mockPort, MOCK_PREVIEW: '1',
    MOCK_VIDEO_FILE: fs.existsSync(mediaFile) ? mediaFile : '',
  });
  start(process.execPath, ['webos/service/proxy.js'], { IPFLIX_PORT: proxyPort });
  await Promise.all([
    waitFor('http://127.0.0.1:' + proxyPort + '/ping'),
    waitFor('http://127.0.0.1:' + mockPort + '/player_api.php?username=test&password=test'),
  ]);
  console.log('\nBrowser: http://127.0.0.1:' + proxyPort + '/');
  console.log('Xtream-Server: http://127.0.0.1:' + mockPort + ' | Benutzer: test | Passwort: test');
  console.log(fs.existsSync(mediaFile) ? 'Filme/Folgen: lokales Testvideo bereit.' : 'Filme/Folgen: Internet-Testvideo (optional ffmpeg für lokale Videos installieren).');
  console.log('Pfeiltasten: navigieren | Enter: OK | Escape: zurück | Strg+C: beenden\n');
}

process.on('SIGINT', () => stop(0));
process.on('SIGTERM', () => stop(0));
main().catch((error) => { if (!stopping) console.error(error.message); stop(1); });
