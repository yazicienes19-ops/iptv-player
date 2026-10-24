# Handoff – IpFlix

> **Historisches Arbeitsprotokoll.** Dieses Dokument beschreibt den damaligen
> Entwicklungsstand vom Oktober 2026. Angaben zu installierten Apps, Geräten,
> Testzahlen und offenen Aufgaben sind keine aktuelle Freigabe. Für Einrichtung
> und Nutzung gelten die [README](README.md), der
> [Plattformstand](docs/PLATFORMS.md) und die
> [Release-Historie](https://github.com/yazicienes19-ops/iptv-player/releases).
> Persönliche Netzwerkadressen und Schlüsselpfade wurden durch Platzhalter ersetzt.

Stand: 22.10.2026, Commit `dc50bbf` und dieser Handoff. Repo: `github.com/yazicienes19-ops/iptv-player` (privat).

## Was ist das?

IPTV-Player „IpFlix“ in Flutter (Riverpod 3, media_kit/libmpv, Dio). Läuft auf macOS
(fertig, installiert unter `/Applications/IpFlix.app`), iOS vorbereitet, Android inkl.
Android TV / Fire TV, Windows und Linux vorbereitet. Oberfläche komplett deutsch.

Interne Kennung bleibt `com.enesyazici.pulseMedia` (Android: `com.enesyazici.pulsemedia`),
damit Playlists und Schlüsselbund-Einträge beim Umbenennen erhalten bleiben.

## Starten

```sh
flutter run -d macos                      # Entwicklung
flutter run -d macos --dart-define=FORCE_TV=true   # Fernseher-Modus am Mac testen
flutter build macos --release             # dann nach /Applications kopieren
flutter test                              # 22 Unit-/Widget-Tests, ohne Fenster
```

Ende-zu-Ende-Test mit echten Streams (öffnet Fenster, ca. 3 Min.):
`python3 integration_test/test_server.py &` und dann
`flutter test integration_test/app_flow_test.dart -d macos`.

## LG-Fernseher (webOS)

Gerät des Nutzers: LG 65UM7100 (2019), webOS 4.10, **Chrome 53, kein WebAssembly** →
Flutter läuft dort nicht. Deshalb eigene TV-Oberfläche in reinem JavaScript:
`webos/tv/` (ES2015 ohne async/await, kein CSS-Grid/`gap`; Check mit acorn ecmaVersion 2016).
Gleiche Funktionen wie die App im Kern: Xtream + M3U, Live mit Kategorien/Raster/EPG,
Filme/Serien mit Details, Staffeln, Weiterschauen, Favoriten (Rot), Suche, Länderfilter,
User-Agent-Wahl (Standard IPTV Smarters), Live-Format m3u8/ts.

Paket: `./scripts/build_webos.sh` → `dist/com.enesyazici.ipflix_1.0.0_all.ipk` (~180 KB).
Startschale `webos/app` weckt per Luna den JS-Dienst `webos/service/proxy.js` (Node 0.12!),
der `webos/tv` unter `http://127.0.0.1:47823/` ausliefert und unter `/p?u=…&ua=…` alles
(API, Logos, Video) mit User-Agent durchreicht; HLS-Listen werden umgeschrieben.
`cacert.pem` (aus /etc/ssl/cert.pem) liegt bei, weil das TV-Node alte Stammzertifikate hat.
Gemessen über den Dienst: HTTP ~28 Mbit/s, HTTPS nur ~4 Mbit/s (TLS im alten Node) →
HD über HTTPS ruckelt. Direkt laden kann der TV-Abspieler HTTPS auch nicht (Zertifikate).

Login per Handy: Login-Bildschirm holt `/setup/start` → `webos/service/setup.js` öffnet
`http://<tv-ip>:47824/<zufallscode>` im WLAN (nur dieser Pfad, eine Eingabe, max. 15 Min.,
schließt beim Verlassen des Logins). TV zeigt QR (`webos/tv/js/vendor/qrcode.js`, MIT) und
fragt `/setup/poll` alle 2 s ab. Falsche Daten → neuer QR-Code. Port 47823 bleibt nur lokal.

TMDB (`webos/tv/js/tmdb.js`): Schlüssel kommt per Handy (beim Login optional oder
Einstellungen → TMDB, `/setup/start-tmdb` → Handy-Seite `?nur=tmdb`), wird geprüft und in
localStorage gespeichert. Detailseite: bereinigter Titel, Tagline, FSK, TMDB-Bewertung,
Darsteller (→ Personenseite mit Titeln aus der Playlist), Filmreihe (fehlende Teile blass),
„Mehr wie dieses“ nur mit vorhandenen Titeln (Abgleich wie PlaylistTitleIndex in Dart).
Testbar ohne Schlüssel: mock_xtream.py beantwortet auch /3/… (fetch im TV per CDP umbiegen).

Auf dem TV geprüft (23.10.): HLS und TS live, Senderwechsel, MP4 und MKV, Springen, Pause,
nächste Folge automatisch, EPG, Suche, Favoriten, Einstellungen, Länderfilter, Beenden.

Testen ohne Anbieter: `MOCK_MEDIA=http://<mac-ip>:8768 python3 webos/dev/mock_xtream.py`
(Login test/test, Port 8766) plus ein Dateiserver mit hls/index.m3u8, live.ts, film.mp4/mkv.
Fernsteuern über DevTools des TV: `ares-inspect -d tv -a com.enesyazici.ipflix`, dann
`http://<TV-IP>:9998/json` (Tasten per CDP Input.dispatchKeyEvent, 461 = Zurück).
Video erscheint nicht in Screenshots (eigene Bildebene des TV).

TV einrichten: `ares-setup-device`, Gerätename `tv`, Adresse `<TV-IP>`,
Schlüssel `<PFAD-ZUM-TV-SCHLUESSEL>`.
Entwicklermodus läuft nach 50 h ab und muss in der Developer-Mode-App verlängert werden.
Die Flutter-Web-Anpassungen (`lib/services/webos.dart`, `lib/player/mpv/`) bleiben für
neuere Fernseher/Browser, werden aber nicht mehr gepackt.

## Aufbau (Einstieg)

| Bereich | Datei |
|---|---|
| Provider (Kataloge, Filter, Favoriten, Verlauf, Einstellungen, VPN) | `lib/providers/app_providers.dart` |
| M3U-Parser (Isolate) + Serien-Zusammenfassung | `lib/services/m3u_parser.dart`, `series_aggregator.dart` |
| Titel-/Kategorie-Cleaner, Qualitäts-Badges, Sprache | `lib/models/channel_name.dart`, `language.dart` |
| Xtream-API | `lib/services/xtream_api.dart` |
| Player, Auto-Retry, Kill-Switch, User-Agent | `lib/player/player_controller.dart` |
| HLS-Umgehung (FFmpeg hängt bei separaten Tonspuren) | `lib/player/hls_resolver.dart` |
| Schlüsselbund, Schwärzen von Zugangsdaten | `lib/services/secure_store.dart`, `local_store.dart` |
| VPN-Erkennung, HTTP-Client mit Kill-Switch | `lib/services/network_security.dart`, `http_client.dart` |
| Layouts: Breitformat / Handy / Seitenleiste | `lib/ui/home/` |
| Live TV (Kachel-Raster + Player) | `lib/ui/live/live_workspace.dart` |
| Filme/Serien (Banner, Reihen, Chips) | `lib/ui/browse/` |
| Fernbedienung/Fokus | `lib/ui/widgets/tv_focus.dart` |

## Offen

1. **Android-APK bauen und testen.** SDK liegt unter `~/Library/Android/sdk`, JDK ist
   `brew openjdk@17`, `flutter doctor` ist grün. Noch nie gebaut: `flutter build apk`.
2. **Windows/Linux-Builds** per GitHub Actions einrichten (auf dem Mac nicht baubar).
   Linux braucht `libmpv-dev`.
3. **Data-Protection-Keychain auf macOS:** Nutzer muss sich in Xcode neu anmelden
   (Einstellungen → Accounts, Login war abgelaufen). Dann `keychain-access-groups` in
   beide `macos/Runner/*.entitlements` und Automatic Signing. Bis dahin klassischer
   Schlüsselbund (funktioniert, verschlüsselt, ohne Dialoge).
4. **iOS-Build:** Signing-Team in Xcode wählen.
5. Untertitel als separate HLS-Spur werden noch nicht angehängt (nur Tonspuren).
6. M3U-EPG (XMLTV) fehlt; Programminfo gibt es nur bei Xtream.

## Fallstricke

- **Kein Hot-Restart** im Entwicklungsmodus: libmpv stürzt beim Beenden ab
  (`mp_shutdown_clients`). Hot-Reload ist in Ordnung, sonst sauber neu starten.
- **Impeller-Absturz** beim Wechsel ins native Vollbild in langen Sitzungen (2× gesehen).
  Gegenmittel eingebaut: Vollbild erst nach dem Seitenübergang, beim Schließen erst
  Fenster zurück, dann Seite. Seitdem nicht mehr aufgetreten, aber nicht bewiesen weg.
  Notlösung wäre `FLTEnableImpeller = false` in `macos/Runner/Info.plist`.
- `defaultExitNativeFullscreen()` von media_kit meldet nicht immer zurück: nie darauf warten.
- Klassischer Mac-Schlüsselbund: `readAll()` ist nicht erlaubt (Fehler -50), nur einzeln lesen.
- Der Nutzer arbeitet parallel am Mac: große Fenster-Tests vorher ankündigen, höchstens
  einen Lauf; für Fotos nur das App-Fenster aufnehmen.
