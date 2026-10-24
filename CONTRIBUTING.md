# An IpFlix mitarbeiten

IpFlix besitzt zwei Oberflächen: Flutter in `lib/` und Browser/LG-TV in
`webos/tv/`. Eine Änderung an einer Oberfläche verändert die andere nicht
automatisch. Gemeinsame Funktionen sollten in beiden umgesetzt und geprüft werden;
Plattformgrenzen gehören in die Beschreibung des Beitrags.

## Lokale Einrichtung

1. Repository klonen und einen Arbeitsbranch anlegen, zum Beispiel
   `feature/persoenliche-startseite` oder `fix/serien-navigation`.
2. Für die Browser-Vorschau Node.js 18+ und Python 3 installieren, dann
   `node webos/dev/start.js` ausführen. Die [README](README.md#schnell-ausprobieren)
   enthält die Demo-Anmeldung.
3. Für Flutter den im [Release-Leitfaden](docs/RELEASING.md) festgelegten SDK-Stand
   verwenden und `flutter pub get` ausführen. Ein laufender Mac-Build benötigt
   zusätzlich vollständiges Xcode und CocoaPods.

Bitte keine privaten IPTV-Zugänge für automatisierte Tests verwenden. Der
Demoanbieter und kleine Test-Fixtures reichen für die meisten Änderungen aus.

## Eine Änderung einreichen

- Beschreibe zuerst, welches Problem die Änderung löst und was sich für Nutzer
  dadurch verbessert. Ein aussagekräftiger PR-Titel wird auch in der
  Veröffentlichungshistorie sichtbar.
- Ergänze eine kurze Markdown-Datei unter `.changes/`, zum Beispiel
  `.changes/serien-navigation.md`. Beschreibe konkrete Auswirkungen statt nur
  Dateinamen oder „diverse Verbesserungen“. Die Release-Automatik übernimmt neue
  oder geänderte Notizen seit der vorigen Version. Alte Notizen bleiben erhalten;
  für eine neue Änderung eine neue Datei anlegen.
- Passe die README oder die passende Dokumentation an, wenn sich Einrichtung,
  Verhalten oder Plattformunterstützung ändern.
- Öffne einen Pull Request gegen `main` und fülle die Vorlage aus. Die automatischen
  Prüfungen müssen erfolgreich sein, bevor die Änderung übernommen wird.

Beispiele für verständliche Titel:

- `feat: Empfehlungen anhand von Likes auf der Startseite anzeigen`
- `fix: Beim Zurückgehen aus einer Serie die Scrollposition erhalten`
- `docs: Installation des LG-Pakets erklären`

Beispiel für eine Änderungsnotiz:

```md
# Zurück zur richtigen Folge

Beim Verlassen einer Seriendetailseite bleibt die zuletzt gewählte Folge
sichtbar. Mit der Fernbedienung muss nicht mehr vom Anfang navigiert werden.

Geprüft mit Tastatur und Maus in der Browser-Vorschau sowie den Navigationstests.
```

Größere Versionsstände werden zusätzlich in [CHANGELOG.md](CHANGELOG.md)
zusammengefasst. Ein zur Versionsnummer passender Changelog-Abschnitt erscheint
ebenfalls in den Release-Notizen. Fehlt eine eigene Änderungsnotiz, bleibt die
automatische Commit-Liste als Mindestbeschreibung erhalten.

## Passende Prüfungen

```sh
# Browser-/TV-Oberfläche und lokaler Hilfsdienst
node --test webos/test/*.test.cjs

# Native App
flutter analyze
flutter test

# Python-Helfer
python3 -m py_compile webos/dev/mock_xtream.py scripts/build_imdb_catalog.py
```

Prüfe bei UI-Änderungen den vollständigen Ablauf: öffnen → bedienen → zurückkehren
→ erneut öffnen. Für Bewertungen und Verlauf zusätzlich speichern, neu laden und
zwischen Playlists wechseln. Prüfe ein schmales und ein breites Fenster sowie
Pfeiltasten, Enter und Escape. Ein Screenshot mit Demo-Inhalten macht sichtbare
Änderungen leichter verständlich.

Für einen gezielten Ende-zu-Ende-Test der nativen App:

```sh
# In einem eigenen Terminal:
python3 integration_test/test_server.py

# Mit eingerichteter macOS-Entwicklungsumgebung:
flutter test integration_test/app_flow_test.dart -d macos
```

Die TV-Oberfläche muss zu Chrome 53 / webOS 4 passen: kein `async/await`, optionales
Chaining, Objekt-Spread, `Object.entries`/`Object.values` oder nicht unterstützte
CSS-Funktionen verwenden. Der lokale Dienst in `webos/service/` muss zusätzlich
mit der älteren Node-Laufzeit des bestehenden LG-Pfads funktionieren. Die CI prüft
die JavaScript-Syntax; echte TV- und Medienprüfungen bleiben erforderlich.

## Releases

Arbeitsbranches und Pull Requests erstellen noch kein öffentliches Release.
**Nach jeder erfolgreich geprüften Übernahme auf `main` wird automatisch eine
neue Version veröffentlicht.** Das gilt auch für reine Dokumentationsänderungen.
Ein fehlgeschlagener Build veröffentlicht keine halbfertige Version.

Neue Versionen ergänzen die bestehende Historie. Veröffentlichte Tags und
Downloads nicht nachträglich verschieben, ersetzen oder löschen. Korrekturen
gehören in eine weitere Version. Details zu Versionsnummern, Release-Notizen und
Wiederholungen stehen in [docs/RELEASING.md](docs/RELEASING.md).

## Zugangsdaten und Metadaten

Keine Passwörter, API-Schlüssel, privaten Playlist-URLs, Anmeldedaten in Screenshots
oder persönlichen IMDb-Datensätze einchecken. `build/`, `dist/` und der erzeugte
IMDb-Katalog werden bewusst nicht versioniert. Metadaten-Lizenzen sind von der
Software getrennt zu betrachten; siehe [docs/IMDB.md](docs/IMDB.md).

Für neue Abhängigkeiten vorhandene Lizenzhinweise beibehalten und den Zweck im
Pull Request erklären. Änderungen an Signierung, Veröffentlichung oder
Netzwerkzugriff ausdrücklich beschreiben.
