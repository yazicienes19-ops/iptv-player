// Gemeinsamer Vollbild-Player für Browser und TV (Chrome 53 / ES2016).
'use strict';

(function (App) {
  const h = App.h;
  const MAX_RETRIES = 3;
  const START_TIMEOUT_MS = 20000;
  const STALL_TIMEOUT_MS = 15000;
  const FITS = [
    { label: 'Original', value: 'contain' },
    { label: 'Zoom', value: 'cover' },
    { label: 'Strecken', value: 'fill' },
  ];
  const ICONS = {
    back: '<path d="M20 12H4m7-7-7 7 7 7"/>',
    play: '<path d="m8 5 11 7-11 7z" fill="currentColor" stroke="none"/>',
    pause: '<path d="M8 5v14M16 5v14" stroke-width="4"/>',
    rewind: '<path d="M5 8a8 8 0 1 1-1 8M5 3v5h5"/>',
    forward: '<path d="M19 8a8 8 0 1 0 1 8m-1-13v5h-5"/>',
    volume: '<path d="M11 4 6 8H3v8h3l5 4zM15 8a6 6 0 0 1 0 8m3-11a10 10 0 0 1 0 14"/>',
    mute: '<path d="M11 4 6 8H3v8h3l5 4zM16 9l5 6m0-6-5 6"/>',
    fullscreen: '<path d="M9 4H4v5m11-5h5v5M4 15v5h5m6 0h5v-5"/>',
    shrink: '<path d="M4 9h5V4m6 0v5h5M9 20v-5H4m16 0h-5v5"/>',
    lock: '<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3m-4 5v2"/>',
    unlock: '<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0m-4 8v2"/>',
    tracks: '<path d="M3 4h18v13H8l-5 4zM7 9h10m-10 4h7"/>',
    next: '<path d="m5 5 11 7-11 7z" fill="currentColor" stroke="none"/><path d="M19 5v14"/>',
    fit: '<rect x="3" y="6" width="18" height="12" rx="2"/><path d="M7 10h10m-10 4h10"/>',
  };

  function icon(name) {
    return h('span.player-icon', { 'aria-hidden': 'true', html: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' + (ICONS[name] || '') + '</svg>' });
  }
  function label(button, text) {
    button.setAttribute('aria-label', text);
    button.setAttribute('title', text);
  }
  function visible(element, show) { element.style.display = show ? '' : 'none'; }
  function watchClock() {
    return typeof performance !== 'undefined' && performance.now ? performance.now() : Date.now();
  }

  function PlayerScreen(item, queue) {
    this.recreate = () => new PlayerScreen(item, queue);
    this.queue = queue && queue.length ? queue : [item];
    this.index = Math.max(0, this.queue.indexOf(item));
    this.retries = 0;
    this.fit = 0;
    this.pendingSeek = null;
    this.locked = false;
    this.destroyed = false;
    this.video = h('video.video', { autoplay: true, playsInline: true });
    this.spinner = h('div.spinner', { 'aria-label': 'Video wird geladen' });
    this.error = h('div.player-error', { role: 'status' });
    this.overlay = h('div.player-overlay');
    this.el = h('div.screen.player', null, [this.video, this.spinner, this.error, this.overlay]);
    this.buildControls();

    this.video.addEventListener('playing', () => this.onPlaying());
    this.video.addEventListener('play', () => this.renderState());
    this.video.addEventListener('pause', () => { this.pauseLiveWatch(); if (!this.destroyed) this.showOverlay(); });
    this.video.addEventListener('volumechange', () => this.renderVolume());
    this.video.addEventListener('waiting', () => { this.pauseLiveWatch(); this.spinner.classList.add('show'); });
    this.video.addEventListener('seeking', () => this.pauseLiveWatch());
    this.video.addEventListener('seeked', () => this.resumeLiveWatch());
    this.video.addEventListener('error', () => this.fail(this.describeError()));
    this.video.addEventListener('ended', () => this.onEnded());
    this.video.addEventListener('timeupdate', () => this.onTime());
    this.video.addEventListener('durationchange', () => this.renderProgress());
    this.video.addEventListener('loadedmetadata', () => {
      if (this.resumeAt > 0 && isFinite(this.video.duration)) this.seekTo(this.resumeAt);
      this.resumeAt = 0;
      this.updateTracks();
      this.renderOverlay();
    });
    this.el.addEventListener('mousemove', () => this.showOverlay());
    this.video.addEventListener('click', () => { if (!this.locked) this.togglePause(); });
    this.overlay.addEventListener('click', (event) => { if (event.target === this.overlay && !this.locked) this.togglePause(); });
    this.el.addEventListener('focusin', () => this.showOverlay());
    this.el.addEventListener('focusout', () => this.scheduleHide());
    this.fullscreenChanged = () => this.renderFullscreen();
    document.addEventListener('fullscreenchange', this.fullscreenChanged);
    document.addEventListener('webkitfullscreenchange', this.fullscreenChanged);
    this.watchVisibilityChanged = () => {
      if (document.hidden) this.pauseLiveWatch();
      else this.resumeLiveWatch();
    };
    this.watchPageHidden = () => this.pauseLiveWatch();
    document.addEventListener('visibilitychange', this.watchVisibilityChanged);
    if (typeof window !== 'undefined' && window.addEventListener) {
      window.addEventListener('pagehide', this.watchPageHidden);
      window.addEventListener('pageshow', this.watchVisibilityChanged);
    }
    this.trackChanged = () => this.updateTracks();
    [this.video.audioTracks, this.video.textTracks].forEach((tracks) => {
      if (tracks && tracks.addEventListener) {
        tracks.addEventListener('addtrack', this.trackChanged);
        tracks.addEventListener('removetrack', this.trackChanged);
      }
    });
    this.clockTimer = setInterval(() => this.renderOverlay(), 15000);
    this.stallTimer = setInterval(() => {
      const v = this.video;
      if (this.started && !v.paused && !this.retryTimer && Date.now() - this.lastProgressAt > STALL_TIMEOUT_MS) this.fail('Der Stream hängt.');
    }, 3000);
    this.open();
  }

  PlayerScreen.prototype.button = function (name, text, action, extra) {
    const button = h('button.player-control' + (extra ? '.' + extra : ''), {
      type: 'button', 'aria-label': text, title: text,
      onclick: (event) => {
        event.stopPropagation();
        if (this.locked) return;
        action();
        this.showOverlay();
      },
    }, name ? [icon(name)] : []);
    return button;
  };

  PlayerScreen.prototype.buildControls = function () {
    // Schon vor App.push vorhanden: navigation.js fügt keinen zweiten Zurück-Knopf ein.
    this.backButton = this.button('back', 'Wiedergabe verlassen', () => App.pop(), 'player-back');
    this.title = h('div.player-title');
    this.subtitle = h('div.player-subtitle');
    this.clock = h('span.player-clock');
    const top = h('div.player-header', null, [this.backButton, h('div.player-heading', null, [this.subtitle, this.title]), this.clock]);
    this.rewindButton = this.button('rewind', '10 Sekunden zurück', () => this.seek(-10), 'player-jump');
    this.rewindButton.appendChild(h('span.jump-seconds', { text: '10' }));
    this.playButton = this.button('pause', 'Pausieren', () => this.togglePause(), 'player-play');
    this.forwardButton = this.button('forward', '10 Sekunden vor', () => this.seek(10), 'player-jump');
    this.forwardButton.appendChild(h('span.jump-seconds', { text: '10' }));
    this.center = h('div.player-center', null, [this.rewindButton, this.playButton, this.forwardButton]);
    this.timeLabel = h('span.player-time', { text: '0:00 / 0:00' });
    this.timeline = h('input.player-timeline', {
      type: 'range', min: 0, max: 100, value: 0, step: 0.1, 'aria-label': 'Wiedergabeposition',
      oninput: () => { if (!this.locked) { this.seekTo(Number(this.timeline.value)); this.showOverlay(); } },
      onclick: (event) => event.stopPropagation(),
    });
    this.progressBar = h('div.player-progress-fill');
    this.timelineRow = h('div.player-timeline-row', null, [h('div.player-progress-track', null, [this.progressBar, this.timeline]), this.timeLabel]);
    this.liveInfo = h('div.player-live-info');
    this.muteButton = this.button('volume', 'Stummschalten', () => this.toggleMute());
    this.volume = h('input.player-volume', {
      type: 'range', min: 0, max: 1, value: 1, step: 0.05, 'aria-label': 'Lautstärke',
      oninput: () => { if (!this.locked) this.setVolume(Number(this.volume.value)); },
      onclick: (event) => event.stopPropagation(),
    });
    this.volumeGroup = h('div.player-volume-group', null, [this.muteButton, this.volume]);
    this.fitButton = this.button('fit', 'Bildformat ändern', () => this.cycleFit());
    this.lockButton = this.button('lock', 'Bildschirm sperren', () => this.setLocked(true));
    this.tracksButton = this.button('tracks', 'Audio und Untertitel', () => this.toggleTracks());
    this.tracksButton.setAttribute('aria-expanded', 'false');
    this.speedButton = this.button(null, 'Wiedergabegeschwindigkeit: 1-fach', () => this.cycleSpeed(), 'player-speed');
    this.speedButton.textContent = '1×';
    this.nextButton = this.button('next', 'Nächste Folge', () => this.nextEpisode(), 'player-next');
    this.nextButton.appendChild(h('span.control-label', { text: 'Nächste Folge' }));
    this.fullscreenButton = this.button('fullscreen', 'Vollbild', () => this.toggleFullscreen());
    this.tools = h('div.player-tools', null, [this.volumeGroup, h('span.player-tools-spacer'), this.nextButton, this.speedButton, this.tracksButton, this.fitButton, this.lockButton, this.fullscreenButton]);
    this.trackMenu = h('div.player-track-menu', { role: 'group', 'aria-label': 'Audio und Untertitel' });
    visible(this.trackMenu, false);
    const bottom = h('div.player-footer', null, [this.trackMenu, this.liveInfo, this.timelineRow, this.tools]);
    this.overlay.appendChild(top);
    this.overlay.appendChild(this.center);
    this.overlay.appendChild(bottom);
    this.unlockButton = h('button.player-unlock', {
      type: 'button', 'aria-label': 'Bildschirm entsperren', onclick: (event) => { event.stopPropagation(); this.setLocked(false); },
    }, [icon('unlock'), h('span', { text: 'Zum Entsperren tippen' })]);
    visible(this.unlockButton, false);
    this.el.appendChild(this.unlockButton);
    this.retryButton = this.button(null, 'Erneut versuchen', () => { this.retries = 0; this.open(); });
    this.retryButton.textContent = 'Erneut versuchen';
    this.renderFullscreen();
    this.updateTracks();
  };

  PlayerScreen.prototype.item = function () { return this.queue[this.index]; };
  PlayerScreen.prototype.isLive = function () { return this.item().kind === 'live'; };

  PlayerScreen.prototype.open = function () {
    // Der bisherige Eintrag bleibt im Tracker erhalten, auch wenn index schon
    // auf den nächsten Sender zeigt. So landet Sehzeit nie beim falschen Sender.
    this.pauseLiveWatch();
    const item = this.item();
    this.playlistScope = App.libraryScope ? App.libraryScope() : null;
    this.liveWatch = (item.kind === 'live' ? App.recordLiveWatch : App.recordVodWatch) ? {
      item: item, scope: this.playlistScope,
      seconds: 0, playing: false, at: null, position: null,
    } : null;
    this.stopTimers();
    clearTimeout(this.seekTimer);
    this.pendingSeek = null;
    this.closeTracks();
    this.error.classList.remove('show');
    this.spinner.classList.add('show');
    this.started = false;
    this.lastTime = null;
    this.lastProgressAt = Date.now();
    this.epg = [];
    this.lastSaved = 0;
    this.resumeAt = this.isLive() ? 0 : App.resumePosition(item, this.playlistScope);
    if (this.isLive()) {
      App.addRecent(item, this.playlistScope);
      App.provider.shortEpg(item).then((epg) => {
        if (!this.destroyed && item === this.item()) { this.epg = epg; this.renderOverlay(); }
      }, () => {});
    }
    this.video.src = App.proxied(App.provider.streamUrl(item));
    this.video.style.objectFit = FITS[this.fit].value;
    const playing = this.video.play();
    if (playing && playing.catch) playing.catch(() => { if (!this.destroyed) this.showOverlay(); });
    this.watchdog = setTimeout(() => {
      if (!this.started && !this.video.paused) this.fail('Zeitüberschreitung: Der Sender liefert keine Daten.');
    }, START_TIMEOUT_MS);
    this.showOverlay();
  };

  PlayerScreen.prototype.onPlaying = function () {
    this.lastProgressAt = Date.now();
    this.stopTimers();
    this.started = true;
    this.retries = 0;
    this.spinner.classList.remove('show');
    this.error.classList.remove('show');
    this.resumeLiveWatch();
    this.renderState();
    this.scheduleHide();
  };

  PlayerScreen.prototype.onEnded = function () {
    if (this.isLive()) return this.fail('Der Stream wurde unterbrochen.');
    this.pauseLiveWatch();
    App.saveProgress(this.item(), this.video.duration, this.video.duration, this.playlistScope);
    if (this.index < this.queue.length - 1 && this.item().kind === 'episode') return this.nextEpisode(true);
    App.pop();
  };

  PlayerScreen.prototype.onTime = function () {
    const v = this.video;
    this.sampleLiveWatch();
    if (this.lastTime != null && v.currentTime > this.lastTime + 0.2) {
      if (!this.started || this.retryTimer || this.error.classList.contains('show') || this.spinner.classList.contains('show')) this.onPlaying();
      this.lastProgressAt = Date.now();
    }
    this.lastTime = v.currentTime;
    if (!this.isLive() && Math.abs(v.currentTime - this.lastSaved) > 10) {
      this.lastSaved = v.currentTime;
      App.saveProgress(this.item(), v.currentTime, v.duration, this.playlistScope);
    }
    if (this.overlay.classList.contains('show') && !this.isLive()) this.renderProgress();
  };

  PlayerScreen.prototype.describeError = function () {
    const error = this.video.error;
    if (error && error.code === 4) return 'Format wird vom Gerät nicht unterstützt oder Stream offline.';
    if (error && error.code === 2) return 'Netzwerkfehler beim Laden des Streams.';
    return 'Der Stream ist offline oder nicht erreichbar.';
  };

  PlayerScreen.prototype.fail = function (message) {
    if (this.destroyed || this.retryTimer) return;
    this.pauseLiveWatch();
    clearTimeout(this.watchdog);
    this.spinner.classList.remove('show');
    this.retries++;
    if (this.retries > MAX_RETRIES) return this.showError(message, 'Du kannst die Wiedergabe erneut starten.', true);
    let remaining = 3 * this.retries;
    const tick = () => {
      this.showError(message, 'Neuer Versuch in ' + remaining + ' s (' + this.retries + '/' + MAX_RETRIES + ')');
      if (remaining-- <= 0) { this.retryTimer = null; this.open(); }
      else this.retryTimer = setTimeout(tick, 1000);
    };
    tick();
  };

  PlayerScreen.prototype.showError = function (message, hint, retry) {
    App.clear(this.error);
    this.error.appendChild(h('div.title', { text: message }));
    this.error.appendChild(h('div.hint', { text: hint }));
    if (retry) this.error.appendChild(this.retryButton);
    this.error.classList.add('show');
    this.showOverlay();
  };

  PlayerScreen.prototype.stopTimers = function () {
    clearTimeout(this.watchdog);
    clearTimeout(this.retryTimer);
    this.retryTimer = null;
  };

  // Gezählt werden nur bestätigte, fortschreitende Bilder (Live und VOD). Medienposition
  // allein wäre falsch: Spulen oder ein neu beginnendes HLS-Fenster ist Sehzeit 0.
  PlayerScreen.prototype.resumeLiveWatch = function () {
    const watch = this.liveWatch;
    if (!watch || this.destroyed || document.hidden || this.video.paused || this.video.seeking || !this.started) return;
    watch.playing = true;
    watch.at = watchClock();
    watch.position = this.video.currentTime;
  };

  PlayerScreen.prototype.sampleLiveWatch = function () {
    const watch = this.liveWatch;
    if (!watch) return;
    const video = this.video;
    const now = watchClock();
    const position = video.currentTime;
    const elapsed = watch.at == null ? 0 : (now - watch.at) / 1000;
    const moved = watch.position == null ? 0 : position - watch.position;
    const rate = video.playbackRate > 0 ? video.playbackRate : 1;
    if (watch.playing && !this.destroyed && !document.hidden && !video.paused && !video.seeking &&
        elapsed > 0 && elapsed <= 5 && moved > 0 && moved <= elapsed * rate + 2) {
      watch.seconds += Math.min(elapsed, moved / rate);
      if (watch.seconds >= 15) this.flushLiveWatch();
    }
    watch.at = now;
    watch.position = position;
  };

  PlayerScreen.prototype.flushLiveWatch = function () {
    const watch = this.liveWatch;
    if (!watch || !(watch.seconds > 0)) return;
    try {
      if (watch.item.kind === 'live') App.recordLiveWatch(watch.item, watch.seconds, watch.scope);
      else App.recordVodWatch(watch.item, watch.seconds, this.video.duration, this.video.currentTime, watch.scope);
      watch.seconds = 0;
    } catch (e) { /* Ein voller lokaler Speicher darf die Wiedergabe nicht stoppen. */ }
  };

  PlayerScreen.prototype.pauseLiveWatch = function () {
    const watch = this.liveWatch;
    if (!watch) return;
    watch.playing = false;
    watch.at = null;
    watch.position = null;
    this.flushLiveWatch();
  };

  PlayerScreen.prototype.switchChannel = function (delta) {
    if (this.locked || this.queue.length < 2) return;
    this.index = (this.index + delta + this.queue.length) % this.queue.length;
    this.retries = 0;
    this.open();
  };

  PlayerScreen.prototype.nextEpisode = function (automatic) {
    if ((!automatic && this.locked) || this.item().kind !== 'episode' || this.index >= this.queue.length - 1) return;
    if (!automatic) App.saveProgress(this.item(), this.video.currentTime, this.video.duration, this.playlistScope);
    this.index++;
    this.retries = 0;
    this.open();
  };

  PlayerScreen.prototype.togglePause = function () {
    if (this.locked) return;
    if (this.video.paused) {
      this.lastProgressAt = Date.now();
      const p = this.video.play();
      if (p && p.catch) p.catch(() => {});
    } else this.video.pause();
    this.showOverlay();
  };

  PlayerScreen.prototype.seekTo = function (position) {
    const v = this.video;
    if (this.locked || this.isLive() || !isFinite(v.duration) || !(v.duration > 0) || !isFinite(position)) return;
    clearTimeout(this.seekTimer);
    this.pendingSeek = null;
    try { v.currentTime = Math.max(0, Math.min(Math.max(0, v.duration - 0.05), position)); } catch (e) { return; }
    this.lastProgressAt = Date.now();
    this.renderProgress();
  };

  // Wiederholte Fernbedienungstasten bündeln, statt den Decoder pro Taste neu zu starten.
  PlayerScreen.prototype.seek = function (delta) {
    const v = this.video;
    if (this.locked || this.isLive() || !isFinite(v.duration) || !(v.duration > 0)) return;
    const base = this.pendingSeek == null ? v.currentTime : this.pendingSeek;
    this.pendingSeek = Math.max(0, Math.min(Math.max(0, v.duration - 0.05), base + delta));
    clearTimeout(this.seekTimer);
    this.seekTimer = setTimeout(() => this.seekTo(this.pendingSeek), 350);
    this.showOverlay();
    this.renderProgress();
  };

  PlayerScreen.prototype.toggleMute = function () {
    if (this.locked) return;
    this.video.muted = !this.video.muted;
    this.renderVolume();
    this.showOverlay();
  };

  PlayerScreen.prototype.setVolume = function (value) {
    if (this.locked || !isFinite(value)) return;
    try { this.video.volume = Math.max(0, Math.min(1, value)); this.video.muted = value <= 0; } catch (e) { App.toast('Lautstärke bitte am Gerät ändern'); }
    this.renderVolume();
    this.showOverlay();
  };

  PlayerScreen.prototype.renderVolume = function () {
    if (!this.muteButton) return;
    const muted = this.video.muted || this.video.volume === 0;
    if (this.volumeIconMuted !== muted) {
      App.clear(this.muteButton);
      this.muteButton.appendChild(icon(muted ? 'mute' : 'volume'));
      this.volumeIconMuted = muted;
    }
    label(this.muteButton, muted ? 'Ton einschalten' : 'Stummschalten');
    this.muteButton.setAttribute('aria-pressed', String(muted));
    this.volume.value = this.video.muted ? 0 : this.video.volume;
  };

  PlayerScreen.prototype.cycleAudio = function () {
    if (this.locked) return;
    const tracks = this.video.audioTracks;
    if (!tracks || tracks.length < 2) return App.toast('Keine weitere Tonspur verfügbar');
    let current = 0;
    for (let i = 0; i < tracks.length; i++) if (tracks[i].enabled) current = i;
    const next = (current + 1) % tracks.length;
    for (let i = 0; i < tracks.length; i++) tracks[i].enabled = i === next;
    App.toast('Tonspur: ' + (tracks[next].label || tracks[next].language || next + 1));
    this.updateTracks();
  };

  PlayerScreen.prototype.updateTracks = function () {
    const audio = this.video.audioTracks;
    const text = this.video.textTracks;
    visible(this.tracksButton, !!((audio && audio.length) || (text && text.length)));
    if (!this.trackMenuOpen) return;
    const focused = this.trackMenu.contains(document.activeElement);
    App.clear(this.trackMenu);
    const addTracks = (heading, tracks, subtitles) => {
      if (!tracks || !tracks.length) return;
      this.trackMenu.appendChild(h('div.track-heading', { text: heading }));
      let selected = false;
      for (let i = 0; i < tracks.length; i++) if (subtitles ? tracks[i].mode === 'showing' : tracks[i].enabled) selected = true;
      const choice = (name, index, checked) => {
        const button = this.button(null, name, () => {
          for (let i = 0; i < tracks.length; i++) {
            if (subtitles) tracks[i].mode = i === index ? 'showing' : 'disabled';
            else tracks[i].enabled = i === index;
          }
          this.closeTracks();
          this.tracksButton.focus();
        }, 'track-choice');
        button.textContent = (checked ? '✓  ' : '') + name;
        button.setAttribute('aria-pressed', String(checked));
        this.trackMenu.appendChild(button);
      };
      if (subtitles) choice('Untertitel aus', -1, !selected);
      for (let i = 0; i < tracks.length; i++) choice(tracks[i].label || tracks[i].language || (subtitles ? 'Untertitel ' : 'Tonspur ') + (i + 1), i, subtitles ? tracks[i].mode === 'showing' : tracks[i].enabled);
    };
    addTracks('Audio', audio, false);
    addTracks('Untertitel', text, true);
    if (focused && this.trackMenu.firstChild) {
      const first = this.trackMenu.querySelector('button');
      if (first) first.focus();
    }
  };

  PlayerScreen.prototype.toggleTracks = function () {
    if (this.locked) return;
    this.trackMenuOpen = !this.trackMenuOpen;
    visible(this.trackMenu, this.trackMenuOpen);
    this.tracksButton.setAttribute('aria-expanded', String(this.trackMenuOpen));
    this.updateTracks();
    if (this.trackMenuOpen) {
      const first = this.trackMenu.querySelector('button');
      if (first) first.focus();
    }
  };

  PlayerScreen.prototype.closeTracks = function () {
    this.trackMenuOpen = false;
    visible(this.trackMenu, false);
    this.tracksButton.setAttribute('aria-expanded', 'false');
  };

  PlayerScreen.prototype.cycleFit = function () {
    if (this.locked) return;
    this.fit = (this.fit + 1) % FITS.length;
    this.video.style.objectFit = FITS[this.fit].value;
    App.toast('Bildformat: ' + FITS[this.fit].label);
  };

  PlayerScreen.prototype.cycleSpeed = function () {
    if (this.locked || this.isLive()) return;
    const rates = [0.5, 0.75, 1, 1.25, 1.5, 2];
    const rate = rates[(rates.indexOf(this.video.playbackRate) + 1) % rates.length];
    try { this.video.playbackRate = rate; } catch (e) { return App.toast('Wiedergabegeschwindigkeit wird vom Gerät nicht unterstützt'); }
    this.speedButton.textContent = String(rate).replace('.', ',') + '×';
    label(this.speedButton, 'Wiedergabegeschwindigkeit: ' + rate + '-fach');
  };

  PlayerScreen.prototype.toggleFullscreen = function () {
    if (this.locked) return;
    const active = document.fullscreenElement || document.webkitFullscreenElement;
    const action = active ? (document.exitFullscreen || document.webkitExitFullscreen) : (this.el.requestFullscreen || this.el.webkitRequestFullscreen);
    if (!action) return;
    try {
      const result = action.call(active ? document : this.el);
      if (result && result.catch) result.catch(() => App.toast('Vollbild ist in diesem Fenster nicht verfügbar'));
    } catch (e) { App.toast('Vollbild ist in diesem Fenster nicht verfügbar'); }
  };

  PlayerScreen.prototype.renderFullscreen = function () {
    if (!this.fullscreenButton) return;
    const active = !!(document.fullscreenElement || document.webkitFullscreenElement);
    visible(this.fullscreenButton, !!(this.el.requestFullscreen || this.el.webkitRequestFullscreen));
    if (active !== this.fullscreenActive) {
      this.fullscreenActive = active;
      App.clear(this.fullscreenButton);
      this.fullscreenButton.appendChild(icon(active ? 'shrink' : 'fullscreen'));
    }
    label(this.fullscreenButton, active ? 'Vollbild verlassen' : 'Vollbild');
  };

  PlayerScreen.prototype.setLocked = function (locked) {
    this.locked = locked;
    if (locked) {
      clearTimeout(this.seekTimer);
      this.pendingSeek = null;
    }
    this.closeTracks();
    this.el.classList.toggle('is-locked', locked);
    visible(this.unlockButton, locked);
    const controls = this.overlay.querySelectorAll('button, input');
    for (let i = 0; i < controls.length; i++) controls[i].disabled = locked;
    if (locked) {
      clearTimeout(this.hideTimer);
      this.overlay.classList.remove('show');
      this.el.classList.remove('controls-visible');
      this.unlockButton.focus();
    } else {
      this.renderOverlay();
      this.showOverlay();
      this.playButton.focus();
    }
  };

  PlayerScreen.prototype.scheduleHide = function () {
    clearTimeout(this.hideTimer);
    if (!this.overlay || this.locked || !this.el) return;
    this.hideTimer = setTimeout(() => {
      const hasKeyboardFocus = App.usingKeyboard && this.el.contains(document.activeElement);
      if (!this.video.paused && !this.trackMenuOpen && !hasKeyboardFocus && !this.error.classList.contains('show')) {
        this.overlay.classList.remove('show');
        this.el.classList.remove('controls-visible');
      }
    }, 4000);
  };

  PlayerScreen.prototype.showOverlay = function () {
    if (this.destroyed || this.locked) return;
    this.renderOverlay();
    this.overlay.classList.add('show');
    this.el.classList.add('controls-visible');
    this.scheduleHide();
  };

  PlayerScreen.prototype.renderState = function () {
    if (!this.playButton) return;
    const paused = this.video.paused;
    if (this.playIconPaused !== paused) {
      App.clear(this.playButton);
      this.playButton.appendChild(icon(paused ? 'play' : 'pause'));
      this.playIconPaused = paused;
    }
    label(this.playButton, paused ? 'Wiedergabe starten' : 'Pausieren');
    this.playButton.setAttribute('aria-pressed', String(!paused));
  };

  // Nur Werte aktualisieren: Fokus, Timeline und Schaltflächen bleiben dieselben DOM-Knoten.
  PlayerScreen.prototype.renderOverlay = function () {
    const item = this.item();
    const live = this.isLive();
    this.title.textContent = item.kind === 'episode' ? (item.seriesName || item.name) : item.name;
    this.subtitle.textContent = live ? 'LIVE TV' : item.kind === 'episode' ? 'STAFFEL ' + item.season + ' · FOLGE ' + item.number + ' — ' + item.name : 'JETZT ANSEHEN';
    this.clock.textContent = App.clock(new Date());
    visible(this.timelineRow, !live);
    visible(this.rewindButton, !live);
    visible(this.forwardButton, !live);
    visible(this.speedButton, !live);
    visible(this.nextButton, item.kind === 'episode' && this.index < this.queue.length - 1);
    visible(this.liveInfo, live);
    if (live) {
      const now = this.epg && this.epg[0];
      const next = this.epg && this.epg[1];
      this.liveInfo.textContent = now ? now.title + (next ? ' · Danach: ' + next.title : '') : 'Live · ' + item.name;
    }
    this.renderState();
    this.renderVolume();
    this.renderProgress();
  };

  PlayerScreen.prototype.renderProgress = function () {
    const v = this.video;
    if (!this.timeline) return;
    const available = !this.isLive() && isFinite(v.duration) && v.duration > 0;
    this.timeline.disabled = this.locked || !available;
    this.rewindButton.disabled = this.locked || !available;
    this.forwardButton.disabled = this.locked || !available;
    const duration = available ? v.duration : 0;
    const position = Math.min(duration, Math.max(0, this.pendingSeek == null ? (v.currentTime || 0) : this.pendingSeek));
    this.progressBar.style.width = (duration ? position / duration * 100 : 0) + '%';
    this.timeline.max = duration || 100;
    this.timeline.value = position;
    this.timeline.setAttribute('aria-valuetext', App.formatTime(position) + ' von ' + App.formatTime(duration));
    this.timeLabel.textContent = App.formatTime(position) + ' / ' + App.formatTime(duration);
  };

  PlayerScreen.prototype.focusControl = function (delta) {
    this.showOverlay();
    const nodes = this.el.querySelectorAll('button, input');
    const controls = [];
    for (let i = 0; i < nodes.length; i++) if (!nodes[i].disabled && nodes[i].offsetWidth && nodes[i].offsetHeight) controls.push(nodes[i]);
    if (!controls.length) return;
    const current = controls.indexOf(document.activeElement);
    controls[(current + delta + controls.length) % controls.length].focus();
  };

  PlayerScreen.prototype.onKey = function (key) {
    if (this.locked) {
      if (key === 'back' || key === 'stop' || key === 'ok') this.setLocked(false);
      return true;
    }
    const errorShown = this.error.classList.contains('show') && !this.retryTimer;
    if (key === 'back' || key === 'stop') {
      if (this.trackMenuOpen) { this.closeTracks(); this.tracksButton.focus(); }
      else App.pop();
      return true;
    }
    if (key === 'ok') {
      if (errorShown) { this.retries = 0; this.open(); }
      else this.togglePause();
      return true;
    }
    if (key === 'space' || key === 'play' || key === 'pause') return this.togglePause(), true;
    if (key === 'mute') return this.toggleMute(), true;
    if (key === 'fullscreen') return this.toggleFullscreen(), true;
    if (this.isLive()) {
      if (key === 'chup') return this.switchChannel(-1), true;
      if (key === 'chdown') return this.switchChannel(1), true;
    }
    const focused = document.activeElement;
    const hasButtonFocus = focused && focused.tagName === 'BUTTON' && this.el.contains(focused);
    if (hasButtonFocus && (key === 'left' || key === 'right')) return this.focusControl(key === 'left' ? -1 : 1), true;
    if (key === 'up' || key === 'down') return this.focusControl(key === 'up' ? -1 : 1), true;
    if (!this.isLive()) {
      if (key === 'left' || key === 'rw') return this.seek(-10), true;
      if (key === 'right' || key === 'ff') return this.seek(10), true;
    }
    if (key === 'yellow') return this.cycleFit(), true;
    if (key === 'green') return this.cycleAudio(), true;
    this.showOverlay();
    return true;
  };

  PlayerScreen.prototype.onDestroy = function () {
    this.pauseLiveWatch();
    this.destroyed = true;
    if (!this.isLive() && this.started) App.saveProgress(this.item(), this.video.currentTime, this.video.duration, this.playlistScope);
    this.stopTimers();
    clearTimeout(this.hideTimer);
    clearTimeout(this.seekTimer);
    clearInterval(this.clockTimer);
    clearInterval(this.stallTimer);
    document.removeEventListener('fullscreenchange', this.fullscreenChanged);
    document.removeEventListener('webkitfullscreenchange', this.fullscreenChanged);
    document.removeEventListener('visibilitychange', this.watchVisibilityChanged);
    if (typeof window !== 'undefined' && window.removeEventListener) {
      window.removeEventListener('pagehide', this.watchPageHidden);
      window.removeEventListener('pageshow', this.watchVisibilityChanged);
    }
    [this.video.audioTracks, this.video.textTracks].forEach((tracks) => {
      if (tracks && tracks.removeEventListener) {
        tracks.removeEventListener('addtrack', this.trackChanged);
        tracks.removeEventListener('removetrack', this.trackChanged);
      }
    });
    if (document.fullscreenElement === this.el || document.webkitFullscreenElement === this.el) {
      const exit = document.exitFullscreen || document.webkitExitFullscreen;
      if (exit) {
        try {
          const result = exit.call(document);
          if (result && result.catch) result.catch(() => {});
        } catch (e) { /* Decoder auch bei einem bereits verlassenen Vollbild freigeben. */ }
      }
    }
    this.video.pause();
    this.video.removeAttribute('src');
    this.video.load();
  };

  App.PlayerScreen = PlayerScreen;
  App.play = function (item, queue) { App.push(new PlayerScreen(item, queue)); };
})(IpFlix);
