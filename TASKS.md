# Aufgaben

Stand: 18.10.2026. Nur aktuelle Arbeit und bekannte Grenzen, keine Versionschronik.

## Als Nächstes

- Windows am Gerät prüfen: Schreiben, Speichern/Neustart, Undo/Redo, Stift- und
  Radierer-Taste, Lasso, Pinch-Zoom und Zweifinger-Lineal.
- PDF-Import, Beschriften, wiederholtes Öffnen und Export real prüfen.
- QR-Scanner im gemeinsamen WLAN am Ziel-PC prüfen.
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
| `canvas_interaction_test.dart` | Rotierter Resize-Anker; Timer bei Touch-Swipe und drei Kontakten (3) |
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
| `planner_panel_test.dart` | To-do-/Hausaufgaben-/Prüfungsdialoge und Tagesauswahl (5) |
| `school_input_test.dart` | Langdruck auf gesperrtes Objekt; schmale Fensterknöpfe (2) |
| `windows_window_frame_test.dart` | Custom-Chrome-Mock bei Maximieren und Stift-Hover (2) |

## Bereits geprüft

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

- Notebook-Verwaltung: dauerhaftes Suchfeld oben filtert Namen direkt; Leeren und erneutes Öffnen
  setzen die Suche zurück. Fünf Dialogtests und Analyse bestanden.
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
