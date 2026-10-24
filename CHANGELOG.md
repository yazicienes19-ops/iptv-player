# Änderungen

Hier stehen die für Nutzer sichtbaren Neuerungen und Korrekturen. Die vollständigen
Änderungen eines Releases sind zusätzlich auf der jeweiligen
[GitHub-Release-Seite](https://github.com/yazicienes19-ops/iptv-player/releases)
mit dem zugehörigen Quellcode verknüpft. Ältere Einträge bleiben erhalten.

## [Unreleased]

Noch nicht veröffentlichte Änderungen werden hier gesammelt. Dieser Abschnitt
ist kein veröffentlichtes Release.

## [1.1.0] – 2026-10-24

### Neue Funktionen

- Moderne Startseite mit Titelmotiv und horizontalen Reihen für Filme, Serien,
  Live-TV und die eigene Merkliste.
- „Für dich empfohlen“ mit lokal berechneten Vorschlägen aus Likes, Merkliste
  und tatsächlicher Film-/Seriensehzeit. „Gefällt mir“ und „Nicht interessiert“
  lassen sich auf Detailseiten jederzeit zurücknehmen.
- „Deine meistgesehenen Sender“ nach tatsächlicher Sehzeit und „Neu in deiner
  Liste“ für hinzugefügte Filme der letzten 30 Tage.
- Suche nach Titel, Genres und vorhandenen Personenangaben, kleine
  Tippfehlerkorrektur und ähnliche Titel über „Filme wie …“.
- Optionale IMDb-Ranglisten für verfügbare Filme, Krimis und weitere Genres;
  persönlicher Katalogimport in der nativen App.
- Titelabgleich auch bei Listen ohne Film-ID oder Jahr: bereinigte Anbieterzusätze,
  optionale Sprachvarianten und römische Fortsetzungsnummern. Mehrdeutige Titel
  werden nicht automatisch mit geratenen Filmdaten verbunden.
- Player-Bedienung mit Zurück-Pfeil, ±10 Sekunden, Zeitleiste, Bildschirmsperre,
  Geschwindigkeit, Bildformat und verfügbaren Ton-/Untertitelspuren.
- Lokale Browser-Vorschau mit einem Startbefehl, Demoanbieter und optionalem
  lokal erzeugten Testvideo. Ein zusätzlicher Testmodus simuliert Listen mit
  ausschließlich Filmtiteln.

### Verbesserungen und Fehlerbehebungen

- Rückkehr aus Details und Player sowie Browser-Zurück/Vorwärts vereinheitlicht.
  Serien- und Folgenansichten lassen sich scrollen; Tastaturfokus bleibt sichtbar.
- Maus-, Touchpad- und Fernbedienungsnavigation verbessert, einschließlich
  schmaler Fenster und verspätet nachgeladener Inhalte.
- Empfehlungen und Bewertungen bleiben pro Playlist getrennt; spätere Metadaten
  ergänzen bestehende Bewertungen, ohne sie erneut abzugeben.
- Echte Sehzeit zählt für Empfehlungen und Senderreihen. Pausen, Pufferung,
  Fehler und Spulen erzeugen keine künstliche Sehzeit.
- Native Favoriten und Verlauf vollständig in den verschlüsselten Speicher
  verschoben; ältere Einträge werden migriert. Die Löschfunktion beschränkt sich
  auf app-eigene Dateien.
- Lokale Anmeldeübergabe gegen fremde Webseiten abgesichert; fehlerhafte
  Adressen und Anfragen beenden den Hilfsdienst nicht mehr.
- M3U-Verarbeitung für Namen mit Kommas und zusätzliche Film-Dateiendungen
  verbessert. TMDB-Zuordnung übernimmt keine beliebigen ersten Suchtreffer mehr.

### Repository und Veröffentlichung

- Automatische Prüfungen und versionierte Releases nach erfolgreichen
  Änderungen auf `main`, mit nachvollziehbaren Änderungsbeschreibungen.
- README, Beitragsleitfaden und Dokumentation zu Plattformen, Metadaten und
  Releases neu geordnet.
- Ältere Releases und Tags bleiben erhalten. Persönliche IMDb-Dateien,
  Zugangsdaten und lokale Build-Caches gehören nicht in veröffentlichte Pakete.

### Bekannte Grenzen

- Medienformate hängen weiterhin von Browser, Betriebssystem und Gerät ab;
  keine automatische Videoumwandlung und kein integrierter DRM-Lizenzablauf.
- Empfehlungen und Verlauf werden nicht zwischen Geräten synchronisiert.
- Weitere Smart-TV-Systeme benötigen eigene Anbindungen. Erfolgreiche
  automatische Tests und Paket-Builds ersetzen keine Tests auf echter Hardware.

## [1.0.0] – 2026-10-24

**Nachträglich dokumentierter Ausgangsstand**, zugeordnet zu
[Commit `61856cd` vom 23.10.2026](https://github.com/yazicienes19-ops/iptv-player/commit/61856cd).
Diese Versionsbezeichnung macht den Stand vor der Überarbeitung auffindbar;
sie behauptet keine damals bereits veröffentlichte GitHub-Version.

Enthalten waren die native Flutter-App und die separate LG-webOS-Oberfläche,
Xtream-/M3U-Anmeldung, Live-TV, Filme und Serien, Kategorien, Favoriten,
Länderfilter, TMDB-Details sowie Anmeldung am Fernseher über das Handy.

Frühere Entwicklungsschritte bleiben in der
[Commit-Historie](https://github.com/yazicienes19-ops/iptv-player/commits/main/)
erhalten, unter anderem die Einführung der macOS-/iOS-Basis, das Live-TV-Raster
und die LG-Oberfläche. Sie werden nicht nachträglich als einzeln veröffentlichte
Releases ausgegeben.

[Unreleased]: https://github.com/yazicienes19-ops/iptv-player/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/yazicienes19-ops/iptv-player/releases/tag/v1.1.0
[1.0.0]: https://github.com/yazicienes19-ops/iptv-player/releases/tag/v1.0.0
