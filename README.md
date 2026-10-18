# Openote

Lokale Notizen für Windows: frei schreiben, mit dem Stift zeichnen, PDFs
beschriften und Materialien für Schule und Studium organisieren.
Die Android-Begleitapp **Openote Scanner** überträgt Dokumente direkt auf
die ausgewählte Seite. Beide Apps bleiben in diesem Repository.

## Windows starten

Benötigt: Flutter mit Windows-Desktop-Unterstützung und Visual Studio mit
C++-Desktopwerkzeugen. Lokal geprüft: Flutter 3.47.7 / Dart 3.13.5 und
Visual Studio Community 2026 Insiders mit CMake 4.3.1.

```powershell
cd app
flutter pub get
flutter run -d windows
```

Im Flutter-Terminal: `r` für Hot Reload, `R` für Hot Restart, `q` zum Beenden.
Native C++-/Rust-Änderungen brauchen einen neuen Build. Der Repository-Hauptordner
selbst ist kein Flutter-Paket.

Rust/Cargo baut den optionalen nativen Kern, insbesondere für den OneNote-Import.
Ohne ihn startet die App mit dem Dart-Kern. Endnutzer benötigen keine separate
Rust-Installation. Die lokalen Plugin-Overrides in `app/pubspec.yaml` gehören
zum funktionierenden Build.
Für OneNote-Import Rust/Cargo bereitstellen, in `rust/onote_core/` mit
`cargo build --release` prüfen und anschließend die Windows-App neu bauen.

## Scanner verbinden

1. In Openote die Zielseite öffnen und „Scan from phone“ wählen.
2. Mit Openote Scanner auf Android den angezeigten QR-Code scannen.
3. Dokumente scannen und auf die Seite übertragen.

Beide Geräte brauchen ein gegenseitig erreichbares lokales Netzwerk,
normalerweise dasselbe WLAN. Die Windows-Firewall muss private eingehende
Verbindungen erlauben. Website und Cloudserver sind dafür nicht erforderlich.
Das Schließen des Kopplungsdialogs beendet den Empfänger.

## Ordner und Projektwissen

| Pfad | Aufgabe |
|---|---|
| `app/` | Windows-App; Linux-Quellcode bleibt erhalten |
| `scanner/` | Android-Scanner |
| `rust/onote_core/` | Optionaler nativer Kern und OneNote-Import |
| `packaging/` | Windows-Installer und spätere Linux-Pakete |
| `.github/workflows/` | Gemeinsamer Build-/Release-Ablauf |

Ergänzend: [AGENTS.md](AGENTS.md), [PRODUCT.md](PRODUCT.md),
[ARCHITECTURE.md](ARCHITECTURE.md), [TASKS.md](TASKS.md) und
[LEARNINGS.md](LEARNINGS.md). Compilerdateien wie `app/build/` werden neu erzeugt.

## Prüfen und bauen

In `app/`: `flutter analyze`, passende Tests mit
`flutter test test/<datei>_test.dart`, Release-Build mit
`flutter build windows --release`. Die Gesamtsuite ist noch nicht vollständig
grün; siehe TASKS.md. Die manuelle Geräteprüfung übernimmt der Nutzer.
In `scanner/` gelten dieselben Analyse-/Testbefehle; ein APK-Build benötigt
zusätzlich Android SDK und Java.
Den Rust-Kern bei Änderungen separat mit `cargo test` in `rust/onote_core/` prüfen.

Der bestehende GitHub-Workflow veröffentlicht bei einem Push auf jeden Branch
eine gemeinsame Version mit Windows-Installer und Scanner-APK. Dieser Ablauf
bleibt unverändert. Kein Push oder Release ohne ausdrücklichen Auftrag.

Für signierte APKs benötigt er `ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` und `ANDROID_KEY_PASSWORD`.
Für Updates den gleichen Signaturschlüssel behalten und extern sicher sichern.
Keystore und `scanner/android/key.properties` gehören nicht ins Repository.

## Lizenzen

| Bestandteil | Bestehende Lizenz |
|---|---|
| App, Scanner und allgemeiner Projektcode | AGPL-3.0-or-later, siehe [LICENSE](LICENSE) |
| Eigener Rust-Kern | Apache-2.0; `rust/onote_core/LICENSE` und `NOTICE` |
| Lokale Plugins und `rust/onote_core/vendor/cab/` | MIT; jeweilige Lizenz und Patchhinweise bleiben dort |
| Inter / JetBrains Mono | OFL-1.1; Lizenztexte neben den Schriftdateien |

Fremdcode behält seine Lizenztexte. Der frühere CC0-Lizenztext der entfernten
Formatspezifikation liegt in `licenses/format-spec-CC0.txt`.
Der Rust-Kern bleibt unabhängig vom AGPL-Appcode; Abhängigkeiten entsprechend
prüfen. Beiträge unterliegen der jeweiligen Komponentenlizenz;
bestehende DCO-Konvention: `git commit -s`.

Der OneNote-Reader basiert auf Microsofts Spezifikationen MS-ONESTORE/MS-ONE.
`onenote.rs` (MPL-2.0) diente als externe Referenz; es ist keine Abhängigkeit
und kein Code daraus wird im Rust-Kern eingebunden.
