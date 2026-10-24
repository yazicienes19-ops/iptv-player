# Plattformen und gemeinsames Produkterlebnis

Stand: 24.10.2026. Ziel sind Browser, eine native Mac-App und Smart-TV-Apps mit
gleichwertiger Gestaltung und Bedienqualität. Alle Plattformen sind gleich wichtig.
Die Reihenfolge der technischen Arbeiten richtet sich nach gemeinsamen Abhängigkeiten,
nicht nach einer bevorzugten Marke.

Eine Marke ist keine ausreichende Kompatibilitätsangabe: Entscheidend sind
Betriebssystem, Modelljahr, Region und Decoder. Deshalb wird jede Freigabe mit
konkreten Geräten und Versionen dokumentiert. „Fast jede Marke“ ist das Produktziel,
keine bereits erreichte Unterstützung aller Fernseher.

## Was heute vorhanden ist

Das Projekt hat zwei Oberflächen: Flutter in `lib/` für native Geräte und
HTML/CSS/JavaScript in `webos/tv/` für den vorhandenen LG-Pfad und die lokale
Browser-Vorschau. Änderungen an einer Oberfläche verändern die andere nicht
automatisch. Gemeinsame Gestaltung, Datenmodelle und Verhalten müssen in beiden
Implementierungen abgestimmt werden.

Aktueller Designstand: Die JS-Startseite zeigt ein Titelmotiv und horizontale Reihen
mit realen Katalog-, Favoriten- und Fortschrittsdaten. Flutter verwendet dieselbe
Farb- und Gestaltungslinie. Die Browseroberfläche wurde bei 390, 1280 und 1920
Pixeln Breite geprüft, einschließlich Seriennavigation, Scrollen, MP4-Wiedergabe
und Rückkehr. Automatisierte Tests prüfen zusätzlich Player-Steuerung, Suche,
persönliche Senderreihen und neu hinzugefügte Filme. Diese Prüfungen sind keine
Tests auf echter TV-Hardware.

Die persönliche Empfehlungsreihe und „Gefällt mir / Nicht interessiert“ sind in
beiden Oberflächen implementiert. Die Web-Oberfläche nutzt native Buttons mit
sichtbarem Auswahlzustand sowie die vorhandene Fernbedienungsnavigation; Flutter
verwendet fokussierbare Bedienelemente. Empfehlungen berücksichtigen ausschließlich
verfügbare Filme/Serien der aktiven Playlist und Sprache. Bewertungs- und
Wiedergabedaten bleiben lokal; eine geräteübergreifende Synchronisierung ist nicht
implementiert. Diese Erweiterung erzeugt keine neuen Tizen-, Roku- oder VIDAA-Pakete.

Auf diesem Rechner ist derzeit nur `/Library/Developer/CommandLineTools` als
Apple-Entwicklerverzeichnis eingerichtet; Xcode.app wurde unter `/Applications`
nicht gefunden, `pod` ist nicht verfügbar. Deshalb wurde aus dem aktuellen
Designstand noch keine native Mac-App gebaut. Dafür vollständiges Xcode samt
macOS-SDK und CocoaPods einrichten, anschließend den Mac-Build und die Wiedergabe
prüfen.

| Ziel | Stand im Repository | Noch bis zu einer belastbaren Freigabe |
|---|---|---|
| **macOS als App** | Flutter, `media_kit`/libmpv, Mac-Projekt und Schlüsselbund vorhanden. Der frühere [Handoff](../HANDOFF.md) beschreibt eine installierte App. Flutter-Tests und Analyse wurden lokal geprüft; diese Prüfung ersetzt keinen neuen vollständigen Mac-Lauf. | Aktuellen Release-Build mit echten Medien, Vollbild und Ruhezustand testen; eigenes Signing und Verteilung einrichten. Für Download außerhalb des Stores: Developer ID und Notarisierung. [Apple](https://developer.apple.com/developer-id/) |
| **Browser: Safari, Chromium, Firefox** | `node webos/dev/start.js` liefert die JS-Oberfläche samt lokalem Proxy und Testanbieter. Login, Kataloge, Navigation, Scrollen und MP4 wurden in der eingebetteten Browser-Vorschau geprüft. `web/` enthält zusätzlich einen Flutter-Web-Einstieg, der keine freigegebene Web-Version darstellt. | Alle drei Browserfamilien separat testen; HLS-Wiedergabe, Ton/Untertitel, Eingaben und Medienfehler vereinheitlichen; Netzwerk- und Speicherlösung für eine gehostete Web-App festlegen. |
| **LG / webOS** | Eigene JS-Oberfläche, Node-Dienst und IPK-Bauskript vorhanden. Der Handoff dokumentiert Tests auf einem LG 65UM7100; die aktuellen Änderungen wurden hier nur lokal geprüft. | IPK erneut bauen und auf älteren sowie aktuellen Geräten testen; Lifecycle, Medien und Durchsatz prüfen; Store-Paket und Freigabe vorbereiten. LG unterscheidet ausdrücklich Simulator-, Geräte- und Veröffentlichungsprüfung. [LG-Workflow](https://webostv.developer.lge.com/develop/getting-started/developer-workflow) |
| **Samsung / Tizen** | Noch kein Tizen-Paket oder AVPlay-Adapter. Wiederverwendbare Web-Oberfläche ist eine Grundlage. | `config.xml`, Zertifikate, Remote-/Lifecycle-Adapter, Player und signiertes Paket erstellen; auf mehreren Modelljahren testen. Für über HTML5 hinausgehende Wiedergabe ist AVPlay vorgesehen. [Samsung-Start](https://developer.samsung.com/smarttv/develop/getting-started/quick-start-guide.html), [AVPlay](https://developer.samsung.com/smarttv/develop/guides/multimedia/media-playback/using-avplay.html) |
| **Android TV / Google TV** | Android-Projekt mit TV-Launcher, Banner, optionalem Touchscreen und Flutter-Fokus vorhanden. Ein hier geprüfter TV-Build fehlt; Release-Signing verwendet noch den Debug-Schlüssel. | APK/AAB bauen, native Abhängigkeiten und Speicherbedarf prüfen, sämtliche Abläufe mit D-Pad testen und Release-Signing einrichten. Android verlangt unter anderem vollständige Fernbedienung und passende Manifest-Einträge. [Android-TV-Anforderungen](https://developer.android.com/docs/quality-guidelines/tv-app-quality) |
| **Amazon Fire TV / Fire OS** | Android-Basis ist ein möglicher Ausgangspunkt, kein geprüfter Fire-TV-Build. | API-/SDK-Kompatibilität, Player, Remote und Store-Anforderungen je Fire-OS-Geräteklasse prüfen. Android-Kompatibilität ist ein Portierungsweg, keine automatische Freigabe. [Amazon-Portierung](https://developer.amazon.com/docs/app-porting/port-existing-app.html) |
| **Amazon Fire TV / Vega OS** | Kein Vega-Projekt vorhanden. Der bestehende Android-Build deckt diese Plattform nicht ab. | Eigenen Vega-Pfad samt Player und Lifecycle implementieren und testen; ein Vega-WebView ist eine mögliche zu prüfende Route. Vega verwendet ein eigenes VPKG statt APK; beide können unter einem Store-Eintrag geführt werden. [Amazon-Portierung](https://developer.amazon.com/docs/adbt/port-fire-os-app-to-vega), [Vega-Verteilung](https://developer.amazon.com/docs/vega/latest/app-submission) |
| **Roku** | Noch nicht implementiert. | Eigenen SceneGraph-/BrightScript-Client mit denselben Produktabläufen bauen; die vorhandene HTML-Seite ist kein Roku-Paket. [Roku-Konzepte](https://developer.roku.com/dev/docs/core-concepts-1) |
| **VIDAA und weitere TV-Systeme** | Keine Adapter oder geprüften Pakete vorhanden. | Entwickler-/Partnerzugang, Zielgeräte, Medien-APIs und Veröffentlichungsweg klären, dann integrieren. VIDAA beschreibt einen gesondert geregelten Partner-/Entwicklerzugang; ein allgemein zugänglicher Veröffentlichungsweg wird hier nicht vorausgesetzt. [VIDAA, Abschnitt 4.6](https://www.vidaa.com/terms-and-conditions/) |

LG bietet inzwischen ein natives Flutter-webOS-SDK für **webOS TV 26 Re:New und
neuer**. Das ist eine zusätzliche Option; es ersetzt keine Lösung für ältere
LG-Geräte. Der vorhandene JS-Pfad bleibt deshalb relevant.
[LG-Ankündigung](https://webostv.developer.lge.com/news/flutter-for-webos-tv-is-now-available-for-developers)

Beim nächsten LG-Paket müssen außerdem die aktuellen ACG-Vorgaben geprüft werden:
`requiredACG` fehlt im vorhandenen `appinfo.json`; LG nennt Warnungen seit September
2026 und eine verpflichtende Prüfung ab März 2027. Die benötigten Rechte sind aus
den tatsächlich genutzten Luna-Aufrufen abzuleiten. [LG-Hinweis](https://webostv.developer.lge.com/)

## Browser-Vorschau und veröffentlichte Web-App

Die aktuelle Vorschau läuft über `http://127.0.0.1:47823/`. API-Aufrufe, Bilder und
Video-URLs werden durch `/p` an den lokalen Node-Dienst geleitet. Auch die
Handy-Anmeldung benötigt diesen Dienst. Einfaches Hochladen der HTML-Dateien auf
einen statischen Host reicht dafür nicht. Eine PWA-Installation ergänzt ebenfalls
keinen fehlenden Proxy oder Decoder.

Für den Browser-Zielbetrieb muss eine dieser Varianten festgelegt und umgesetzt werden:

- Direkter Zugriff bei Anbietern, die passende HTTPS-Endpunkte und CORS für die
  benötigten API-/Playlist-Abrufe anbieten.
- Ein ausdrücklich eingerichteter lokaler Begleitdienst.
- Ein authentifizierter, begrenzter Serverdienst mit festgelegtem Umgang mit
  Anbieter-Zugangsdaten, Zieladressen und Stream-Traffic.

Der bestehende Loopback-Dienst ist nicht für eine öffentliche Freigabe vorbereitet.
Browser beschränken fremde API-Abrufe per CORS und unsichere HTTP-Inhalte auf
HTTPS-Seiten. Ein Proxy löst außerdem keine fehlenden Codecs.
[CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS),
[Mixed Content](https://developer.mozilla.org/en-US/docs/Web/Security/Defenses/Mixed_content)

Aktuell nutzt die TV-Oberfläche ein HTML-Videoelement. HLS, Container, Codecs und
Tonspuren müssen je Browser und TV geprüft werden; MP4-Erfolg belegt keine
MKV-/HEVC-/HLS-Unterstützung. Für nicht nativ unterstütztes HLS ist ein geeigneter
Browser-Player ein eigener Arbeitsschritt. Fähigkeiten können vorab erkannt werden,
der tatsächliche Wiedergabetest bleibt erforderlich.
[Medienprüfung im Browser](https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/canPlayType),
[LG-Medienmatrix](https://webostv.developer.lge.com/develop/specifications)

### Dateiendung und tatsächlich abspielbares Medium

Eine Endung wie `.mkv` oder `.mp4` bezeichnet zunächst den Container. Video- und
Audiocodec, Profil, Auflösung, Bitrate und Gerätehardware entscheiden über die
Wiedergabe. Der Proxy wandelt keine Medien um. Die M3U-Parser erkennen auch WebM,
OGV, MPG/MPEG, M2TS und VOB als Filmdateien; diese Katalogzuordnung ergänzt keine
fehlenden Decoder. `.ts`, `.m3u8` und `.mpd` werden ohne VOD-Angabe weiterhin nicht
pauschal als Film eingestuft.

| Medium | Browser-Version | Native Mac-App | LG/webOS |
|---|---|---|---|
| MP4 mit H.264/AAC | Geprüfte lokale Testbasis | Breite libmpv-Unterstützung; aktueller Geräte-Lauf steht aus | Innerhalb der Modellgrenzen unterstützt |
| MKV, AVI, MOV, MPEG und weitere Container | Abhängig vom eingebauten Browserplayer | libmpv/FFmpeg unterstützt viele Kombinationen | Container und enthaltene Codecs müssen zur Modellmatrix passen |
| HEVC/H.265, AV1, HDR, DTS/Dolby | Browser, Betriebssystem und Hardware entscheidend | Decoder und Hardware entscheidend | Modell und Jahrgang entscheidend |
| HLS | Nur native Browserunterstützung; kein HLS.js-Fallback | Implementiert, inklusive Workaround für separate Audiospuren | Grenzen je webOS-Version |
| DASH/DRM | Kein eigener DASH-Player oder DRM-Lizenzablauf | Kein DRM-Lizenzablauf implementiert | Gerätefähigkeit ersetzt die fehlende App-Integration nicht |

Der native HLS-Workaround übernimmt derzeit separate Audio-Renditions, aber keine
separaten Untertitel-Renditions. RTSP/UDP/SRT sind im HTTP-Proxy der Browser-Version
nicht implementiert. Der Demoanbieter kann dieselbe MP4-Datei auch hinter einer
`.mkv`-Adresse liefern; das bestätigt keine echte MKV-/HEVC-Unterstützung.

Quellen: [MDN Container und Codecs](https://developer.mozilla.org/en-US/docs/Web/Media/Guides/Formats/Containers),
[media_kit](https://github.com/media-kit/media-kit#supported-formats),
[LG Medienmatrix für webOS 25](https://webostv.developer.lge.com/develop/specifications/video-audio-250),
[LG Streaming-Protokolle](https://webostv.developer.lge.com/develop/specifications/streaming-protocol-drm).

Auch Datenschutzfunktionen unterscheiden sich heute: Die native App nutzt
`flutter_secure_storage`, die JS-Oberfläche `localStorage`. Der native VPN-Wächter
ist keine nachgewiesene Schutzfunktion der Browser-/TV-Oberfläche. Diese Unterschiede
müssen vor einer gemeinsamen Produktfreigabe technisch und in der Oberfläche geklärt sein.

## Gemeinsame Umsetzungsschritte

1. **Ein gemeinsames Produkterlebnis festlegen.** Ruhige dunkle Flächen, hochwertige
   Titelbilder, klare Typografie, großzügige Abstände, zurückhaltende Bewegung,
   verständliche Lade-/Leer-/Fehlerzustände. Gemeinsame Abläufe für Start, Live-TV,
   Filme, Serien, Suche, Merkliste und Weiterschauen. Maus, Touch und Fernbedienung
   erhalten passende Bedienelemente; Fokus, Zurück und Scrollposition bleiben verlässlich.
2. **Gemeinsame Verträge schaffen.** Dieselben Katalog-, Fortschritts- und
   Player-Zustände in beiden Clients definieren. Transport, Zugangsdaten, Playback,
   Remote-Tasten und App-Lifecycle hinter klaren Plattformadaptern trennen.
   Das Aussehen wird geteilt; Decoder und Betriebssystemfunktionen bleiben plattformspezifisch.
3. **Alle Plattformpfade parallel vervollständigen.** Browser-Netzwerkmodell und
   Player, native Mac-Verteilung, LG-Paket, Android-/Fire-OS-Build sowie Tizen-,
   Vega-, Roku- und VIDAA-Anbindung jeweils mit eigenen Abnahmekriterien führen.
   Fehlender Store-/Partnerzugang wird als offene Abhängigkeit dokumentiert.
4. **Jede Plattform anhand derselben Szenarien freigeben.** Anmeldung → Katalog →
   Suche → Film/Folge → Wiedergabe → Zurück → Fortsetzen; zusätzlich Live-Zapping,
   Untertitel/Ton, Netzunterbrechung, Hintergrund/Vordergrund und große Playlists.
   Modell, OS-Version, getestete Medien und bekannte Grenzen erfassen. Echte
   Geräteprüfung, signierte Pakete und Store-Abnahme sind getrennte Freigabeschritte.

Ein neues Design allein bestätigt keine neue Plattformunterstützung. Als „unterstützt“
wird ein Ziel erst bezeichnet, wenn sein vollständiger Ablauf auf den angegebenen
Geräten beziehungsweise Browsern geprüft und sein Installationsweg verfügbar ist.
