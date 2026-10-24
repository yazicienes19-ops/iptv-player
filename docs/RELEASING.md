# Releases und Versionsgeschichte

[Alle veröffentlichten Versionen](https://github.com/yazicienes19-ops/iptv-player/releases) bleiben mit ihrer Beschreibung, ihrem Quellstand und ihren Downloads erreichbar. Die automatische Veröffentlichung verändert keine bereits veröffentlichte Version und verschiebt keine bestehenden Tags.

## Wann entsteht ein Release?

Jeder Push auf `main` startet **Prüfen und veröffentlichen**, auch wenn nur die Dokumentation geändert wurde. Ein Push kann mehrere Commits enthalten: Er erzeugt eine gemeinsame Veröffentlichung mit allen Änderungen dieses Pushs. Lokale Änderungen und Arbeit auf anderen Branches sind noch keine Releases.

1. Der Workflow bestimmt Quellstand und nächste Versionsnummer.
2. Web-Tests, Python-Tests, Flutter-Analyse und Flutter-Tests müssen erfolgreich sein. Zusätzlich wird die Syntax sämtlicher TV-JavaScript-Dateien auf ES2016 geprüft.
3. Browser-ZIP, LG/webOS-IPK und macOS-ZIP werden gebaut.
4. Erst wenn alle drei Builds erfolgreich sind, werden Tag und Releaseentwurf für genau diesen Commit angelegt. Nach dem Upload aller Pakete und Prüfsummen wird der Entwurf öffentlich.

Pull Requests führen dieselben Tests und Paketbuilds aus, veröffentlichen aber nichts. Fehlschläge sind unter [Actions](https://github.com/yazicienes19-ops/iptv-player/actions) sichtbar. Der fehlgeschlagene Quellstand bekommt kein fertiges Release. Ein während des Uploads unterbrochener Lauf kann einen unveröffentlichten Entwurf hinterlassen; die Wiederholung setzt ihn fort.

Die ersten dokumentierten Versionen:

- **v1.0.0:** Nachträglich dokumentierter Ausgangsstand beim bisherigen Commit `61856cd`. Das ist keine Behauptung, dass damals bereits dieses Release oder diese Automatisierung existierte.
- **v1.1.0:** Die aktuellen Erweiterungen und die neue Releaseautomatisierung. Die Funktionen sind im [CHANGELOG](../CHANGELOG.md) beschrieben.

## Welche Version wird vergeben?

`version:` in `pubspec.yaml` ist die gewünschte **Untergrenze**. Ohne bestehende Release-Tags beginnt die Automatisierung dort. Sonst verwendet sie die größere der beiden Versionen: diese Untergrenze oder die nächste Patchversion nach dem höchsten vorhandenen `vMAJOR.MINOR.PATCH`-Tag.

Beispiele: Nach `v1.1.0` folgt automatisch `v1.1.1`, dann `v1.1.2`. Wird die Untergrenze im Quellcode auf `1.2.0` erhöht, heißt das nächste Release mindestens `v1.2.0`. Versionen werden numerisch verglichen; `1.10.0` liegt nach `1.9.9`. Vorab-Tags wie `v2.0.0-beta.1` zählen dabei nicht.

Die berechnete Version wird in die Downloadpakete übernommen. Der Quellcode bekommt dabei keinen zusätzlichen Bot-Commit; deshalb kann die Versionsuntergrenze im Repository hinter dem jüngsten Patchrelease liegen. Das vermeidet eine Endlosschleife aus Versionscommit und neuem Release. GitHub-Laufnummern dienen als Buildnummern.

Wiederholungen desselben Commits verwenden dessen bestehenden Tag. Ein fertiges Release bleibt unverändert. Wird ein älterer Commit nach einem neueren veröffentlicht, erhält er eine eigene Version, ersetzt aber den neueren Quellstand nicht als „Latest“.

## Verständliche Änderungsbeschreibungen

Für jede inhaltliche Änderung gehört eine kurze deutsche Beschreibung in eine neue Datei `.changes/<kurzer-name>.md`. Beschreibe, was sich für Anwender verbessert, wie es benutzt wird und welche Einschränkungen verbleiben. Die [Vorlage](../.changes/template.md) und die [Beitragsanleitung](../CONTRIBUTING.md) helfen dabei.

Der Release-Helper übernimmt:

- den passenden Abschnitt aus `CHANGELOG.md`, wenn dort die exakte Releaseversion steht;
- neue oder geänderte `.changes/*.md`-Dateien seit dem vorherigen Release dieses Quellstands;
- die zugehörigen Commit-Links, den vollständigen Quellstand und einen Vergleich mit dem vorherigen Release.

Alte Änderungsdateien bleiben als Geschichte erhalten und werden nicht bei jeder Veröffentlichung erneut ausgegeben. Fehlen solche Texte, enthält das Release weiterhin die Commitliste. Aussagekräftige Commit- und PR-Titel bleiben deshalb wichtig. Die Datei `.github/release.yml` ordnet zusätzlich die Kategorien der optionalen GitHub-Funktion „Generate release notes“; die automatische deutsche Beschreibung erstellt `scripts/release.py`.

## Downloads und Grenzen

| Download | Verwendung |
| --- | --- |
| `IpFlix-browser-v….zip` | Lokale Vorschau mit den enthaltenen Startskripten; Node.js 22 und Python 3 werden benötigt. |
| `com.enesyazici.ipflix_…_all.ipk` | LG/webOS-Paket für Installation über den Entwicklermodus. |
| `IpFlix-macOS-<architektur>-v….zip` | Mac-Testapp; die tatsächlichen unterstützten CPU-Architekturen stehen im Dateinamen. |
| `SHA256SUMS` | SHA-256-Prüfsummen für diese drei Pakete. |

Der Mac-Build läuft auf dem GitHub-Runner `macos-14` und wird lokal/ad hoc signiert. Er besitzt **keine Apple-Developer-ID-Signatur und keine Notarisierung**. macOS kann deshalb eine Sicherheitsbestätigung verlangen. Storeveröffentlichung und regulär signierte Auslieferung benötigen einen getrennten, später einzurichtenden Prozess.

Die Pakete enthalten weder IPTV-Zugangsdaten noch persönliche IMDb-Daten. Der GitHub-Workflow braucht keine Anbieterzugänge, Metadaten-API-Schlüssel oder Apple-Zertifikate. Ein erfolgreicher Paketbau bestätigt keine Wiedergabe auf jeder TV-Marke oder jedem Gerätemodell. Samsung, Android/Google TV und weitere Stores werden durch diesen LG-/Mac-/Browser-Workflow nicht automatisch beliefert.

## Fehlgeschlagenen Lauf wiederholen

Am einfachsten den betroffenen Lauf unter **Actions → Prüfen und veröffentlichen → Re-run all jobs** wiederholen. Dadurch werden auch Tests und Builds erneut ausgeführt. „Nur fehlgeschlagene Jobs wiederholen“ ist bei einem reinen Uploadfehler ebenfalls möglich, solange die vorherigen Buildartefakte noch vorhanden sind. Workflowartefakte werden 30 Tage aufbewahrt; öffentliche Releasedownloads bleiben bestehen.

Alternativ unter **Actions → Prüfen und veröffentlichen → Run workflow** den Branch `main` auswählen. Ohne Eingabe wird der aktuelle Stand geprüft. Für einen älteren Stand den vollständigen 40-stelligen Commit-SHA in `revision` eintragen. Der Commit muss bereits in der Geschichte von `main` liegen. Auch dieser Weg durchläuft Tests und Builds und kann deren Ergebnis nicht umgehen.

Main-Läufe werden ohne automatische Abbrüche nacheinander abgearbeitet. `concurrency.queue: max` hält bis zu 100 wartende Läufe vor; bei GitHub-Limits oder manuell abgebrochenen Läufen den betreffenden Stand wie oben wiederholen. GitHub garantiert die Reihenfolge der wartenden Läufe, nicht die Reihenfolge ihrer ursprünglichen Auslösung. Das Skript verhindert deshalb, dass ein nachträglich gebauter älterer Quellstand einen neueren als „Latest“ ersetzt.

## Repository-Einstellungen und Wartung

GitHub Actions muss im Repository zugelassen sein. Der Workflow hat standardmäßig nur Leserechte; ausschließlich der Veröffentlichungsjob fordert `contents: write` für Tags, Releasebeschreibung und Downloads an. Es ist kein persönlicher Token als Secret nötig. Organisationseinstellungen können diese Rechte oder externe Actions trotzdem einschränken; entsprechende Fehler stehen im Workflowprotokoll.

Actions sind auf konkrete Commit-SHAs festgelegt; daneben steht jeweils die geprüfte Versionsnummer. Flutter `3.47.8`, Node.js `22`, Acorn `8.15.0` und `@webos-tools/cli` `3.2.6` sind ebenfalls ausdrücklich festgelegt. Änderungen daran zuerst per Pull Request testen. Für verpflichtende Prüfungen vor jedem Merge sollte ein Repository-Administrator einen Branchschutz für `main` aktivieren; diese Repositorydateien richten selbst keinen Branchschutz ein.

Lokale Prüfungen der Releasewerkzeuge:

```sh
python3 -m unittest discover -s scripts/tests -v
python3 scripts/release.py plan --preview --output /tmp/ipflix-release-plan.json
```

Weiterführend: [GitHub-Warteschlangen](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency), [Berechtigungen des GITHUB_TOKEN](https://docs.github.com/en/actions/tutorials/authenticate-with-github_token) und [GitHub-Runner](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
