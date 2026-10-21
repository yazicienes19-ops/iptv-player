# Pulse Media

IPTV-Player für macOS und iOS mit Flutter, Riverpod und media_kit (libmpv).

![Senderliste](docs/screenshots/11_senderliste_badges.png)

## Funktionen

- Playlists per **Xtream Codes** (Server, Benutzer, Passwort) oder **M3U** (URL oder Datei)
- M3U-Parser im Hintergrund-Isolate, auch für sehr große Listen
- **Live TV** im 3-Spalten-Layout (macOS, iPad quer), Tab-Leiste mit Mini-Player auf dem iPhone
- Bereinigte Sendernamen mit Länder-Tag und farbigen Qualitäts-Badges (4K, HEVC, FHD …), Trennzeilen als haftende Abschnittsüberschriften
- **Filme und Serien** im Netflix-Stil: Titelbild, Kategorie-Reihen, Detailseite, Staffeln und Folgen
- Kurz-EPG, Stream-Info (Auflösung, FPS, Codecs, Bitrate) und Tonspurwahl
- Automatische Wiederholung bei Offline-Streams, Vollbild, Spulen, Favoriten

## Datenschutz

- Zugangsdaten (Server, Benutzer, Passwort, M3U-URL) verschlüsselt im Schlüsselbund (`flutter_secure_storage`); in Favoriten werden Zugangsdaten in Stream-URLs durch Platzhalter ersetzt
- VPN-Wächter mit Kill-Switch: ohne erkannten Tunnel keine Playlist-, Stream- oder Bildabrufe
- Wählbarer User-Agent für alle HTTP-Anfragen und libmpv, keine Telemetrie, kein Festplatten-Cache, keine Logs in Release-Builds
- Panik-Knopf löscht Playlists, Schlüsselbund, Einstellungen und Caches

macOS: Signierung mit Apple-Development-Zertifikat (Team in `macos/Runner/Configs/AppInfo.xcconfig`).
Ohne Provisioning-Profil nutzt die App den klassischen Schlüsselbund; mit `keychain-access-groups`
automatisch die Data-Protection-Keychain.

## Starten

```sh
flutter pub get
flutter run -d macos
```

Voraussetzungen: Flutter 3.47+, Xcode, CocoaPods (`brew install cocoapods`).

## Tests

```sh
flutter test                      # Unit-Tests (Parser, HLS-Auflöser, Namens-Bereinigung)

# Ende-zu-Ende mit echten öffentlichen Streams (macOS):
python3 integration_test/test_server.py &
flutter test integration_test/app_flow_test.dart -d macos
```

## Hinweis zu HLS

Das in media_kit mitgelieferte FFmpeg hängt bei HLS-Master-Playlists mit separaten
Ton-/Untertitelspuren (z. B. Das Erste). `lib/player/hls_resolver.dart` öffnet deshalb
direkt die beste Bildvariante und hängt die Tonspuren einzeln an.
