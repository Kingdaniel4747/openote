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

## KI zum Lernen verbinden

1. In Openote auf „KI: aus“ neben dem Seitentitel klicken oder in den
   Einstellungen „KI-Lernzugriff“ öffnen.
2. „Aktuelle Seite“ oder „Dieses Notizbuch“ freigeben. Der Seitenmodus folgt
   der aktiven Seite, auch im geteilten Fenster. Die Buchfreigabe bleibt an das
   ausgewählte Buch gebunden; beim Wechsel in ein anderes Buch ruht der Zugriff.
3. Im Desktop-KI-Client einen MCP-Server mit **Streamable HTTP** hinzufügen.
   URL und Authorization-Wert mit den Schaltflächen aus Openote übernehmen.
   Für Codex alternativ „Codex-Konfiguration kopieren“ und den Abschnitt in
   die persönliche `~/.codex/config.toml` einfügen; danach den Client neu verbinden.
   Diese Konfiguration enthält ein geheimes Token und gehört nicht ins Repository.
4. Beispielsweise fragen: „Erkläre meine aktuelle Seite“ oder „Lies alle Seiten
   dieses Buchs und frage mich dazu ab“.

Openote muss geöffnet bleiben. Der Server ist nur über `127.0.0.1` erreichbar;
ein reiner Web-Client kann diese lokale Adresse nicht abrufen. Ein belegter
Port wird im Dialog als Verbindungsfehler angezeigt. Nach einem Neustart ist
die Freigabe aus; die Verbindungsdaten bleiben für die nächste Freigabe erhalten.

Der Zugriff ist ausschließlich lesend und schließt gesperrte Seiten aus.
Text einschließlich PDF-Text wird portionsweise geliefert, Handschrift, Bilder
und PDF-Anmerkungen als begrenzte Seitenbilder mit Detailausschnitten. Buchlisten
und Textsuche helfen beim gezielten Nachlesen; Handschrift wird nicht automatisch
per OCR durchsuchbar. Videos, Dateianhänge und verknüpfte Seiten werden nicht
automatisch geöffnet. Bereits übertragene Inhalte bleiben im Chat; eine
Cloud-KI verarbeitet sie bei ihrem Anbieter.

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

Der GitHub-Workflow **Release packages** wird unter Actions manuell gestartet
und veröffentlicht eine gemeinsame Version mit Windows-Setup-`.exe` und
Scanner-APK. Normale Pushes lösen keinen Release aus. Diesen Ablauf unverändert
lassen; kein Push oder Release ohne ausdrücklichen Auftrag.

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
