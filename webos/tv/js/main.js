// Start: Anmeldung oder direkt die Startseite, Tasten an den obersten Bildschirm.
'use strict';

(function (App) {
  App.startWith = function (provider) {
    App.provider = provider;
    if (App.resetTmdbIndex) App.resetTmdbIndex();
    App.reset(new App.HomeScreen());
  };

  let pointerX = null;
  let pointerY = null;
  document.addEventListener('mousemove', (event) => {
    // Scrollen verschiebt Einträge unter einem ruhenden Zeiger. Erst eine
    // wirkliche Mausbewegung darf den Tastaturfokus wieder übernehmen.
    if (event.clientX !== pointerX || event.clientY !== pointerY) App.usingKeyboard = false;
    pointerX = event.clientX;
    pointerY = event.clientY;
  }, true);

  document.addEventListener(
    'keydown',
    (event) => {
      if (event.ctrlKey || event.metaKey || event.altKey) return;
      const key = App.keyName(event);
      // Tab und native Regler bewegen den echten DOM-Fokus, ohne dispatchKey.
      if (key || event.key === 'Tab' || event.keyCode === 9) App.usingKeyboard = true;
      if (!key) return;
      const focused = document.activeElement;
      if (focused && focused.tagName === 'INPUT' && focused.type === 'range' &&
          ['left', 'right', 'space', 'ok'].indexOf(key) >= 0) return;
      // In Eingabefeldern bewegen ◀▶ den Cursor; nur Feldwechsel und Zurück abfangen.
      if (App.isTyping() && ['up', 'down', 'ok', 'back'].indexOf(key) < 0) return;
      // Native Knöpfe bleiben mit Tab und Enter bedienbar. Pfeiltasten wechseln
      // von dort zurück zur Fernbedienungsnavigation der Seite.
      if (focused && focused.tagName === 'BUTTON') {
        if (key === 'ok' || key === 'space') return;
        // Der Player verwaltet den Fokus seiner Transportknöpfe selbst.
        if (!focused.closest || !focused.closest('.player')) focused.blur();
      }
      event.preventDefault();
      App.dispatchKey(key);
    },
    true
  );

  // Lebenszeichen an den Hilfsdienst; ohne Anfragen beendet er sich nach 5 Minuten.
  setInterval(() => fetch('/ping').catch(() => {}), 60000);

  const account = App.load('account', null);
  if (account) App.startWith(App.createProvider(account));
  else App.reset(new App.LoginScreen());
})(IpFlix);
