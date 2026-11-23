# Erkenntnisse

Nur Erkenntnisse behalten, die künftige Fehler verhindern. Keine Sitzungsprotokolle.

## Windows-Build

- Funktionierende Kombination: Flutter 3.47.7 / Dart 3.13.5, Visual Studio
  Community 2026 Insiders, CMake 4.3.1. Spätere Insiders-Versionen sind damit
  nicht automatisch geprüft.
- `media_kit_libs_windows_video` 1.0.12: ANGLE-Entpacken ohne 7-Zip brauchte
  `POST_BUILD`; CMP0175 für ältere CMake-Versionen abfragen. Funktionierenden
  MPV-Download und Prüfsumme erhalten.
- `pdfrx_engine` 0.3.9: Im asynchronen Range-Reader eine feste, nicht-nullbare
  Cache-Referenz verwenden. Ein pauschales PDF-Update würde auch PDFium und
  dessen Paketierung ändern. Ressourcen erst nach asynchronem Öffnen freigeben;
  Rückgaben in try/catch/finally entsprechend abwarten.
- Cargokit: `Get-Item -LiteralPath ... -Force -ErrorAction Stop` verarbeitet
  versteckte Pfadteile und eckige Klammern. AppData-Fehler nicht pauschal der
  Sandbox zuschreiben. Test: `app/tool/test_windows_symlink_resolver.ps1`.
- Diese Fixes sind lokale Paketkopien. Keine Flutter-Installation oder globale
  Paketquelle patchen. Bei Paketwechseln die jeweilige OPENOTE.md beachten.
- Flutter-Befehle im richtigen Paketordner ausführen. Neuere Paketversionen
  und beabsichtigte Overrides sind keine Buildfehler.

## Daten und Bedienung

- Planer-Tagesansicht nicht zusätzlich mit dem Hinweisbanner für fällige
  Erinnerungen belegen: Banner + Monatsraster können die Eingabe auf null Höhe
  verdrängen. Tagesnavigation und Speichern bleiben außerhalb der scrollenden Liste.
- Tooltips auf Navigationseinträgen beanspruchen standardmäßig Langdruck und
  können das Kontextmenü verhindern. Dort `TooltipTriggerMode.manual` verwenden:
  Maus-Hover bleibt erhalten, die Haltegeste gehört dem gemeinsamen Menü-Recognizer.
- PDF-Bytes im Speicher direkt über PDFiums Speicherpfad öffnen: der bisherige
  1-MiB-Schwellwert leitete größere Importe unnötig durch native Lese-Callbacks.
  Bei Windows-Condition-Variables müssen Leser und Schreiber denselben Lock
  sowie ein Zustandsprädikat verwenden; sonst gehen frühe Signale verloren.
  Regression: `pdf_memory_loading_test.dart`, einschließlich echtem Worker.

- PDF-Blätter referenzieren ein gemeinsames Original: beim Export nach
  `content['pdf']` deduplizieren, niemals nach Vorschaubild oder Blattnummer.
  Ein Originalexport muss einen Ziel-Dialog anbieten; Downloads ist kein
  stillschweigender Ersatz für eine Nutzerauswahl.
- Medienplatzierung über sichtbare Grenzen berechnen: natürliche Bildmaße,
  gespeicherte/gemessene Höhe und Rotation berücksichtigen. 60 Pixel als
  generische Bildhöhe lassen Folgeimporte hinter bestehenden PDFs landen.
  Ausrichtung aus der vorhandenen Reihe ableiten, nicht aus Auswahl oder Caret.
- Gleichzeitige Scan-/PDF-Importe vor dem Lesen der Zielseite serialisieren.
  Nur die Schreiboperation zu serialisieren genügt nicht: zwei zuvor gelesene
  Off-screen-Kopien können sich gegenseitig überschreiben. Nach jedem neuen
  PDF-Blatt die nächste Position erneut aus dem aktuellen Inhalt ermitteln.
- Fortschrittsdialoge über ihre eigene Route schließen. Notifier erst nach
  `route.completed` freigeben; das Ende des Arbeits-Futures bedeutet noch
  nicht, dass alle Dialogwidgets abgebaut sind. Abgeschlossene statische
  Future-Warteschlangen freigeben, damit Widgettests nicht an alten Fake-Uhren
  hängen bleiben. Fehler dürfen nachfolgende Queue-Einträge nicht blockieren.
- Entfernte Funktionen einschließlich Befehlen, Hilfsmethoden, Abhängigkeiten
  und Kürzeln prüfen. Kompatibilitätsdarstellung alter Notizen ist weiterhin
  gebraucht und darf nicht als toter Code entfernt werden.

- Radierer gegen die gesamte Bewegung zwischen zwei Stiftpositionen schneiden,
  nicht nur gegen einzelne Abtastkreise. Schnittpunkte samt Druck/Neigung/Zeit
  interpolieren; beim Neuzeichnen auch geänderte Striche in der Listenmitte prüfen.
- Windows-Handballenschutz muss vor dem Hit-Test greifen, nicht nur im Canvas:
  sonst reagieren Scrollbalken und Fensterknöpfe bereits auf den Kontakt.
  Bei Stiftkontakt alte Touch-Sequenzen abbrechen und bis zum Abheben verwerfen.
  Frische, bestätigte Fingergesten separat weiterreichen, auch bei Stift-Hover;
  aufliegende Handkontakte dürfen nicht als zusätzliche Pinch-Finger zählen.
- Planer-Seiten-IDs gehören zu einem Notebook: vor `selectPage` das Ziel dort
  prüfen und gegebenenfalls das Notebook wechseln. Die Sektion aus der Seite
  ableiten; beim Bearbeiten niemals die Ziel-Notebook-ID durch die aktuelle ersetzen.
  Neue ganztägige Erinnerungen speichern `allDay: true` und `at: yyyy-MM-dd`;
  alte Zeitstempel ohne Migration erhalten.
- Windows-Stifttaste: Hover-Nähe, Spitzenkontakt und Seitentaste getrennt
  auswerten. Flutter kann `invertedStylus` bis zum Verlassen der Nähe behalten;
  das darf ein aktuelles natives Loslassen nicht überstimmen. Physische Taste
  über `GetRawPointerDeviceData` lesen, `PEN_FLAG_BARREL` als Fallback; keine
  Radierer-Typkennung als gehaltene Taste speichern. Native Zustandsfolgen:
  `app/test/native/pen_button_state_test.cpp` mit MSVC `/std:c++20 /Zs` prüfen.
- Beim Einrasten von Drehgesten den freien Zeigerwinkel getrennt vom angezeigten
  Winkel weiterführen, damit auch langsames Weiterdrehen die Rastung lösen kann.
- Rust-FFI braucht `panic = "unwind"` für `catch_unwind`; `opt-level = 3`
  erhält die Importgeschwindigkeit. Sortierte JSON-Schlüssel für stabile Hashes
  erhalten (`serde_json` nicht auf `preserve_order` umstellen).
- Den lokalen `cab`-Patch für effizientes Entpacken von `.onepkg` erhalten;
  Details stehen direkt in `rust/onote_core/vendor/cab/OPENOTE-PATCH.md`.
- Speicherungen vor dem Schließen abwarten; fehlgeschlagene Saves nicht als
  Erfolg anzeigen. `exit(0)` umgeht den Widget-Abbau: nach erfolgreichen Saves
  App/Repository ausdrücklich schließen, damit SQLite den WAL-Checkpoint
  ausführt. Autosave: 1 s Schreibpause, spätestens nach 5 s Änderungen;
  gleichzeitig angeforderte Speicherungen nacheinander ausführen.
  Bei Formatänderungen alte Dateien erhalten.
- SQLite-DLLs in Tests aus einer Kopie laden, damit Windows den nächsten
  App-Build nicht durch gesperrte Runner-Dateien blockiert.
- Lange Menütexte innerhalb der Zeile begrenzen/umbrechen lassen.
- Nach `await` die Lebensdauer des verwendeten Dialog-Kontexts prüfen.
- Beim Löschen von Prüfungsdatum und Uhrzeit beide Maps unabhängig verändern;
  `remove(date) || remove(time)` überspringt die zweite Operation.
- Erfolgreicher Hot Reload und saubere Analyse beweisen keine grüne Gesamtsuite.
  Alte Erwartungen mit dem heutigen Produkt abgleichen.

## Prüfungen

Release-Shells laufen mit `bash -e`: `((patch++))` liefert beim alten Wert 0
einen Fehlerstatus und beendet den Schritt. Versionen mit `patch=$((patch + 1))`
erhöhen; Nullwerte und Versionsüberläufe in `.github/scripts/version.test.mjs`
gegen den tatsächlichen Workflow prüfen.

PDF-Anzeige: Decode-Größe an Zoom und Display-Pixeldichte anpassen, auch unter
100 % Zoom. Scharfe sichtbare Ausschnitte nur transient halten; niemals als
dauerhafte Vorschau speichern. Veraltete Aufträge vor dem Öffnen überspringen,
bei geteilten Aufträgen alle noch aktiven Betrachter berücksichtigen. Einen
zuletzt verwendeten großen PDF-Quellcontainer trotz Cache-Budget behalten,
sonst wird derselbe Inhalt für jede Seite erneut geöffnet; bei Inaktivität freigeben.
PDF-Ausschnitte vor dem Positionswechsel vollständig dekodieren: `gaplessPlayback`
zeigt sonst kurz die alten Pixel im neuen Rechteck. Alte Bildressourcen erst nach
dem Frame freigeben. Anzeigetimeouts müssen auch Warteschlange/Öffnen abdecken;
verspätete Resultate dürfen weder angezeigt noch als Vorschau gespeichert werden.
Auch `exit(0)` kann auf einen Dart-Isolate in einem nativen Aufruf warten.
Unter Windows erst Änderungen speichern und SQLite schließen, dann den eigenen
Prozess direkt beenden; nicht auf PDF-Cleanup warten. Regressionstest mit
blockiertem FFI-Worker und anschließend wieder freier Dateisperre erhalten.

Widgettests nutzen eine künstliche Uhr. Speicher-/Erinnerungs-Timer rechtzeitig
beenden; echtes Datei-I/O passend außerhalb dieser Uhr ausführen. Testdoubles
müssen auch neu benötigte Notifier bereitstellen. Die bestehende Headless-
PDFium-Einschränkung beachten; Mocktests ersetzen keine Prüfung im Programm.
