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

- Beim Einrasten von Drehgesten den freien Zeigerwinkel getrennt vom angezeigten
  Winkel weiterführen, damit auch langsames Weiterdrehen die Rastung lösen kann.
- Rust-FFI braucht `panic = "unwind"` für `catch_unwind`; `opt-level = 3`
  erhält die Importgeschwindigkeit. Sortierte JSON-Schlüssel für stabile Hashes
  erhalten (`serde_json` nicht auf `preserve_order` umstellen).
- Den lokalen `cab`-Patch für effizientes Entpacken von `.onepkg` erhalten;
  Details stehen direkt in `rust/onote_core/vendor/cab/OPENOTE-PATCH.md`.
- Speicherungen vor dem Schließen abwarten; fehlgeschlagene Saves nicht als
  Erfolg anzeigen. Bei Formatänderungen alte Dateien erhalten.
- SQLite-DLLs in Tests aus einer Kopie laden, damit Windows den nächsten
  App-Build nicht durch gesperrte Runner-Dateien blockiert.
- Lange Menütexte innerhalb der Zeile begrenzen/umbrechen lassen.
- Nach `await` die Lebensdauer des verwendeten Dialog-Kontexts prüfen.
- Beim Löschen von Prüfungsdatum und Uhrzeit beide Maps unabhängig verändern;
  `remove(date) || remove(time)` überspringt die zweite Operation.
- Erfolgreicher Hot Reload und saubere Analyse beweisen keine grüne Gesamtsuite.
  Alte Erwartungen mit dem heutigen Produkt abgleichen.

## Prüfungen

Widgettests nutzen eine künstliche Uhr. Speicher-/Erinnerungs-Timer rechtzeitig
beenden; echtes Datei-I/O passend außerhalb dieser Uhr ausführen. Testdoubles
müssen auch neu benötigte Notifier bereitstellen. Die bestehende Headless-
PDFium-Einschränkung beachten; Mocktests ersetzen keine Prüfung im Programm.
