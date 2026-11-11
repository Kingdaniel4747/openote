# Architektur

## Programme

`app/` und `scanner/` sind eigenständige Flutter-Pakete mit eigener pubspec
und Lockdatei. Sie bleiben in einem Repository. Die Verbindung läuft über das
Scan-Protokoll, nicht über eine Website oder gemeinsame Laufzeit.

## Windows-App

| Bereich | Einstieg |
|---|---|
| Start, Workspace, Lebenszyklus | `app/lib/main.dart` |
| Oberfläche, Navigation, Menüs | `app/lib/ui/` |
| Dokumentzustand, Speichern, Undo | `app/lib/state/app_state.dart` |
| Seitenfläche, Kamera, Eingaben | `app/lib/canvas/` |
| Text-/Objekteditoren | `app/lib/editor/` |
| Formeln und Graphen | `app/lib/math/` |
| PDF, Video, Import/Export | `app/lib/media/`, `app/lib/export/` |
| Datenmodell und Persistenz | `app/lib/model/`, `app/lib/store/` |
| Handschrift, Planer, Sprache, Theme | `app/lib/ink/`, `planner/`, `l10n/`, `theme/` |

Text wird als Markdown, Mathematik als LaTeX gespeichert. Der eigene Editor
verwaltet Darstellung und Quelltextpositionen; Änderungen dürfen Caret,
Auswahl und Inline-Objekte nicht auseinanderbringen. Farben und Abstände
kommen aus `theme/`, nicht aus neuen parallelen Stilsystemen.

## Speicherung und native Grenze

`Repository` verwaltet `workspace.json`, Notizbücher und Papierkorb.
Neue Notizbücher liegen in `.onotebook`-Ordnern mit `.onote`-SQLite-Container;
zugehörige Medien bleiben bei ihrem Notizbuch. Keine Dateipfade oder Layouts
aus alten Sync-Plänen übernehmen. Maßgeblich sind `store/repository.dart`,
`store/database.dart`, `store/notebook_writer.dart` und `store/media_store.dart`.

`page_mirror` enthält den maßgeblichen Seiteninhalt als JSON
(`onote-page/1`, pageId, Seiteneigenschaften, Blöcke). Unbekannte Blockinhalte
verlustfrei erhalten. Struktur, Blob-/Referenzindizes und Papierkorb konsistent
halten. Komplette Backups verwenden, nicht beliebige offene SQLite-Dateien
kopieren. App-Passcodes sind keine Verschlüsselung der Datei.

`core/engine.dart` kapselt Dart- und Rust-Implementierung. `core/onote_ffi.dart`
bindet den eigenen Rust-Kern per `dart:ffi`/C-ABI ein. Rust liefert unter anderem
Inhaltshashes und `.one`-/`.onepkg`-Import. CMake baut/bündelt ihn bei vorhandenem
Cargo automatisch; sonst greift der Dart-Fallback. Hot Reload ersetzt keine DLL.

## Scanner

`app/lib/api/scanner_receiver.dart` startet einen temporären HTTP-Empfänger.
Der QR-Code enthält Host, Port, zufälliges Token und Zielseite. Der Scanner
sendet Bilder an `/v1/scan` und den Abschluss an `/v1/complete`.
Der Empfänger prüft Token, Größe und Typ; er bietet keinen Notebook-Lesezugriff.
`scanner/lib/main.dart` enthält Kamera, QR-Auswertung und Upload.

## Lesender MCP-Lernzugriff

`app/lib/api/mcp_server.dart` bietet zustandsloses Streamable HTTP unter
`http://127.0.0.1:27191/mcp`: JSON-RPC, Bearer-Token, begrenzte Anfragen,
keine Browser-Origin und keine Bindung ins LAN. Keine neuen Abhängigkeiten.
`learning_access.dart` prüft für jedes Werkzeug den Freigabebereich: aus,
aktive Seite oder das ausgewählte Buch. Buchwechsel erweitern keine Freigabe;
gesperrte Seiten, beliebige Dateipfade und schreibende Werkzeuge sind ausgeschlossen.
Freigaben leben nur in der Sitzung, Port und Token lokal in `learningMcp`.

Werkzeuge: `get_context`, `list_pages`, `search_pages`, `read_page` und
`read_page_image`. Textantworten haben Fortsetzungen und Inhaltsrevisionen;
Bildantworten sind auf 1600 Pixel standardmäßig, höchstens 2400 Pixel begrenzt.
Seitenbilder und Detailausschnitte verwenden eingefrorene Eingaben der bestehenden
Vektor-PDF-Ausgabe, einschließlich ungespeicherter Texte aus beiden Editorflächen.
Asynchrone Bildantworten prüfen die Freigabe vor der Rückgabe erneut. Der Bildcache
ist auf sechs Einträge/12 MiB begrenzt. Handschrift bleibt Bildinhalt, keine OCR.
PDF-Quellen werden nicht als vollständiges mehrseitiges Dokument herausgegeben.

## Build und Abhängigkeiten

Windows-Runner: `app/windows/`; Linux-Runner: `app/linux/`.
Lokale Plugin-Fixes liegen unter `app/third_party/` und sind über
`dependency_overrides` eingebunden. Provenienz, Lizenzen und Patchnotizen bleiben
beim jeweiligen Fremdcode. Beide Apps beziehen Releaseinformationen direkt von
GitHub; die Website ist dafür unnötig. Der Workflow baut beide Pakete mit einer
gemeinsamen Releaseversion.
