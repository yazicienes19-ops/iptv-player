// Vollbild-Player mit dem eingebauten <video> des Fernsehers. Der Stream läuft
// über den Hilfsdienst, damit der getarnte User-Agent auch beim Video gilt.
'use strict';

(function (App) {
  const h = App.h;
  const MAX_RETRIES = 3;
  const START_TIMEOUT_MS = 20000;
  // So lange darf das Bild bei laufender Wiedergabe stehen, bevor neu verbunden wird.
  const STALL_TIMEOUT_MS = 15000;
  const FITS = [
    { label: 'Original', value: 'contain' },
    { label: 'Zoom', value: 'cover' },
    { label: 'Strecken', value: 'fill' },
  ];

  function PlayerScreen(item, queue) {
    this.queue = queue && queue.length ? queue : [item];
    this.index = Math.max(0, this.queue.indexOf(item));
    this.retries = 0;
    this.fit = 0;
    this.pendingSeek = null;

    this.video = h('video.video', { autoplay: true });
    this.spinner = h('div.spinner');
    this.error = h('div.player-error');
    this.overlay = h('div.player-overlay');
    this.el = h('div.screen.player', null, [this.video, this.spinner, this.error, this.overlay]);

    this.video.addEventListener('playing', () => this.onPlaying());
    this.video.addEventListener('waiting', () => this.spinner.classList.add('show'));
    this.video.addEventListener('error', () => this.fail(this.describeError()));
    this.video.addEventListener('ended', () => this.onEnded());
    this.video.addEventListener('timeupdate', () => this.onTime());
    this.video.addEventListener('loadedmetadata', () => {
      if (this.resumeAt > 0 && isFinite(this.video.duration)) this.video.currentTime = this.resumeAt;
      this.resumeAt = 0;
    });
    this.el.addEventListener('mousemove', () => this.showOverlay());
    this.el.addEventListener('click', () => this.togglePause());

    this.clockTimer = setInterval(() => this.renderOverlay(), 15000);
    this.stallTimer = setInterval(() => {
      const v = this.video;
      if (this.started && !v.paused && !this.retryTimer && Date.now() - this.lastProgressAt > STALL_TIMEOUT_MS) {
        this.fail('Der Stream hängt.');
      }
    }, 3000);
    this.open();
  }

  PlayerScreen.prototype.item = function () {
    return this.queue[this.index];
  };

  PlayerScreen.prototype.isLive = function () {
    return this.item().kind === 'live';
  };

  PlayerScreen.prototype.open = function () {
    const item = this.item();
    this.stopTimers();
    this.error.classList.remove('show');
    this.spinner.classList.add('show');
    this.started = false;
    this.lastTime = null;
    this.lastProgressAt = Date.now();
    this.epg = [];
    this.lastSaved = 0;
    this.resumeAt = this.isLive() ? 0 : App.resumePosition(item);
    if (this.isLive()) {
      App.addRecent(item);
      App.provider.shortEpg(item).then(
        (epg) => {
          if (item === this.item()) {
            this.epg = epg;
            this.renderOverlay();
          }
        },
        () => {}
      );
    }
    this.video.src = App.proxied(App.provider.streamUrl(item));
    this.video.style.objectFit = FITS[this.fit].value;
    const playing = this.video.play();
    if (playing && playing.catch) playing.catch(() => {});
    this.watchdog = setTimeout(() => {
      if (!this.started) this.fail('Zeitüberschreitung: Der Sender liefert keine Daten.');
    }, START_TIMEOUT_MS);
    this.showOverlay();
  };

  PlayerScreen.prototype.onPlaying = function () {
    this.lastProgressAt = Date.now();
    if (this.started) return this.spinner.classList.remove('show');
    this.started = true;
    this.retries = 0;
    clearTimeout(this.watchdog);
    this.spinner.classList.remove('show');
    this.error.classList.remove('show');
  };

  PlayerScreen.prototype.onEnded = function () {
    if (this.isLive()) return this.fail('Der Stream wurde unterbrochen.');
    App.saveProgress(this.item(), this.video.duration, this.video.duration);
    if (this.index < this.queue.length - 1 && this.item().kind === 'episode') {
      this.index++;
      this.retries = 0;
      return this.open();
    }
    App.pop();
  };

  PlayerScreen.prototype.onTime = function () {
    const v = this.video;
    // webOS meldet „playing“ nicht immer; laufende Zeit zählt deshalb auch als Start.
    if (this.lastTime != null && v.currentTime > this.lastTime + 0.2) {
      if (!this.started || this.spinner.classList.contains('show')) this.onPlaying();
      this.lastProgressAt = Date.now();
    }
    this.lastTime = v.currentTime;
    if (!this.isLive() && v.currentTime - this.lastSaved > 10) {
      this.lastSaved = v.currentTime;
      App.saveProgress(this.item(), v.currentTime, v.duration);
    }
    if (this.overlay.classList.contains('show') && !this.isLive()) this.renderProgress();
  };

  PlayerScreen.prototype.describeError = function () {
    const error = this.video.error;
    if (error && error.code === 4) return 'Format wird vom Fernseher nicht unterstützt oder Stream offline.';
    if (error && error.code === 2) return 'Netzwerkfehler beim Laden des Streams.';
    return 'Der Stream ist offline oder nicht erreichbar.';
  };

  PlayerScreen.prototype.fail = function (message) {
    if (this.retryTimer) return;
    clearTimeout(this.watchdog);
    this.spinner.classList.remove('show');
    this.retries++;
    if (this.retries > MAX_RETRIES) {
      this.showError(message, 'OK: erneut versuchen · Zurück: schließen');
      return;
    }
    // Wartezeit wächst: 3 s, 6 s, 9 s.
    let remaining = 3 * this.retries;
    const tick = () => {
      this.showError(message, 'Neuer Versuch in ' + remaining + ' s (' + this.retries + '/' + MAX_RETRIES + ')');
      if (remaining-- <= 0) {
        this.retryTimer = null;
        this.open();
      } else {
        this.retryTimer = setTimeout(tick, 1000);
      }
    };
    tick();
  };

  PlayerScreen.prototype.showError = function (message, hint) {
    App.clear(this.error);
    this.error.appendChild(h('div.title', { text: message }));
    this.error.appendChild(h('div.hint', { text: hint }));
    this.error.classList.add('show');
  };

  PlayerScreen.prototype.stopTimers = function () {
    clearTimeout(this.watchdog);
    clearTimeout(this.retryTimer);
    this.retryTimer = null;
  };

  PlayerScreen.prototype.switchChannel = function (delta) {
    if (this.queue.length < 2) return;
    this.index = (this.index + delta + this.queue.length) % this.queue.length;
    this.retries = 0;
    this.open();
  };

  PlayerScreen.prototype.togglePause = function () {
    if (this.video.paused) {
      // Nach der Pause nicht gleich als Hänger werten.
      this.lastProgressAt = Date.now();
      const p = this.video.play();
      if (p && p.catch) p.catch(() => {});
    } else {
      this.video.pause();
    }
    this.showOverlay();
  };

  /// Mehrfaches Drücken summiert sich, gesprungen wird erst nach einer kurzen Pause.
  PlayerScreen.prototype.seek = function (delta) {
    const v = this.video;
    if (!isFinite(v.duration)) return;
    const base = this.pendingSeek == null ? v.currentTime : this.pendingSeek;
    this.pendingSeek = Math.max(0, Math.min(v.duration - 1, base + delta));
    clearTimeout(this.seekTimer);
    this.seekTimer = setTimeout(() => {
      v.currentTime = this.pendingSeek;
      this.pendingSeek = null;
      this.lastProgressAt = Date.now();
    }, 600);
    this.showOverlay();
    this.renderProgress();
  };

  PlayerScreen.prototype.cycleAudio = function () {
    const tracks = this.video.audioTracks;
    if (!tracks || tracks.length < 2) return App.toast('Nur eine Tonspur vorhanden');
    let current = 0;
    for (let i = 0; i < tracks.length; i++) if (tracks[i].enabled) current = i;
    const next = (current + 1) % tracks.length;
    for (let i = 0; i < tracks.length; i++) tracks[i].enabled = i === next;
    App.toast('Tonspur: ' + (tracks[next].label || tracks[next].language || next + 1));
  };

  PlayerScreen.prototype.cycleFit = function () {
    this.fit = (this.fit + 1) % FITS.length;
    this.video.style.objectFit = FITS[this.fit].value;
    App.toast('Bildformat: ' + FITS[this.fit].label);
  };

  PlayerScreen.prototype.showOverlay = function () {
    this.renderOverlay();
    this.overlay.classList.add('show');
    clearTimeout(this.hideTimer);
    this.hideTimer = setTimeout(() => {
      if (!this.video.paused || this.isLive()) this.overlay.classList.remove('show');
    }, 5000);
  };

  PlayerScreen.prototype.renderOverlay = function () {
    const item = this.item();
    App.clear(this.overlay);
    const title = item.kind === 'episode' ? item.seriesName + ' · S' + item.season + ' F' + item.number + ' · ' + item.name : item.name;
    const top = h('div.overlay-top', null, [
      this.isLive() && this.queue.length > 1 ? h('span.channel-no', { text: String(this.index + 1) }) : null,
      h('span.overlay-title', { text: title }),
      h('span.clock', { text: App.clock(new Date()) }),
    ]);
    const bottom = h('div.overlay-bottom');
    if (this.isLive()) {
      const now = this.epg[0];
      const next = this.epg[1];
      if (now) {
        const share = Math.max(0, Math.min(1, (Date.now() - now.start) / (now.end - now.start)));
        bottom.appendChild(
          h('div.epg-now', null, [
            h('span.epg-time', { text: App.clock(new Date(now.start)) + ' – ' + App.clock(new Date(now.end)) }),
            h('span.epg-title', { text: now.title }),
          ])
        );
        bottom.appendChild(h('div.progress.wide', null, [h('div.bar', { style: 'width:' + Math.round(share * 100) + '%' })]));
      } else {
        bottom.appendChild(h('div.epg-now', null, [h('span.epg-title.muted', { text: 'Keine Programminfo' })]));
      }
      if (next) {
        bottom.appendChild(
          h('div.epg-next', { text: 'Danach ' + App.clock(new Date(next.start)) + ' ' + next.title })
        );
      }
      bottom.appendChild(h('div.hints', { text: '▲▼ Sender wechseln · Gelb Bildformat · Grün Tonspur' }));
    } else {
      this.progressBar = h('div.bar');
      this.timeLabel = h('span.time');
      bottom.appendChild(h('div.progress.wide', null, [this.progressBar]));
      bottom.appendChild(
        h('div.vod-line', null, [
          h('span.state', { text: this.video.paused ? 'Pausiert' : '' }),
          this.timeLabel,
        ])
      );
      bottom.appendChild(h('div.hints', { text: '◀▶ 10 s springen · OK Pause · Gelb Bildformat · Grün Tonspur' }));
      this.renderProgress();
    }
    this.overlay.appendChild(top);
    this.overlay.appendChild(bottom);
  };

  PlayerScreen.prototype.renderProgress = function () {
    const v = this.video;
    if (!this.progressBar || !isFinite(v.duration) || !(v.duration > 0)) return;
    const position = this.pendingSeek == null ? v.currentTime : this.pendingSeek;
    this.progressBar.style.width = (position / v.duration) * 100 + '%';
    this.timeLabel.textContent = App.formatTime(position) + ' / ' + App.formatTime(v.duration);
  };

  PlayerScreen.prototype.onKey = function (key) {
    const errorShown = this.error.classList.contains('show') && !this.retryTimer;
    if (key === 'back' || key === 'stop') return App.pop(), true;
    if (key === 'ok') {
      if (errorShown) {
        this.retries = 0;
        this.open();
      } else if (this.isLive()) {
        this.overlay.classList.contains('show') ? this.overlay.classList.remove('show') : this.showOverlay();
      } else {
        this.togglePause();
      }
      return true;
    }
    if (this.isLive()) {
      if (key === 'up' || key === 'chup') return this.switchChannel(-1), true;
      if (key === 'down' || key === 'chdown') return this.switchChannel(1), true;
    } else {
      if (key === 'left') return this.seek(-10), true;
      if (key === 'right') return this.seek(10), true;
      if (key === 'rw') return this.seek(-30), true;
      if (key === 'ff') return this.seek(30), true;
      if (key === 'play' || key === 'pause') return this.togglePause(), true;
    }
    if (key === 'yellow') return this.cycleFit(), true;
    if (key === 'green') return this.cycleAudio(), true;
    this.showOverlay();
    return true;
  };

  PlayerScreen.prototype.onDestroy = function () {
    if (!this.isLive() && this.started) App.saveProgress(this.item(), this.video.currentTime, this.video.duration);
    this.stopTimers();
    clearTimeout(this.hideTimer);
    clearTimeout(this.seekTimer);
    clearInterval(this.clockTimer);
    clearInterval(this.stallTimer);
    // Decoder des Fernsehers sofort freigeben.
    this.video.pause();
    this.video.removeAttribute('src');
    this.video.load();
  };

  App.PlayerScreen = PlayerScreen;

  App.play = function (item, queue) {
    App.push(new PlayerScreen(item, queue));
  };
})(IpFlix);
