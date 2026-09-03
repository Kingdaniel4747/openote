# Windows-first fork

## Installer mit GitHub Desktop bauen

1. In GitHub Desktop dieses Repository öffnen. Alle Änderungen auswählen,
   einschließlich neuer Dateien und der gelöschten Dateien unter `app/macos`.
2. Als Zusammenfassung z. B. `Fix live S Pen buttons and add fullscreen controls`
   eintragen. **Commit to master** (bzw. deinen aktuellen Branch), dann **Push origin**.
3. Auf GitHub **Actions → Release** öffnen. Der neue Lauf baut ausschließlich
   Windows x64 und führt Dart-/Rust-Tests und die Lizenzprüfung aus.
4. Nach dem grünen Lauf unten **Artifacts → windows-x64** herunterladen.
   GitHub verpackt das Artefakt als ZIP; darin liegt nur die fertige
   `openote-0.8.0-windows-x64-setup.exe` (Version aus `app/pubspec.yaml`).
5. ZIP entpacken, Openote schließen und die Setup-EXE installieren.
   Notizbücher vor dem ersten Test sichern. Die Installation enthält Laufzeit-
   und Video-DLLs; Visual Studio ist auf dem Laptop nicht nötig.

Alternativ: **Actions → Release → Run workflow**, `platform: windows`,
Version leer lassen. Nicht gleichzeitig zusätzlich den Workflow
**Windows checks and installer** starten: Release verwendet ihn bereits.
Es wird keine öffentliche GitHub-Release-Seite angelegt oder verändert.

## Bedienung

- Windows startet standardmäßig im Vollbild. Unter **Settings → Appearance →
  Start in full screen** lässt sich der Startmodus speichern.
- **F11** oder **Toggle full screen (F11)** wechselt sofort zwischen Vollbild
  und normalem Fenster; der gespeicherte Startmodus bleibt davon unabhängig.
- Vom schmalen Griff am oberen Rand nach unten wischen, darauf tippen oder
  die Maus an den oberen Rand bewegen: Fensterleiste einblenden.
- Die Leiste bietet Minimieren, Vollbild verlassen und Schließen. Im normalen
  Fenster stehen die Windows-Knöpfe für Minimieren/Maximieren/Schließen bereit.
- Schließen verwendet weiterhin den normalen Speichern-und-Beenden-Ablauf.

## Stiftänderung und Hardwaretest

Die alte Windows-Ergänzung las nur `WM_POINTER`-Stiftdaten am Flutter-Fenster.
Zusätzlich konnte ein von Flutter beibehaltenes Tastenbit eine bereits
gemeldete native Freigabe überstimmen. Der neue Code liest Pointerdaten auch
vor der Weiterleitung im Windows-Message-Loop und berücksichtigt den
Sekundärtastenstatus bei Kontakt. Als Kompatibilitätsweg werden außerdem
HID-Berichte der Stifttaste ausgewertet, wenn der Treiber sie bereitstellt.
Diese Beobachtung ist auf die aktive App begrenzt; normale Pointer-Ereignisse
werden weder unterdrückt noch erzeugt. Maus und Touch bleiben unverändert.

Nach Installation auf einer Testseite prüfen:

1. Normal schreiben; Druck, Farbe und Stiftstärke prüfen.
2. Stift in Reichweite über dem Display halten. Taste mehrmals drücken und
   loslassen, ohne ihn wegzunehmen; Radierer-Cursor muss jeweils wechseln.
3. Während eines durchgehenden Kontakts schreiben → Taste halten/radieren →
   loslassen/weiterschreiben. Kein Entfernen aus dem Erfassungsbereich nötig.
4. Wiederholen mit Textmarker; anschließend Undo und normales Schreiben prüfen.
5. Taste halten, zu einer anderen App wechseln und zurückkehren. Kein klemmender
   Radierer; Maus-Rechtsklick und Finger dürfen nicht zum Stiftradierer werden.

Die automatisierten Tests prüfen Umschalten, Loslassen, Cursor und Strichtrennung
mit simulierten Ereignissen. Sie ersetzen keinen Test mit dem Samsung-S-Pen.
Ein Treiber, der überhaupt keine Live-Tastensignale bereitstellt, benötigt
weitere gerätespezifische Diagnose. Der C++-Teil wird durch den GitHub-Build geprüft.

## Linux später

**Actions → Release → Run workflow → platform: linux** baut ausschließlich
Linux (.deb, .rpm, .tar.gz). Es startet kein Windows-Build. Linux-Ziel,
Rust-Kern und Paket-Skripte sind erhalten; der neue Fenster-/Stiftcode ist
Windows-spezifisch. Ein Linux-Hardwaretest ist noch nötig.

## Umfang und Rückweg

Entfernt sind das native Apple-Projekt, seine Icon-Erzeugung und alle Mac-Buildjobs.
Historische Dokumentation, Testdaten und Apple-Unterstützung in Drittbibliotheken
sind keine aktiven Buildziele und bleiben erhalten. Vor dem Entfernen wurde der
Mac-Ordner lokal außerhalb des Repositories gesichert; auch Git enthält den alten Stand.
Keine Notizbücher oder installierten Programme wurden verändert.

Der ursprüngliche In-App-Updater verweist weiterhin auf das Originalprojekt.
Ein Original-Update enthält diese Fork-Änderungen nicht: neue eigene Versionen
weiter über diesen Actions-Workflow bauen und installieren.

## Lokale Prüfung am 03.09.2026

- 44 gezielte Tests für Stift, Fensterleiste und Build-Dateien bestanden.
- Gesamtsuite: 2.760 Tests bestanden, 20 ausgelassen (optionale Laufzeit-/Fixture-
  und Golden-Tests). Ein Windows-Credential-Store-Test war in der Sandbox blockiert;
  die unveränderte Wiederholung außerhalb der Sandbox bestand ebenfalls.
- Flutter-Analyse: keine Fehler oder Warnungen; 94 bestehende Info-Hinweise.
- Rust-Quellen sind unverändert. Für lokale FFI-Tests wurde der bereits gebaute
  Kern aus demselben Quellstand benutzt. Keine neu gebaute Windows-App behauptet:
  C++-Kompilierung, Installer-Installation und echter S-Pen-Test stehen noch aus.
