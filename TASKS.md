# Aufgaben

Stand: 11.11.2026. Nur aktuelle Arbeit und bekannte Grenzen, keine Versionschronik.

## Als Nächstes

- Windows am Gerät prüfen: Schreiben, Speichern/Neustart, Undo/Redo, Stift- und
  Radierer-Taste, Lasso, Pinch-Zoom und Zweifinger-Lineal.
- Automatischen Handballenschutz am Gerät prüfen: Hand vor dem Stift auflegen,
  Ärmel am Scrollbalken, Schreibpausen und bewusstes Wischen/Zoomen bei weiter
  aufliegender Hand. Keine manuelle Touch-Sperre und keine neue Einstellung.
- PDF-Import, Beschriften, wiederholtes Öffnen und Export real prüfen.
- QR-Scanner im gemeinsamen WLAN am Ziel-PC prüfen.
- MCP dauerhaft im gewünschten Desktop-KI-Client konfigurieren; Buchwechsel
  außerhalb der Freigabe und gesperrte Seiten zusätzlich am Gerät prüfen.
- Große Notizbücher und laufende Medien beim Schließen/Backup beobachten.
- Wortlaut des noch nicht identifizierten VS-Code-Auto-Fix-Dialogs aufnehmen;
  Explorer-Farben können Git-Status oder Diagnosen bedeuten.
- Linux und getrennte Windows-/Scanner-Releases später behandeln.

## Offene automatisierte Fälle

Letzter breiter Lauf vor dem Aufräumen: 2324 bestanden, 21 übersprungen,
27 fehlgeschlagen. Datum/Uhrzeit-Löschen und Notebook-Pfadfixture wurden danach
behoben; beide Testdateien bestanden (56 Tests). Die übrigen 25 Fälle sind teils
veraltete UI-Erwartungen, teils Test-Lifecycle-Probleme, teils noch zu prüfendes
Verhalten. Entfernte Messproben ändern zukünftige Testzahlen.

| Testdatei in `app/test/` | Noch zu prüfen |
|---|---|
| `canvas_interaction_test.dart` | Rotierter Resize-Anker; Timer bei Touch-Swipe, Maus nach Stift-Hover und drei Kontakten (4; auch im unveränderten Vergleichsstand) |
| `command_bar_compact_test.dart` | Heutiges Planersymbol/-Badge statt alter Erwartung (2) |
| `drawing_regressions_test.dart` | Lineal bewegen/strecken ohne Kamerabewegung (1) |
| `draw_tools_test.dart` | Schmale Tab-Leiste läuft über (1) |
| `dialog_controller_lifetime_test.dart` | Notebook anlegen bei aktivem Editor (1) |
| `insert_catalog_test.dart` | Entfernte Flashcard/Template-Einträge und Kompaktbreite (2) |
| `keyboard_map_test.dart` | Timer beim Verlassen des Editors (1) |
| `localized_shell_test.dart` | Sprachzeile im Dialog; Handschrift-Debounce (2) |
| `math_click_position_test.dart` | Zweiter Klick im offenen Formelblock (1) |
| `marker_chord_test.dart` | Tastaturkürzel statt Marker-Eingabe (1) |
| `notebook_menu_test.dart` | Heutige Notebook-Verwaltung statt alter Erwartung (1) |
| `school_input_test.dart` | Langdruck auf gesperrtes Objekt; schmale Fensterknöpfe (2) |
| `windows_window_frame_test.dart` | Custom-Chrome-Mock bei Maximieren und Stift-Hover (2) |

## Bereits geprüft

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
  Fehlerdialog-Datei entfernt; alle 148 Dart-Dateien sind vom App-Einstieg aus
  erreichbar.
- Bild-/PDF-Drehgriff rastet bei Vierteldrehungen ein (1,5° Nähe, 2° zum Lösen,
  beim Losdrehen aus gerader Position 1°);
  zehn gezielte Drehtests einschließlich Undo bestanden. Am Gerät ausprobieren.
- Windows-Buildblocker durch drei lokale Plugin-Korrekturen beseitigt.
- Abschnittsmenüs umbrechen; Prüfungsuhrzeit wird mit dem Datum entfernt.
- Projekt auf sechs zentrale Dateien konzentriert; historische Berichte,
  Website und reine Messproben entfernt. Wichtige Funktionstests bleiben.
