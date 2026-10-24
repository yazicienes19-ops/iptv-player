# IMDb-Kategorien und Suche

Die Filmreihen verwenden die offiziellen [IMDb Non-Commercial Datasets](https://data.imdb.com/non-commercial-datasets/). `title.ratings.tsv.gz` liefert Bewertung und Stimmenzahl; `title.basics.tsv.gz` liefert Titel, Originaltitel, Jahr und bis zu drei Genres. IMDb aktualisiert diese Dateien täglich.

Der lokale Katalog enthält standardmäßig Kinofilme mit mindestens **25.000 Stimmen**, ohne als `isAdult` markierte Titel. Innerhalb deiner verfügbaren Playlist wird nach IMDb-Bewertung absteigend sortiert, bei Gleichstand nach Stimmenzahl. Das ist eine eigene Auswahl aus deiner Mediathek und **keine Kopie der offiziellen IMDb Top 250**. Bei „Krimis“ wird das IMDb-Genre `Crime` verwendet. Ein Film kann mehreren Genres angehören.

## Lokal vorbereiten oder aktualisieren

```sh
python3 scripts/build_imdb_catalog.py
```

Der erste Lauf lädt die beiden offiziellen komprimierten Datensätze in `build/imdb/`. Insbesondere die Titeldaten sind mehrere hundert MB groß. Das Skript liest sie zeilenweise, ohne den gesamten entpackten Bestand in den Arbeitsspeicher zu laden. Es schreibt den kleinen gefilterten Katalog atomar nach `webos/tv/data/imdb.json`. Anschließend die App neu laden. Ein fehlgeschlagener Import lässt einen vorhandenen Katalog unverändert.

Für neue Daten:

```sh
python3 scripts/build_imdb_catalog.py --refresh
```

Für Listen, die nur übersetzte Filmtitel enthalten, kann der Katalog zusätzlich
Alternativtitel übernehmen:

```sh
python3 scripts/build_imdb_catalog.py --with-aliases
```

Dabei wird einmalig die große offizielle Datei `title.akas.tsv.gz` zwischengespeichert
und zeilenweise ausgewertet. Nur Alternativtitel der ausgewählten Filme für
DE/AT/CH/TR/US/GB beziehungsweise die Sprachen Deutsch, Englisch und Türkisch
landen im kleinen App-Katalog. Als Arbeits-, Entwicklungs-, künstliche oder
Werbetitel markierte Varianten werden dabei ausgeschlossen. Andere Sprachen bleiben über Originaltitel
auffindbar, wenn diese übereinstimmen. Die zusätzlichen Daten werden ebenso
lokal verarbeitet. Ohne `--with-aliases` enthält ein neu gebauter Katalog nur
Primär- und Originaltitel; bei späteren Aktualisierungen die Option daher
beibehalten. In der Mac-App anschließend den aktualisierten Katalog importieren.

`--min-votes`, `--limit` (Standard 15.000 Filme), `--cache-dir` und `--output` lassen sich anpassen. Download und generierter Katalog werden nicht in Git eingecheckt. Die Daten werden nicht beim Start der App aus dem Internet geladen; der Player liest nur die lokale JSON-Datei. Datumsanzeige und Stimmenuntergrenze stammen aus dieser Datei.

## Mac-App / Flutter

In **Einstellungen → IMDb-Ranglisten → IMDb-Katalog importieren** dieselbe Datei `webos/tv/data/imdb.json` auswählen. Die App prüft Format und Bewertungen, kopiert den persönlichen Katalog in ihr eigenes Datenverzeichnis und lädt ihn beim nächsten Start wieder. Eine ungültige Datei ersetzt keinen vorhandenen Katalog. Mit „Katalog aktualisieren“ lässt sich später ein frisch erzeugter Stand importieren. „Alle lokalen Daten & Cache sofort löschen“ entfernt auch diesen Import.

Danach erscheinen auf der Startseite die verfügbaren besten Filme und Krimis. Im Filmbereich lassen sich IMDb-Genre-Filter wählen; zugeordnete Poster tragen eine ausdrücklich als IMDb bezeichnete Bewertung. Die Suche unterstützt auch ohne Import Tippfehler, Anbieter-Genres, Besetzung und „Filme wie …“, soweit die Playlist Metadaten mitliefert. IMDb ergänzt Genres nur bei sicherer Zuordnung. Es werden keine persönlichen IMDb-Daten als Flutter-Asset mit der App gebündelt.

## Zuordnung und Suchverhalten

Eine IMDb-ID des Anbieters hat Vorrang. Ohne ID werden bereinigter Titel,
Originaltitel und vorhandene Alternativtitel verglichen. Mit Jahr muss dieses
übereinstimmen. Ohne Jahr darf es im geladenen Katalog nur einen exakten Treffer
geben. Bei mehreren gleichnamigen Filmen, einer unbekannten expliziten ID oder
fehlenden Metadaten bleibt die Zuordnung leer. Anbieter- und TMDb-Bewertungen
dienen niemals als Ersatz für IMDb.

Bekannte Länderpräfixe sowie Qualitäts- und Codec-Zusätze werden entfernt. Ein
Jahr wie `(1994)` oder `[1994]` wird erkannt; ein bloß angehängtes `1994` erst,
nachdem der vollständige Titel keinen Treffer ergibt. Zahlen, die zum Titel
gehören, wie `1917`, `2001: A Space Odyssey` oder `Blade Runner 2049`, bleiben
erhalten. Mehrstellige römische Fortsetzungsnummern am Titelende (II, III, IV,
VI, VII, VIII, IX) werden beim Vergleich auch als arabische Ziffern verstanden;
der Anzeigename bleibt unverändert. Einzelbuchstaben wie in `Malcolm X` und
alleinstehende römische Titel werden nicht umgeschrieben. Entsteht durch diese
Normalisierung eine Mehrdeutigkeit, bleibt die Zuordnung leer. Tippfehlertoleranz der Suche wird bewusst nicht für die automatische
Metadatenzuordnung verwendet.

Ein eindeutiger Treffer im lokalen Katalog ist keine Garantie für weltweit
vollständige Erkennung: Der Stimmenfilter, fehlende Alternativtitel und
mehrdeutige Anbieterangaben begrenzen die Abdeckung. Nicht zugeordnete Inhalte
bleiben regulär auffindbar und abspielbar, erhalten aber keine erfundenen Genres
oder Bewertungen. TMDB-Suchergebnisse werden ebenfalls nur bei eindeutiger
exakter Titelzuordnung übernommen, nicht nach Popularität oder Ergebnisposition.

Die lokale Suche berücksichtigt Titel, kleine Tippfehler, Genres auf Deutsch/Englisch, Jahr und vorhandene Angaben zu Besetzung und Regie. „Filme wie …“, „wie …“ und „ähnlich wie …“ nutzen gemeinsame Genres und Personen. Fehlen solche Angaben, kann die gemeinsame Anbieterkategorie als schwächeres Signal dienen. Die Suche zeigt ausschließlich verfügbare Playlist-Einträge; sie erfindet keine Empfehlungen oder Verfügbarkeiten.

## Quelle und Verwendung

IMDb beschreibt die Datensätze für persönliche, nicht kommerzielle Nutzung und erlaubt lokale Kopien unter seinen [Nutzungsbedingungen](https://help.imdb.com/article/imdb/general-information/can-i-use-imdb-data-in-my-software/G5JTRESSHJBBHTGX). Dieser Import ist für den persönlichen lokalen Katalog eingerichtet. Generierte Dateien nicht mit einem öffentlich verteilten App-Paket ausliefern; für die Veröffentlichung oder kommerzielle Nutzung die passende [IMDb-Datenlizenz](https://data.imdb.com/) einrichten.

Information courtesy of IMDb (https://www.imdb.com). Used with permission.

`scripts/build_webos.sh` lässt den persönlichen Katalog standardmäßig aus dem TV-Paket weg. Für die Installation ausschließlich auf dem eigenen Gerät kann er mit `INCLUDE_PERSONAL_IMDB=1 scripts/build_webos.sh` eingebunden werden.

## Schnittstelle

- `App.imdbCatalog.load()` lädt `/data/imdb.json`; fehlende Daten ergeben einen Status mit `available: false`, keinen Fehlerbildschirm.
- `App.imdbCatalog.status()` liefert `available`, `source`, `attribution`, `generatedAt`, `minVotes` und `count`.
- `App.imdbCatalog.match(item)` liefert den sicher zugeordneten IMDb-Datensatz oder `null`.
- `App.rankedMovies(items, genre, { limit: 16 })` liefert denselben Quellenstatus, `matchedCount` und `items`. Treffer sind Kopien der Playlist-Einträge mit zusätzlichem `imdb`-Datensatz.
- `App.catalogTitle(raw)` bereinigt bekannte Anbieterzusätze und liefert `title` und optional `year`.
- `App.catalogIdentity(item)` liefert `imdb:tt…` bei einer eindeutigen Zuordnung, sonst `null`.
- `App.catalogFeatures(item)` liefert Identität, bereinigten Titel, Jahr, kanonische Genres sowie vorhandene Besetzung/Regie für lokale Empfehlungen. Leere Anbieter-Genres werden aus einem passenden Katalogtreffer ergänzt.
- `App.catalogSearch(items, query, { limit: 100, similarTo: optionalItem })` liefert sortierte ursprüngliche Playlist-Einträge.

Katalogdaten: `schemaVersion`, `generatedAt`, `minVotes`, `movies`. Jeder Film besitzt `id`, `title`, `originalTitle`, `year`, `genres`, `rating` und `votes`; `aliases` ist eine optionale Liste zusätzlicher Titel. Alte Dateien ohne dieses Feld bleiben kompatibel.
