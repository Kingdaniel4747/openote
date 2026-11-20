# Aufgaben

Stand: 20.11.2026. Nur aktuelle Arbeit und bekannte Grenzen, keine Versionschronik.

## Übergabe für den nächsten Chat

Bedienregeln und entfernte Funktionen stehen in PRODUCT.md, Code-Einstiegspunkte
und Datenflüsse in ARCHITECTURE.md. Die letzten Änderungen umfassen Navigation,
Kontextmenüs/Codebereinigung, Import-/Exportfortschritt, Original-Deduplizierung
und das Fortsetzen vorhandener Medienreihen. Nächster sinnvoller Schritt ist
die Geräteprüfung unten; bestehende Funktionen nicht wieder ergänzen, nur weil
alte Tests oder Kommentare sie erwähnen. Vor Änderungen den lokalen Diff lesen.

Aktueller automatisierter Stand, keine grüne Gesamtsuite:

| Bereich | Letzte Prüfung |
|---|---|
| App, kompletter Dart-Quellbaum | Gesamtlauf beim Notebook-Umbau: keine Fehler; bestehender Stilhinweis in `command_bar.dart:907`, außerhalb der Notebook-Änderung |
| Notebook-Auswahl und Backup-Dialog | 17 gezielte UI-/Backup-/Lifecycle-Tests bestanden; Analyse der fünf betroffenen Dart-Dateien sauber. Helle/dunkle Ansichten gerendert und visuell geprüft |
| Entfernte Befehle, Kalender, Text, Navigation, Anhänge | 157 gezielte Tests bestanden, vor den folgenden Importänderungen |
| Fortschritt, Zielauswahl, Originalexport, Import-/Exportregressionen | 184 bestanden, 3 wegen fehlendem PDFium übersprungen |
| Neue Reihenplatzierung, parallele Scans und PDF-Regressionen | 59 bestanden, dieselben 3 PDFium-Fälle übersprungen |
| Abschließende Spaltenausrichtung und Scan-/Medienplatzierung | 20 bestanden, keine übersprungen |
| Präziser Radierer, Stifttupfer, Knopf/Hover und Ink-Speicherung | 70 gezielte Tests bestanden; Analyse der fünf geänderten Dart-Dateien ohne Befund (20.11.2026, damaliger Stand) |

Diese Läufe überschneiden sich und dürfen nicht addiert werden. Ein neuer
Windows-/APK-/Rust-Build wurde für diesen letzten UI-/Importstand nicht
ausgeführt; ältere Build-Ergebnisse weiter unten gelten für die damaligen
Stände. Kein Push, Release oder manuelles Geräteergebnis daraus ableiten.

Zum Wiederaufnehmen in `app/`: `flutter analyze --no-pub` und nach passender
Änderung die relevanten Tests aus ARCHITECTURE.md ausführen. Für Reihenfolge
und Scan-Rennen insbesondere `pdf_placement_test.dart`, `phone_scanner_test.dart`,
`media_import_layout_test.dart` und `media_arrangement_test.dart`; für Zielauswahl
und Mehrfach-PDFs `original_export_test.dart` und `transfer_progress_test.dart`.
Für reine Dokumentationspflege diese Prüfungen nicht erneut starten.

## Als Nächstes

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
- PDF-Anzeige nach Zoom-/Cache-Korrektur vom Nutzer als verbessert bestätigt.
  Noch prüfen: während des PDF-Nachladens schließen; danach darf kein
  Openote-Prozess im Task-Manager verbleiben. Import, Beschriften und Export
  weiterhin real prüfen. Gezielte PDF-Prüfung: 62 bestanden, 3 wegen fehlendem
  PDFium übersprungen; statische Analyse der geänderten Dateien ohne Befund.
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
- Linux und getrennte Windows-/Scanner-Releases später behandeln.

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
  Schreibwerkzeug oder den Radierer; nach dem Abheben wählt und verschiebt
  die Maus wieder. Ein ausdrücklich gewähltes Werkzeug zeichnet mit der Maus;
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
  Der manuell startbare GitHub-Release-Workflow bleibt unverändert.
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
