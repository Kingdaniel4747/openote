# Aufgaben

Stand: 25.11.2026. Nur aktuelle Arbeit und bekannte Grenzen, keine Versionschronik.

## Nächstes Release

Vor dem nächsten manuellen Hauptrelease die folgenden Punkte durch die dann aktuellen
Änderungen aus Nutzersicht ersetzen. Die Markierungen erhalten. Der Workflow
übernimmt diesen Inhalt nur, wenn er sich gegenüber dem letzten Release ändert;
sonst werden Wartungshinweis und neue Commits ausgegeben.

<!-- release-notes:start -->
- Neue englische Website-Seite „Features & guide“ mit vollständigerer Übersicht
  und Anleitungen für MCP-Lernzugriff, Screen-Clips, Stift/Touch, drei Seitenmodi,
  PDF-Bearbeitung, Split-Screen, adaptive Tinte und lokale Windows-Schreibprüfung.
- README mit visuellem Einstieg, Download-Schaltflächen, Navigation und echten
  App-Ansichten in Hell/Dunkel sowie Notizbuch- und Scanner-Bildern neu aufgebaut.
- Projektwebsite ausschließlich auf Englisch umgestellt und mit echten Bildern,
  neuem Layout, Bedienhilfe und genauerem Android-Scanner-Ablauf überarbeitet.
<!-- release-notes:end -->

## macOS-Erstprüfung

- Universal-DMG im gemeinsamen Release-Workflow ergänzt (Intel und Apple Silicon,
  macOS ab 12), einschließlich Rust-OneNote-Import. Noch kein macOS-Build gelaufen.
- Nach dem ersten manuellen macOS-Build CI und Installation auf beiden Architekturen
  prüfen: Start, Speichern/Neustart, PDF, Import/Export, Video, Android-Scan und MCP.
- Pakete sind nur ad-hoc signiert; Developer-ID/Notarisierung bleibt offen.
  Gatekeeper-Freigabe und manuelles Ersetzen bei Updates stehen in README.md.

## Linux-Erstprüfung

- Vorhandene DEB-/RPM-Paketierung in den gemeinsamen Release-Workflow eingebunden;
  x64-Build in Debian 12 mit Rust-Importer, mindestens glibc 2.36 und libmpv.so.2.
- Ersten CI-Build sowie Installation, Menü-/Dateistart, Speichern/Neustart, PDF,
  Video, OneNote-Import, Android-Scan und MCP auf Linux prüfen.
- Lokale Tests prüfen die Abhängigkeitskontrolle; echte DEB/RPM-Fixtures laufen
  zusätzlich in der Linux-CI. Unter Windows kein vollständiger Linux-Build möglich.
- Lokal 22 Release-/Paketierungstests bestanden, ein echter Linux-Pakettest
  übersprungen. QuickJS wird nach der Bundle-Bereinigung erneut mitkopiert.

## Manuelle Workflows

- Pushes starten keine Builds oder Deployments. In Actions einzeln „Build Windows
  package“, „Build macOS package“ oder „Build Linux package“ starten; Ergebnisse
  unter Artifacts, 7 Tage aufbewahrt. Diese Läufe veröffentlichen nichts.
- „Main release“ baut gemeinsam und veröffentlicht nach Erfolg aller Plattformen.
  „Publish website“ muss ebenfalls manuell gestartet werden.

## Veröffentlichung vorbereiten

- Pages-Quelle im Nutzerscreenshot auf „GitHub Actions“ gesetzt; neue Änderungen
  selbst auf `master` pushen. Kein Push oder Release in dieser Sitzung.
- Bestehende Android-Signatur-Secrets erhalten; GitHub-Build und gemeinsame
  Release-Dateien nach dem ersten manuellen Hauptrelease prüfen. Live-CI ersetzt keine Geräteprüfung.
- Website im GitHub-About verlinken; nach dem Deployment Search Console einrichten
  und `https://kingdaniel4747.github.io/openote/sitemap.xml` einreichen.
- Öffentliche Screenshots aus den echten Widgets mit isolierten Beispieldaten
  gerendert und angesehen: drei Windows- und zwei Scanner-Ansichten. Einige echte
  Android-Beschriftungen sind noch Deutsch; die Website selbst bleibt Englisch.
- Geprüft: 16 Node-Tests bestanden, drei opt-in Screenshot-Tests bestanden;
  Analyse beider neuer Dart-Dateien ohne Befund. 46 lokale Links/Anker und
  Assets, HTML-Verschachtelung, SVG/Sitemap-XML sowie Software-JSON-LD geprüft.
  Lokale Website liefert HTTP 200; `git diff --check` sauber.
- Browser-Sichtprüfung bleibt offen: Die Umgebung hat die Firefox-Steuerung
  wegen fehlender URL-Policy-Unterstützung gestoppt. Kein Live-Deploy in dieser Sitzung.

## Übergabe für den nächsten Chat

Bedienregeln und entfernte Funktionen stehen in PRODUCT.md, Code-Einstiegspunkte
und Datenflüsse in ARCHITECTURE.md. Die letzten Änderungen umfassen Navigation,
Kontextmenüs/Codebereinigung, Import-/Exportfortschritt, Original-Deduplizierung
und das Fortsetzen vorhandener Medienreihen sowie PDF-Nachschärfen/Prozessende.
Nächster sinnvoller Schritt ist
die Geräteprüfung unten; bestehende Funktionen nicht wieder ergänzen, nur weil
alte Tests oder Kommentare sie erwähnen. Vor Änderungen den lokalen Diff lesen.

Aktueller automatisierter Stand, keine grüne Gesamtsuite:

| Bereich | Letzte Prüfung |
|---|---|
| Handschrift: Größe und Abstände | 30 gezielte Dialog-/Profiltests bestanden; Analyse der vier geänderten Dart-Dateien sauber, lokale Windows-Beta erfolgreich gebaut (Dart-Kern, ohne Cargo). Bisherige Standards 28/600/1/1 auf allen Reglern mittig; alle Werte reduzierbar, Zeilenabstand bis 0,5. A5-Begrenzung auch bei maximaler Schriftgröße geprüft. Bedienprüfung am Gerät offen |
| Eigene Handschrift (Beta) und Lasso-Farbe/-Dicke | 101 gezielte Handschrift-/Druck-/Pointer-/Touch-/Stifttasten-/Ink-Tests bestanden; Analyse sauber, Windows-Release-Build erfolgreich (Dart-Kern, lokal ohne Cargo). Einlernen und Bearbeiten mit fester mittlerer Dicke 2,5; alte Vorlagen behalten Geometrie/Sensormetadaten, erzeugte Striche sind ebenfalls druckunabhängig und nachträglich in der Dicke änderbar. Fehlende Endmeldungen, Removed, neuer Kontakt, Hover, Fokus-/App-Wechsel, Hot Reload und späte Meldungen nach Schließen geprüft. Handballenschutz bereinigt verlorene Kontakte je physischem Gerät, alte Hände und andere aktive Stifte bleiben geschützt. Kreis-Pfeil, automatischer neuer Entwurf bis fünf Varianten, vollständiger Profil-Reset, 160-Pixel-Feld und Abstände bleiben erhalten. Konkreten sporadischen Gerätehänger erneut am Gerät prüfen; Hot Reload ist als alleinige Ursache nicht belegt. Verbundene Schreibschrift/Lernen aus Notizen fehlen; drei alte Einstellungen-Erwartungen in `command_bar_compact_test.dart` bleiben separat bekannt |
| Kalender: direkte Eingabe und Tagesübersicht | 119 gezielte Planer-/Erinnerungs-/Layouttests bestanden. Direkt rechts anlegen/bearbeiten, feste Tagesleiste mit „Alle anzeigen“, feste Speichern-/Abbrechen-Knöpfe, Farbpunkt und aktueller-Monat-Knopf. Entwürfe, vollständige Notizen, stabile Seitenziele, alte Uhrzeiten und Farbspeicherung geprüft. Betroffene Dart-Dateien ohne Analysebefund; Hell/Dunkel und 560-Pixel-Fenster mit 130 % Schrift gerendert und visuell geprüft. Geräteprüfung offen |
| Einstellungen, Seitenlöschung, Touch-Menüs und dauerhafte Stiftauswahl | 79 gezielte Tests bestanden, zusätzlich deutscher Einstellungsdialog/Sprachwechsel bestanden. Danach nur Einstellungen neu gestaltet: Themenleiste ohne Haken, einheitliche Felder, direkte Designauswahl und erklärende Zeilen. Vier Layout-/Bedientests bei 400/540/1000 Pixel Breite, Hell/Dunkel, Deutsch/Englisch und 130 % Schrift sowie Sprachwechsel bestanden; Ansichten gerendert und visuell geprüft. Gezielte Analyse der vier Einstellungsdateien sauber. Bedienung am Gerät offen |
| App, kompletter Dart-Quellbaum | `flutter analyze --no-pub`: keine Probleme gefunden (25.11.2026) |
| Notebook-Auswahl und Backup-Dialog | 17 gezielte UI-/Backup-/Lifecycle-Tests bestanden; Analyse der fünf betroffenen Dart-Dateien sauber. Helle/dunkle Ansichten gerendert und visuell geprüft |
| Entfernte Befehle, Kalender, Text, Navigation, Anhänge | 157 gezielte Tests bestanden, vor den folgenden Importänderungen |
| Fortschritt, Zielauswahl, Originalexport, Import-/Exportregressionen | 184 bestanden, 3 wegen fehlendem PDFium übersprungen |
| Neue Reihenplatzierung, parallele Scans und PDF-Regressionen | 59 bestanden, dieselben 3 PDFium-Fälle übersprungen |
| Abschließende Spaltenausrichtung und Scan-/Medienplatzierung | 20 bestanden, keine übersprungen |
| Präziser Radierer, Stifttupfer, Knopf/Hover und Ink-Speicherung | 70 gezielte Tests bestanden; Analyse der fünf geänderten Dart-Dateien ohne Befund (20.11.2026, damaliger Stand) |
| PDF-Nachschärfen, Render-Timeout, Speichern und Prozessende | 102 bestanden, 3 bekannte PDFium-Fälle übersprungen; blockierter nativer Worker und freigegebene Dateisperre im Unterprozess geprüft |
| PDF-Import: Speicherpfad und Windows-Lese-Callback | 28 gezielte Tests bestanden, einschließlich 512 nativer Leseaufrufe; Windows-Release am 22.11.2026 gebaut (Dart-Kern). Analyse: nur bestehender Stilhinweis in `command_bar.dart:907`. Betroffene Original-PDF noch am Gerät prüfen |
| Importabstand und leere Textfelder | 28 gezielte Import-/Scanner-/Textfeldtests bestanden: erster Import 44 Pixel unter dem Titelbereich; leere Textfelder beeinflussen die Platzierung nicht. Löschen leerer Felder beim Wegklicken im Canvas bestätigt. Windows-Release gebaut; Analyse nur mit bekanntem Stilhinweis |

Diese Läufe überschneiden sich und dürfen nicht addiert werden. Windows-Release
am 21.11.2026 erfolgreich gebaut (Dart-Kern; ohne Cargo kein OneNote-Import).
Kein neuer APK-/Rust-Build. Ältere Ergebnisse weiter unten gelten für die damaligen
Stände. Kein Push, Release oder manuelles Geräteergebnis daraus ableiten.

Zum Wiederaufnehmen in `app/`: `flutter analyze --no-pub` und nach passender
Änderung die relevanten Tests aus ARCHITECTURE.md ausführen. Für Reihenfolge
und Scan-Rennen insbesondere `pdf_placement_test.dart`, `phone_scanner_test.dart`,
`media_import_layout_test.dart` und `media_arrangement_test.dart`; für Zielauswahl
und Mehrfach-PDFs `original_export_test.dart` und `transfer_progress_test.dart`.
Für reine Dokumentationspflege diese Prüfungen nicht erneut starten.

## Als Nächstes

- „Verschieben nach …“ am Gerät prüfen: Sektion in anderes Buch, Seite samt
  Unterseiten in andere Sektion/Buch; Zielauswahl, Abbrechen, PDFs/Anhänge und
  Passcodes nach dem Wechsel prüfen.

- Kalender am Gerät prüfen: Tag antippen, Aufgabe mit Enter oder Speichern
  erfassen; lange Texte lesen/bearbeiten, optional Seite/Farbe verknüpfen.
  „Alle anzeigen“, Tageszahl nach Erledigen und aktueller Monat neben dem X;
  neue/bearbeitete Entwürfe beim Wechsel zwischen Tagen wiederfinden.
- Einstellungen am Gerät prüfen: Themenwahl, lesbare Beschriftungen und direkt
  bedienbare Schalter. Sektionen/Seiten auch eingeklappt 0,6 Sekunden ruhig halten:
  Kontextmenü statt Tooltip; Bewegen startet weiter das Verschieben. Nach Löschen
  nächste, am Ende vorherige Seite derselben Sektion; leere Sektion bleibt aktiv.
- Neue Bücher- und Backup-Auswahl am Gerät prüfen: lange Namen, viele Bücher,
  Farbauswahl, Tastatur/Touch und Einzel-/Gesamtsicherung mit Zielauswahl.
- Sektionen oben/links und Seiten am Gerät prüfen: direkt mit Maus und Finger
  verschieben, Nachbarn weichen animiert aus; erste Position, Griffpunkt,
  Begrenzung und Randscrollen bei langen Listen prüfen. Gruppenwechsel links
  sowie Seitenwechsel in andere Sektionen mit sichtbaren/verdeckten Unterseiten prüfen.
  Für Unterseiten eine Seite 0,5 Sekunden über einer anderen halten:
  Einrückung als Vorschau, Übernahme beim Loslassen; Wegziehen/Abbruch prüfen.
  Kein schwebendes Drag-Element oder Einfügestrich.
- Windows am Gerät prüfen: Schreiben, Speichern/Neustart, Undo/Redo, Stift- und
  Radierer-Taste, Lasso, Pinch-Zoom und Zweifinger-Lineal.
  Beim verbesserten Radierer schnelle und feine Bewegungen in beiden Modi,
  Textmarker-Ränder und Knopfwechsel während Kontakt/Hover prüfen; außerdem
  kurze Stift-/Kugelschreiber-/Textmarker-Tupfer. Schreibgefühl noch nicht am Gerät bestätigt.
- Start/Update am Gerät prüfen: minimiert schließen, sofort erneut öffnen,
  während Setup manuell starten, automatischen und manuellen Start nach Setup prüfen.
- Automatischen Handballenschutz am Gerät prüfen: Hand vor dem Stift auflegen,
  Ärmel am Scrollbalken, Schreibpausen und bewusstes Wischen/Zoomen bei weiter
  aufliegender Hand. Keine manuelle Touch-Sperre und keine neue Einstellung.
  Windows-Confidence/Kontaktfläche jetzt direkt angebunden; bestätigte Finger
  dürfen auch während eines Stiftstrichs Pan/Pinch ausführen. 69 gezielte
  Eingabe-/Zeichentests und nativer Transporttest bestanden; Gerätewirkung offen.
- PDF-Anzeige am Gerät erneut prüfen: Nachschärfen und Verschieben ohne kurzen
  Bildsprung; Schließen während laufendem/hängendem Rendern und sofortiger Neustart
  ohne verbliebenen Prozess. Ausschnitte wechseln jetzt fertig dekodiert mit ihrer
  Position; nach 30 Sekunden endet die Ladeanzeige mit Retry. Windows beendet den
  Prozess nach Speichern/SQLite-Abschluss direkt. Import, Beschriften und Export
  weiterhin real prüfen; die Geräteprüfung übernimmt der Nutzer.
- QR-Scanner im gemeinsamen WLAN am Ziel-PC prüfen.
- Bild-/PDF-Import am Gerät prüfen: wie Handy-Scans linksbündig mit gleicher
  Breite und 36 Pixel Abstand unter vorhandenen Inhalt stapeln, auch bei
  Auswahl oder aktivem Texteditor; mehrere Dateien und gemischte Formate prüfen.
  Folgeimporte setzen vorhandene horizontale Reihen rechts und vertikale Reihen
  unten fort; auch mehrere gleichzeitig eintreffende Scans und alte PDFs ohne
  gespeicherte Blockhöhe prüfen. Unklare Anordnung hängt unter dem Inhalt an.
- Einheitlichen Import-/Exportfortschritt am Gerät prüfen: Prozent, erledigt,
  verbleibend und Fehler; bei mehreren PDFs zusätzlich Seiten der aktuellen Datei.
  Export fragt immer nach dem Ziel. „Save original“ speichert dieselbe PDF-Quelle
  aus mehreren markierten Blättern einmal, unterschiedliche Quellen getrennt.
- Seitenmenü am Gerät prüfen: Export als seitliches Untermenü per Hover/Klick,
  Ausweichen am Fensterrand und alle Exportformate. Export oben, Favoriten und
  Drucken sind entfernt; „Move up/down“ samt Befehlslogik auch für Gruppen.
  Sektionsmenü enthält Farbpunkte ohne Beschriftung sowie Umbenennen, Gruppenzuordnung,
  Sperren und Löschen. Reihenfolge bleibt manuell; Prüfungsdaten nur im Kalender.
- MCP dauerhaft im gewünschten Desktop-KI-Client konfigurieren; Buchwechsel
  außerhalb der Freigabe und gesperrte Seiten zusätzlich am Gerät prüfen.
- Große Notizbücher und laufende Medien beim Schließen/Backup beobachten.
- Wortlaut des noch nicht identifizierten VS-Code-Auto-Fix-Dialogs aufnehmen;
  Explorer-Farben können Git-Status oder Diagnosen bedeuten.
- Linux-Pakete sind eingebunden; ersten Build und Installationen noch prüfen.

## Offene automatisierte Fälle

Letzter breiter Lauf vor dem Aufräumen: 2324 bestanden, 21 übersprungen,
27 fehlgeschlagen. Datum/Uhrzeit-Löschen und Notebook-Pfadfixture wurden danach
behoben; beide Testdateien bestanden (56 Tests). Die Toolbar-Erwartungen wurden
an die aktuellen Schaltflächen angepasst, ebenso die Einfügen-Tests nach
Entfernung von draw.io. Die damals übrigen Fälle sind teils
veraltete UI-Erwartungen, teils Test-Lifecycle-Probleme, teils noch zu prüfendes
Verhalten. Kein neuer vollständiger Lauf seit diesen Korrekturen; die folgende
Liste ist ein Arbeitsvorrat, keine neu bestätigte Fehlerzählung.
Entfernte Messproben und Funktionen ändern zukünftige Testzahlen.

| Testdatei in `app/test/` | Noch zu prüfen |
|---|---|
| `canvas_interaction_test.dart` | Rotierter Resize-Anker; Timer bei Touch-Swipe, Maus nach Stift-Hover und drei Kontakten (4; auch im unveränderten Vergleichsstand) |
| `draw_tools_test.dart` | Schmale Tab-Leiste läuft über (1) |
| `dialog_controller_lifetime_test.dart` | Notebook anlegen bei aktivem Editor (1) |
| `keyboard_map_test.dart` | Timer beim Verlassen des Editors (1) |
| `localized_shell_test.dart` | Sprachzeile im Dialog; Handschrift-Debounce (2) |
| `math_click_position_test.dart` | Zweiter Klick im offenen Formelblock (1) |
| `marker_chord_test.dart` | Tastaturkürzel statt Marker-Eingabe (1) |
| `school_input_test.dart` | Langdruck auf gesperrtes Objekt; schmale Fensterknöpfe (2) |

## Bereits geprüft

- Eingabewerkzeuge am Gerät prüfen: Stift verwendet das zuletzt gewählte
  Schreibwerkzeug oder den Radierer. Ausdrücklich gewählte Schreibwerkzeuge
  bleiben nach dem Abheben aktiv; nur vorübergehendes Schreiben aus dem
  Auswahlmodus kehrt zur Auswahl zurück. Ein gewähltes Werkzeug zeichnet mit der Maus;
  Fingerzeichnen bei Einstellung „Always“ und Zweifinger-Navigation prüfen.

Live-MCP an der installierten Windows-App: aktuelle Seite mit Aufgabenbildern,
Handschrift und Detailausschnitten gelesen; Seitenwechsel sperrt die vorherige
Seite. Buchmodus listet 18 Seiten portionsweise und liest eine andere Seite,
ohne zu navigieren; lange Notiz mit 40 Bildabschnitten erkannt und nur einen
Abschnitt abgerufen. Unveränderter Text erkannt; Ausschalten beendet den
Server (Verbindung abgewiesen). Keine Notizen geändert.

Windows startet; sichtbare Dart-Änderung und Rücknahme per Hot Reload geprüft.
App-/Scanner-Analyse waren sauber. Gezielte Editor-/PDF-/Cache-/Tastaturtests:
232 bestanden, 3 übersprungen; Abschnittsnavigation zusätzlich bestanden.
Scanner: 3 Tests bestanden. Das ist kein grüner vollständiger Lauf.
Nach der Repository-Bereinigung: 19 Tests für Releaseanzeige, Sidebar und
Scan-Empfang sowie alle 3 Scanner-Tests bestanden; zentrale Markdown-Links gültig.
`flutter analyze --no-pub` für App und Scanner: keine Probleme gefunden.
Rust/Cargo und Android SDK waren lokal nicht installiert. OneNote-Import und
ein lokaler APK-Build brauchen diese Werkzeuge.

## Erledigt

- Notizbuchnamen vereinheitlicht: direkte Importe, OneNote und Backup-Restore
  vergeben eindeutige Namen mit fortlaufenden Nummern; Anzeigename, eigener
  `.onotebook`-Ordner und Containername stimmen überein, auch bei Umlauten.
  Explorer-Umbenennungen werden beim Start/Verwaltungsabgleich anhand der
  Container-ID zugeordnet; alte doppelte Anzeigenamen werden abgeglichen.
  Lose Container werden in eigene Ordner übernommen. 74 gezielte Tests
  bestanden; App-Analyse sauber. Persönliche Notizbücher wurden nicht verändert.
- Drei Speicher-/Wiederherstellungsfehler behoben: passende Medienpfade im
  Backup, konsistente Containerkopien auch für den Papierkorb, Erkennung von
  `.onotebook`-Ordnern ohne Workspace-Datei. Erneuter Abgleich beim Öffnen der
  Notizbuchverwaltung, keine Dauersuche. Alte externe Originale werden portabel
  mitgesichert, ohne die Quelle zu bereinigen; Wiederherstellungen erhalten
  eigene Ordner/Identitäten. 46 gezielte Tests bestanden; Größenbereinigung
  bestehender Notizbücher ist noch nicht implementiert.
- Windows-Fensteraktivierung vereinheitlicht: Start, erneutes Öffnen und
  Wiederanzeigen verwenden Maximieren statt Wiederherstellen/Umschalten.
  Der alte Toggle-Fallback beim Start entfällt; Hintergrund-MCP liest ohne
  Fensteraktivierung. Alle neun Fenstersteuerungstests sowie elf Fokus-/
  Instanztests bestanden; damit sind die beiden alten Fenster-Testfälle erledigt.
  App-Analyse sauber; Windows-Release-Build erfolgreich (lokal ohne Cargo).
- Start/Update abgesichert: Schließen wartet auf keinen neuen Fenster-Frame;
  Sperre bleibt bis Prozessende bestehen. Neustart während des Schließens versucht
  die Sperre erneut, ohne ungesperrten Fallback. Updates warten auf abschließendes
  Speichern und schließen SQLite; Netzwerkwartezeiten sind begrenzt. Windows-Runner
  und Installer koordinieren Starts per Setup-Mutex. App-Analyse sauber,
  57 gezielte Tests bestanden; Windows-Release-Build erfolgreich
  (Dart-Kern, lokal kein Cargo). Vollständiger Setup-Neustart noch am Gerät prüfen.
- Hilfsskripte bereinigt: nachgebauten Handschrift-Diagnosepfad zugunsten der
  Tests am echten Importer entfernt; ungenutztes Video-Auslagerungsskript entfernt
  (Windows-Build bündelt die Bibliotheken). Erreichbarkeit wurde damals geprüft;
  keine historische Dateianzahl als aktuellen Stand übernehmen.
  Video-Lade-/Downloadfunktionen bleiben erhalten.
  App-Analyse sauber; 39 gezielte Import-/Ink-/Video-/Paketierungstests bestanden.
- Lesender MCP-Lernzugriff: aus/aktive Seite/freigegebenes Buch, lokaler
  Token-Zugriff, begrenzte Textantworten, Buchsuche und Seitenbilder mit
  Handschrift/PDF-Anmerkungen und Detailausschnitten. Ungespeicherte Texte aus
  beiden Editorflächen bleiben lesbar; Freigabewechsel und neue Sperren
  widerrufen laufende Bildantworten. 97 gezielte MCP-/Schutz-/Handschrift-/PDF-/
  Navigationstests bestanden, drei bekannte Headless-PDFium-Fälle übersprungen.
  Analyse sauber, Windows-Release-Build erfolgreich (Dart-Kern, lokal kein Cargo).
  GitHub-Releases enthalten denselben Text wie die Updateanzeige.
- Automatischer Windows-Handballenschutz vor der UI-Ereignisverarbeitung:
  Stift hat Vorrang, alte Handkontakte bleiben bis zum Abheben ausgeschlossen;
  frische klare Fingerbewegungen erlauben weiter Wischen und Pinch-Zoom.
  16 neue Tests bestanden; breiter Eingabelauf: 81 bestanden, vier bestehende
  Canvas-Fehler im unveränderten Vergleich bestätigt. Analyse sauber,
  Windows-Release-Build erfolgreich (Dart-Kern, lokal kein Cargo).
- Notebook-Verwaltung: dauerhaftes Suchfeld oben filtert Namen direkt; Leeren und erneutes Öffnen
  setzen die Suche zurück. Beim Öffnen erhält es automatisch den Fokus;
  zusätzliche Dialoge behalten ihren eigenen Eingabefokus.
- Planer: Anlegen nur per Kalendertag, neue Einträge mit reinem Datum ohne
  Uhrzeit; Liste zeigt Titel ohne Metadaten. Navigation prüft Notebook- und
  Seiten-ID und übernimmt die tatsächliche Sektion; Bearbeiten erhält das Ziel.
  Alte datierte und undatierte Einträge bleiben erhalten und bearbeitbar.
  118 gezielte Planer-/Erinnerungs-/Notebook-Dialogtests bestanden;
  `flutter analyze --no-pub` sauber, Windows-Release-Build erfolgreich
  (Dart-Kern, lokal kein Cargo). Geräteprüfung bleibt beim Nutzer.
- Quellcode-Audit: drei nicht kompilierte Seitenleisten-Reste entfernt. Alte
  Notiz-/Medienformate bleiben absichtlich unterstützt. Eine nicht erreichbare
  Fehlerdialog-Datei entfernt; Erreichbarkeit der damaligen Dateien geprüft.
- Bild-/PDF-Drehgriff rastet bei Vierteldrehungen ein (1,5° Nähe, 2° zum Lösen,
  beim Losdrehen aus gerader Position 1°);
  zehn gezielte Drehtests einschließlich Undo bestanden. Am Gerät ausprobieren.
- Windows-Buildblocker durch drei lokale Plugin-Korrekturen beseitigt.
- Abschnittsmenüs umbrechen; Prüfungsuhrzeit wird mit dem Datum entfernt.
- Projekt auf sechs zentrale Dateien konzentriert; historische Berichte,
  Website und reine Messproben entfernt. Wichtige Funktionstests bleiben.
