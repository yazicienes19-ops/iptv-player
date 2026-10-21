# Handoff – IpFlix

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
