# Architektur

## Programme

`website/` ist eine buildfreie englische GitHub-Pages-Website; die alte Adresse
`en/` leitet auf die Wurzel um. Gemeinsame CSS-Datei und progressive Downloadlinks
über `downloads.js`. Ohne GitHub-API/JavaScript bleiben die Release-Seiten verlinkt.
`.github/workflows/pages.yml` veröffentlicht unabhängig von den App-Builds.
`features.html` listet die Werkzeuge und erklärt ihre Bedienung; beide Seiten
verlinken sie über die auch mobil sichtbare Navigation „Features & guide“.
`release.yml` baut nach Push auf `master` beide Apps; `release-notes.mjs` erstellt
aus dem markierten TASKS-Abschnitt, vorherigem Release-Stand und Git-Commits den
Release-Text. Keine neue separate Markdown-Chronik.

Echte öffentliche UI-Bilder unter `website/assets/screenshots/` entstehen aus
`app/test/publication_screenshots_test.dart` und dem gleichnamigen Scanner-Test:
opt-in `OPENOTE_PUBLICATION_SHOTS=1`, gesetztes `FLUTTER_ROOT`, `--update-goldens`.
Nur temporäre Beispieldaten, keine persönlichen Bücher oder aktiven QR-Tokens.

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

Handschrift: `canvas/page_canvas.dart` erfasst Stiftbewegungen und erhält kurze
Tupfer als Punkte für Stift, Kugelschreiber und Textmarker. `canvas/ink_eraser.dart`
schneidet Striche gegen die gesamte vom runden Radierer überstrichene Fläche;
Schnittpunkte interpolieren Druck, Neigung und Zeit. Unveränderte Striche bleiben
im Cache, Undo/Redo und Speichern werden weiter am Gestenende abgeschlossen.
`canvas/ink_painter.dart` erkennt auch Änderungen in der Mitte der Strichliste.
Die bestehende Knopf-/Hover-Auswertung in `canvas/windows_pen_buttons.dart`
und im Windows-Runner bleibt davon unabhängig und wurde nicht geändert.
Referenz für Schnittintervalle und Stabilisierung: [Xournal++](https://github.com/xournalpp/xournalpp/tree/master/src/core/control/tools).
Tests: `ink_eraser_test.dart`, `windows_pen_buttons_test.dart`,
`drawing_regressions_test.dart`, `ink_storage_test.dart` und `ink_codec_test.dart`.

Handschrift-Beta: `ui/handwriting_dialog.dart` erfasst Zeichen auf einem festen
Schreibfeld mit Grundlinie; Stift/Maus schreiben, Touch scrollt den Dialog.
Die Einrichtung führt durch alle 84 Zeichen mit festem Bestätigen-Knopf und
automatischem Weiterschalten. Der nächste Schritt wird aus den gespeicherten
Vorlagen abgeleitet; kein separater Freigabeschalter. `HandwritingProfile.isComplete`
sperrt auch die Erzeugung selbst, solange Pflichtzeichen fehlen. Nach Abschluss
öffnet sich die Umwandlung; Variantenbearbeitung bleibt separat erreichbar.
`ui/handwriting_pad.dart` kapselt Entwurf, Strich-/Radierer-Undo und die gemeinsame
Darstellung für Schreibfeld, Zeichenübersicht und Variantenauswahl. Die blasse
Inter-Vorlage sitzt auf der festen Grundlinie und wird nie als Strich gespeichert.
Die Stifttaste nutzt `WindowsPenButtons`, Radieren den vorhandenen `eraseStroke`.
Das sichtbare Schreibfeld ist 160 Pixel breit; das gespeicherte 220×160-System
und `letterHeight` bleiben unverändert. Die proportional kleinere Vorlage und
Pointer-Abbildung ändern damit weder vorhandene Proben noch die Ausgabegröße.
Der bestätigte Profil-Reset leert `handwritingProfileBeta` sowie den Dialogentwurf,
setzt Einrichtung/Undo zurück und ändert keine Ink-Blöcke auf Notizseiten.
Die Bestätigungsknöpfe sind ebenfalls gezielte Touch-Ziele während Stift-Hover.
Speichern ersetzt nur die ausgewählte Variante; maximal fünf ohne Verdrängen.
Der Editor bleibt beim Speichern geöffnet und wählt die gespeicherte Variante;
„Gespeichert“ verhindert doppeltes Anhängen desselben Entwurfs. Beim Wechsel oder
Zurückgehen werden leere gespeicherte Varianten entfernt; Zielindizes werden
entsprechend angepasst. Leere neue Entwürfe bleiben ungespeichert, genau eine
Neue-Variante-Kachel bleibt bis zur Fünfergrenze verfügbar. Die Werkzeugleiste und
Einzellöschung sind durch einen mittigen Entwurf-Reset ersetzt; Cursor ist im
Schreibfeld unsichtbar, Radieren bleibt über die Stifttaste erreichbar.
`WritingTouchGuard.registerControlTarget` erlaubt frische kleine Fingerkontakte
nach Pen-up nur an den sichtbaren Dialogkontrollen, nicht auf dem Schreibfeld;
Registrierungen enden beim Dialogabbau. Aktive Stiftkontakte und alte Handkontakte
haben weiter Vorrang. Generator, Abstände und existierende Vorlagen bleiben erhalten.
`ink/handwriting_profile.dart` speichert Zeichenvarianten als Strichpfade und
setzt Text mit Umbruch in seitenabsolute `Stroke`s um. Das lokale Profil liegt
im Workspace-Setting `handwritingProfileBeta`, unabhängig von Notizbuchinhalten.
Die Erzeugung berücksichtigt die Breite fester Papierseiten. `AppState.insertHandwriting`
fügt gewöhnliche Ink-Blöcke ein; Radierer, Lasso und Speicherformat bleiben gemeinsam.
Lasso-Formatierung ändert `brush.color`/`brush.size`, invalidiert gespeicherte
Ink-Referenzen und erhöht die Cache-Revision auch bei schnellen Folgeänderungen.
Tests: `handwriting_profile_test.dart`, `handwriting_beta_test.dart`,
`handwriting_pad_test.dart` und `writing_touch_guard_test.dart`.

## Navigation und Kontextmenüs

`ui/inline_section_strip.dart` enthält die gemeinsame direkte Verschiebelogik
für obere Sektionstabs und vertikale Sektions-/Seitenlisten. Sie hält den
Griffpunkt, animiert Nachbarn, begrenzt die Bewegung und scrollt am Rand.
Die 500-ms-Unterseitenvorschau wird erst beim Loslassen übernommen.
`ui/sidebar.dart` und `ui/app_shell.dart` binden sie ein; `AppState` speichert
Reihenfolge und Seitenbäume über `reorderNode`, `reorderPageTree` und
`makeSubpageOf`. Der frühere `moveNode(id, delta)`-Befehl ist entfernt.

`ui/node_context_menu.dart` stellt das Kontextmenü bereit;
`NavigatorHoldMenu` vereinheitlicht den 600-ms-Langdruck in direkten Listen,
Sektionstabs und der eingeklappten Leiste. Deren Tooltips beanspruchen keine
Haltegeste mehr; Maus-Hover bleibt verfügbar.
`ui/page_export_menu.dart` definiert Formatauswahl und Export der angeklickten
Seite. `ui/insert_catalog.dart` ist der gemeinsame Einfügen-Katalog für Ribbon
und Canvas-Menü. Kalenderdaten bleiben in `state/study_state.dart`,
`state/planner_state.dart` und `planner/`; `StudyState` enthält nur noch
Prüfungsdaten/-zeiten, keine Lernkartenplanung.

Der Planer öffnet `ui/planner_entry_editor.dart` direkt unter dem Monatsraster.
`PlannerPanel` hält Entwürfe je Tag/Eintrag und die feste Tages- und Aktionsleiste.
`Reminder.color` ist ein optionaler Farbschlüssel in den bestehenden Settings;
`MonthGrid` und Listen verwenden denselben Akzent. Neue Einträge sind ganztägig,
Bearbeiten erhält alte Uhrzeiten und Notebook-/Seiten-IDs. Das Monatsraster selbst
bleibt erhalten; der aktuelle-Monat-Knopf setzt seine Widget-Identität zurück.

## Medienimport und Dateiexport

| Aufgabe | Einstieg |
|---|---|
| Fortschrittsmodell, Anzeige und Dialog-Lebensdauer | `ui/transfer_progress.dart`: `TransferProgress`, `TransferMeter`, `runTransfer` |
| Dateiauswahl für Bilder, Dateien, Tabellen und PDFs | `ui/insert_catalog.dart` |
| PDF-Quelle, Vorschauen und Platzierungsmodi | `export/pdf_import.dart` |
| QR-Dateien auf der gekoppelten Zielseite | `api/scanner_import.dart`, `ui/scanner_pairing_dialog.dart` |
| Drop und Clipboard | `canvas/media_drop.dart`, `canvas/page_canvas.dart`, `ui/app_shell.dart` |
| Originalquellen zusammenfassen und Namen reservieren | `core/original_download.dart` |
| Originale speichern, auch Anhänge/Videos | `ui/selection_toolbar.dart`; Datei-/Videokarten delegieren dorthin |
| Markdown, PDF und offene Formate | `export/markdown_export.dart`, `pdf_vector_export.dart`, `pdf_export.dart`, `open_export.dart` |
| Notizbuch-/Backup-Import und Export | `ui/notebook_manager.dart`, `state/app_state.dart` |

`AppState.mediaImportPlacement` ist die gemeinsame Platzierung für ausgewählte
Bilder, PDF-Ausdrucke und Handy-Dateien. Sie verwendet tatsächliche sichtbare
Blockgrenzen einschließlich Rotation; ohne gespeicherte/gemessene Bildhöhe
werden `naturalW`/`naturalH`, sonst ein Bild-Seitenverhältnis als Fallback benutzt.
Off-screen-Importe verwenden die Daten der gekoppelten Seite, keine Messwerte
der aktuell sichtbaren Seite. Erkennbare horizontale Reihen wachsen rechts;
sonst wächst der Inhalt unten. Feste Papier-/PDF-Seiten behalten ihre Grenzen.
PDF-Ausdrucke berechnen die Position für jedes neu veröffentlichte Blatt erneut.
Der erste Import beginnt 44 Pixel unter dem Titelbereich, passend zum linken
Rand. Leere Textcontainer zählen für die Platzierung nicht als Inhalt;
zwischen vorhandenen Inhalten und Folgeblättern bleiben 36 Pixel Abstand.

`AppState.runMediaImport` serialisiert PDF- und Handy-Importe einschließlich
Lesen, Dekodieren und Speichern. Das verhindert sowohl überlagerte Positionen
als auch das Überschreiben von Off-screen-Seiten durch veraltete Kopien.
Nach einem Fehler kann der nächste Import fortfahren. PDF-only und eine
Openote-Seite je PDF-Blatt bleiben eigene Platzierungsmodi.

Ein PDF-Blatt ist ein Bildblock mit `content['pdf']` als vollständiger
Originalquelle und optionalem `blob` als Seitenvorschau. `uniqueOriginals`
dedupliziert zuerst nach der Originalreferenz, nicht nach Vorschau oder
Blattnummer; normale Blob-Anhänge derselben Quelle zählen ebenfalls nur einmal.
Medien-/Pfadreferenzen bilden eigene Schlüssel. Zielauswahl erfolgt vor dem
Schreiben; nie automatisch in Downloads. Originale werden temporär im
Zielordner geschrieben und erst danach auf den gewählten Dateinamen umbenannt.
Mehrere Originale bekommen kollisionsfrei reservierte `OpenNote N.<ext>`-Namen.

`TransferProgress` trennt abgeschlossene Einträge, Teilfortschritt und Fehler.
`runTransfer` besitzt seine eigene Dialogroute; Bereinigung darf keinen fremden
Dialog schließen. Videoimport behält echten Abbruch, OneNote-Paketimport seine
Hintergrundkarte; beide verwenden dieselbe Fortschrittsanzeige. Eintragszähler
können je Operation Dateien, Seiten oder Schritte zählen; unbekannte Gesamten
werden nicht als erfundene Prozentzahl angezeigt.

Gezielte Regressionen liegen insbesondere in `original_export_test.dart`,
`transfer_progress_test.dart`, `pdf_placement_test.dart`, `phone_scanner_test.dart`,
`media_import_layout_test.dart`, `media_arrangement_test.dart`,
`file_block_view_test.dart`, `page_context_menu_test.dart`,
`sidebar_page_reorder_test.dart`, `sidebar_section_reorder_test.dart` und
`section_tabs_navigation_test.dart` unter `app/test/`.

## Speicherung und native Grenze

`Repository` verwaltet `workspace.json`, Notizbücher und Papierkorb.
Neue Notizbücher liegen in `.onotebook`-Ordnern mit `.onote`-SQLite-Container;
zugehörige Medien bleiben bei ihrem Notizbuch. Keine Dateipfade oder Layouts
aus alten Sync-Plänen übernehmen. Maßgeblich sind `store/repository.dart`,
`store/database.dart`, `store/notebook_writer.dart` und `store/media_store.dart`.

Die Workspace-Liste wird bei Verlust aus Containern und `.onotebook`-Ordnern
einschließlich `Recycle Bin` rekonstruiert. Beim Start und beim Öffnen der
Notizbuchverwaltung erfolgt ein zusammengefasster, flacher Abgleich ohne
Medien-Decodierung. Gelöschte Bücher bleiben im Papierkorb; bei unbekanntem
Löschdatum beginnt eine neue Aufbewahrungsfrist. Container speichern ihre
Notizbuch-ID auch selbst; wiederhergestellte Kopien bekommen eigene Identitäten.
Backups enthalten konsistente Containerkopien einschließlich Papierkorb sowie
passend referenzierte Medien und alte externe Blobs. Restore legt eigene
`.onotebook`-Ordner an. Diese Sicherung ist keine Größenbereinigung: alte
Originaldateien werden erhalten und nicht ungeprüft gelöscht.

Importe verwenden eine gemeinsame Namensvergabe (`Informatik`, `Informatik 2`,
`Informatik 3`); Papierkorb und vorhandene Ordner zählen bei Kollisionen mit.
Anzeigename, Ordner und Container werden gemeinsam benannt. Beim Abgleich werden
Explorer-Umbenennungen anhand der internen ID dem bestehenden Buch zugeordnet,
anstatt ein zweites Buch anzulegen. Der geänderte Ordner- oder Dateiname wird
auf die übrigen Namen übertragen; lose Container erhalten einen eigenen Ordner.

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

PDF-Anzeige (`media/pdf_pages.dart`, `editor/image_block_view.dart`): Original-PDF
und dauerhafte Seitenvorschau bleiben erhalten. Die Bilddekodierung folgt Zoom
und Display-Pixeldichte; für höhere PDF-Auflösung werden sichtbare Ausschnitte
mit Rand nachgeladen und ausschließlich im Arbeitsspeicher gecacht. Überholte
Aufträge werden vor dem Öffnen/Rendern verworfen. Ausschnitte werden vor dem
Wechsel dekodiert; Pixel und Ausschnittsposition wechseln im selben Frame.
Anzeigeaufträge enden nach spätestens 30 Sekunden mit erneuter Versuchsmöglichkeit;
verspätete Ergebnisse werden verworfen. Ein zuletzt genutztes großes
PDF darf das Dokumentcache-Budget überschreiten; Inaktivität gibt es wieder frei.
Der Import bereitet weiterhin alle Seitenvorschauen vor dem Abschluss vor;
eine schrittweise Veröffentlichung während des Imports ist nicht umgesetzt.

Start/Ende: Pro Workspace hält `core/single_instance.dart` eine Dateisperre;
beim Schließen werden keine neuen Öffnungsanfragen bestätigt. Ein Neustart
versucht nach ausbleibender Antwort die Sperre erneut, öffnet aber nie ungesperrt.
Schließen wartet auf Speichern, nicht auf einen weiteren Fenster-Frame.
Neue PDF-Aufträge werden beim Schließen gesperrt und laufende abgebrochen.
Nach erfolgreichem Speichern und SQLite-Abschluss beendet `core/process_exit.dart`
den Windows-Prozess direkt, auch bei einem blockierten nativen PDF-Worker.
Updates speichern den letzten Zustand und schließen SQLite vor Prozessende.
Während Setup läuft, verwirft der Windows-Runner manuelle Starts; Setup startet
die fertige Installation mit `--after-update`. Der Setup-Mutex ist an den
Installer-Prozess gebunden, keine dauerhafte Startsperre auf der Festplatte.
Automatisches Anzeigen verwendet unter Windows `runner/window_state.h`:
Start, erneutes Öffnen, Wiederanzeigen nach Bildschirmaufnahme und Fehlerwiederkehr
zeigen maximiert mit Taskleiste. Größenumschaltung nur auf ausdrückliche
Bedienung (Fensterknopf/F11); MCP-Lesezugriffe ändern den Fensterzustand nicht.

Windows-Runner: `app/windows/`; Linux-Runner: `app/linux/`.
Lokale Plugin-Fixes liegen unter `app/third_party/` und sind über
`dependency_overrides` eingebunden. Provenienz, Lizenzen und Patchnotizen bleiben
beim jeweiligen Fremdcode. Beide Apps beziehen Releaseinformationen direkt von
GitHub; die Website ist dafür unnötig. Der Workflow baut beide Pakete mit einer
gemeinsamen Releaseversion.
