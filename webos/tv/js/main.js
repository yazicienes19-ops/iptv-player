// Start: Anmeldung oder direkt die Startseite, Tasten an den obersten Bildschirm.
'use strict';

(function (App) {
  App.startWith = function (provider) {
    App.provider = provider;
    App.reset(new App.HomeScreen());
  };

  document.addEventListener(
    'keydown',
    (event) => {
      const key = App.keyName(event);
      if (!key) return;
      // In Eingabefeldern bewegen ◀▶ den Cursor; nur Feldwechsel und Zurück abfangen.
      if (App.isTyping() && ['up', 'down', 'ok', 'back'].indexOf(key) < 0) return;
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
