# Openote

**Die kostenlose Open-Source-Alternative zu OneNote für Windows mit Stift und Touch.**

Handschriftlich mitschreiben, PDFs beschriften und Lernmaterialien für ein ganzes
Semester organisieren: Openote ist ein Arbeits- und Lernraum für Schule, Studium
und den Alltag auf Windows-Geräten mit Stifteingabe. Der **Openote Scanner** auf
Android bringt Arbeitsblätter und Dokumente direkt auf deine Seite.

[Website & Anleitung](https://kingdaniel4747.github.io/openote/) ·
[Windows herunterladen](https://github.com/Kingdaniel4747/openote/releases/latest) ·
[Android-Scanner herunterladen](https://github.com/Kingdaniel4747/openote/releases/latest) ·
[Neuerungen](https://github.com/Kingdaniel4747/openote/releases) ·
[Fehler melden](https://github.com/Kingdaniel4747/openote/issues)

**Free, open-source handwriting and PDF annotation for Windows pen and touch.**
A OneNote alternative for students who want local notebooks, handwritten study
materials and an Android companion scanner. [English website & quick start](https://kingdaniel4747.github.io/openote/en/).

## Für deinen Stift. Für deinen Stoff.

- **Handschrift und Touch:** Stift, Kugelschreiber, Textmarker, präziser Radierer,
  Undo/Redo sowie Verschieben und Zoomen mit Touch. Windows-Handballenschutz
  gibt dem Stift Vorrang.
- **PDFs bearbeiten:** Skripte und Aufgabenblätter importieren, markieren,
  handschriftlich beschriften und Seiten wieder als PDF exportieren.
- **Ein System zum Lernen:** Notizbücher, Abschnitte, Seiten und Unterseiten;
  freier Platz für Text, Formeln, Tabellen, Bilder, Dateien und Videos.
  Der Planer sammelt Hausaufgaben, Aufgaben und Prüfungstermine.
- **Deine Daten lokal:** kein benötigtes Konto, kein Abo und kein erforderlicher
  Cloudserver. Lokale Dateien funktionieren offline. Ganze Bücher sichern,
  wiederherstellen oder in offenen Formaten exportieren.
- **Android-Scanner:** per QR-Code koppeln und Dokumente im lokalen Netzwerk
  direkt auf die ausgewählte Windows-Seite übertragen.
- **Optionale KI-Anbindung:** einem kompatiblen Desktop-KI-Client über MCP
  gezielt eine Seite oder ein Buch zum Lesen freigeben. Handschrift, Bilder und
  PDF-Anmerkungen werden als Seitenbilder bereitgestellt. Kein eingebautes
  Modell; externe KI-Dienste können Gebühren berechnen.

Für Geräte wie Microsoft Surface, Samsung Galaxy Book 360 sowie passende
Lenovo-Yoga- und ThinkPad-Modelle mit Stifteingabe. Stiftfunktionen und
Schreibgefühl hängen von der Hardware ab; nicht jedes Modell ist geprüft.
Wenn du eine GoodNotes-ähnliche Arbeitsweise auf Windows suchst, kannst du
Openote ausprobieren. Der Funktionsumfang unterscheidet sich von OneNote und
GoodNotes; Openote ist ein unabhängiges Projekt.

## Herunterladen und installieren

| App | Download | Zweck |
|---|---|---|
| Openote für Windows x64 | [Aktuelles Setup](https://github.com/Kingdaniel4747/openote/releases/latest), Datei mit `windows-x64-setup.exe` | Vollständiger Notizeditor und Lernarbeitsplatz |
| Openote Scanner für Android ab Version 6 | [Aktuelle APK](https://github.com/Kingdaniel4747/openote/releases/latest), Datei `openote-scanner-<Version>.apk` | Dokumente aufnehmen und an Windows senden |

Windows: Setup herunterladen und ausführen. Android: APK auf dem Handy öffnen;
gegebenenfalls die Installation aus dieser Quelle erlauben. Verwende die Dateien
aus diesem Repository. Der Scanner ist eine Begleitapp, kein Android-Notizeditor.
Linux-Quellcode bleibt vorhanden; Linux- und macOS-Downloads werden aktuell
nicht angeboten.

Beide Apps prüfen auf neuere GitHub-Releases. Updates werden nach Bestätigung
installiert. Auf Android muss jede Version mit demselben Schlüssel signiert sein.
Alternativ kannst du die aktuelle Version über die Links oben installieren.

## Die ersten fünf Minuten

1. Öffne die Notizbuchverwaltung und lege ein Notizbuch an.
2. Erstelle darin einen Abschnitt und eine Seite, etwa für ein Fach oder Seminar.
3. Wähle unter **Draw** einen Stift und schreibe los; unter **Home** schreibst
   und formatierst du Text. **Insert** fügt PDFs, Bilder und weitere Inhalte ein.
   **View** steuert Seitendarstellung und Zoom. Beschriftungen können je nach
   eingestellter Sprache übersetzt sein.
4. Ordne Abschnitte und Seiten durch Ziehen. Halte eine Seite etwa 0,5 Sekunden
   über einer anderen, um eine Unterseite vorzuschauen; Loslassen übernimmt sie.
5. Sichere dein Buch regelmäßig über **Backup** in der Notizbuchverwaltung.
   Wähle Bücher und Zielort der ZIP-Sicherung. Über **Import** stellst du sie
   wieder her. Bewahre eine weitere Kopie auf einem anderen Datenträger auf.

| Bedienelement | Wofür? |
|---|---|
| Home / Insert / Draw / View | Text / Inhalte einfügen / Handschrift / Ansicht |
| Kalendersymbol | Planer öffnen; per Kalendertag neue Einträge anlegen |
| KI-Symbol oben rechts | Lesenden Zugriff für einen externen KI-Client einrichten |
| Zahnrad | Einstellungen |
| Rechtsklick auf eine Seite → Export | Markdown, Vektor-PDF, Bild-PDF, JSON Canvas oder InkML exportieren |
| Notizbuchverwaltung → Backup / Import | Bücher sichern, Sicherungen und unterstützte Dateien importieren |

Jeder Dateiexport fragt nach einem Speicherort. „Save original“ sichert die
Originalquelle; mehrere Blätter derselben PDF ergeben ein vollständiges Original.
Mehr Bedienhilfe findest du auf der [Website](https://kingdaniel4747.github.io/openote/#anleitung).

## Kann ich OneNote-Notizbücher importieren?

Openote enthält einen **eingeschränkten Import für lokale `.one`- und
`.onepkg`-Dateien** über den optionalen Rust-Kern. Wähle **Import** in der
Notizbuchverwaltung. Der GitHub-Release-Build baut den nativen Kern mit;
lokale Builds ohne Cargo haben diesen Import nicht.

Nicht alle Inhalte oder Layouts sind unterstützt. Prüfe die importierten Seiten
und behalte die Originaldateien. Eine vollständige Migration oder originalgetreue
Bearbeitung ist nicht zugesichert. Es gibt keine direkte OneDrive-Anbindung.

## Scanner verbinden

1. In Openote die Zielseite öffnen und „Scan from phone“ wählen.
2. Mit Openote Scanner auf Android den angezeigten QR-Code scannen.
3. Dokumente scannen und auf die Seite übertragen.

Beide Geräte brauchen ein gegenseitig erreichbares lokales Netzwerk,
normalerweise dasselbe WLAN. Die Windows-Firewall muss private eingehende
Verbindungen erlauben. Website und Cloudserver sind dafür nicht erforderlich.
Das Schließen des Kopplungsdialogs beendet den Empfänger.

## KI zum Lernen verbinden

1. In Openote auf das KI-Symbol oben rechts neben den Einstellungen klicken.
2. Den Schalter einschalten und „Nur diese Seite“ oder „Ganzes Buch“ auswählen.
   Bei ausgeschalteter Freigabe sind Auswahl und Kopieren deaktiviert. Der Seitenmodus folgt
   der aktiven Seite, auch im geteilten Fenster. Die Buchfreigabe bleibt an das
   ausgewählte Buch gebunden; beim Wechsel in ein anderes Buch ruht der Zugriff.
3. „Für Chat kopieren“ wählen und den Text im Desktop-KI-Chat einfügen.
   Er enthält Verbindungsdaten mit geheimem Token und eine Einrichtungsanweisung.
   Der Client muss lokale MCP-Verbindungen unterstützen; gegebenenfalls ist
   ein Neustart nötig. Für Codex enthält der Text einen Abschnitt für
   die persönliche `~/.codex/config.toml`; danach den Client neu verbinden.
   Diese Konfiguration enthält ein geheimes Token und gehört nicht ins Repository.
4. Beispielsweise fragen: „Erkläre meine aktuelle Seite“ oder „Lies alle Seiten
   dieses Buchs und frage mich dazu ab“.

Openote muss geöffnet bleiben. Der Server ist nur über `127.0.0.1` erreichbar;
ein reiner Web-Client kann diese lokale Adresse nicht abrufen. Ein belegter
Port wird als kurze Fehlermeldung angezeigt. Nach einem Neustart ist
die Freigabe aus; die Verbindungsdaten bleiben für die nächste Freigabe erhalten.

Der Zugriff ist ausschließlich lesend und schließt gesperrte Seiten aus.
Text einschließlich PDF-Text wird portionsweise geliefert, Handschrift, Bilder
und PDF-Anmerkungen als begrenzte Seitenbilder mit Detailausschnitten. Buchlisten
und Textsuche helfen beim gezielten Nachlesen; Handschrift wird nicht automatisch
per OCR durchsuchbar. Videos, Dateianhänge und verknüpfte Seiten werden nicht
automatisch geöffnet. Bereits übertragene Inhalte bleiben im Chat; eine
Cloud-KI verarbeitet sie bei ihrem Anbieter.

## Für Mitwirkende

Einstieg: [PRODUCT.md](PRODUCT.md) für Funktionen und Bedienregeln,
[ARCHITECTURE.md](ARCHITECTURE.md) für Code-Einstiegspunkte,
[TASKS.md](TASKS.md) für offene Arbeit und [LEARNINGS.md](LEARNINGS.md)
für Fehlerfallen. [AGENTS.md](AGENTS.md) enthält die Arbeitsregeln.
Vor Änderungen den lokalen Git-Status und Diff prüfen; vorhandene Änderungen erhalten.

### Windows aus Quellcode starten

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

### Ordner und Projektwissen

| Pfad | Aufgabe |
|---|---|
| `app/` | Windows-App; Linux-Quellcode bleibt erhalten |
| `scanner/` | Android-Scanner |
| `rust/onote_core/` | Optionaler nativer Kern und OneNote-Import |
| `packaging/` | Windows-Installer und spätere Linux-Pakete |
| `website/` | Deutsche und englische GitHub-Pages-Website mit Bedienhilfe |
| `.github/workflows/` | Gemeinsamer Build-/Release-Ablauf |

Ergänzend: [AGENTS.md](AGENTS.md), [PRODUCT.md](PRODUCT.md),
[ARCHITECTURE.md](ARCHITECTURE.md), [TASKS.md](TASKS.md) und
[LEARNINGS.md](LEARNINGS.md). Compilerdateien wie `app/build/` werden neu erzeugt.

Ein vollständiger `.onotebook`-Ordner lässt sich bei geschlossener App auf einen
anderen Rechner kopieren. Beim Start und Öffnen der Notizbuchverwaltung werden
hinzugefügte Bücher erkannt; eine fehlende `workspace.json` wird aus den
Notizbüchern neu aufgebaut. Mitkopierte Bücher unter `Recycle Bin` bleiben im
Papierkorb. Die Backup-/Restore-Funktion sichert zusätzlich konsistente
Datenbankstände und erhält auch Medien aus älteren Speicherlayouts.
Importierte Kopien heißen bei Bedarf beispielsweise `Informatik 2` und liegen
in `Informatik 2.onotebook/Informatik 2.onote`. Umbenennen in der App passt beide
Namen an; Explorer-Umbenennungen werden beim nächsten Start oder erneuten Öffnen
der Notizbuchverwaltung abgeglichen.

### Prüfen und bauen

In `app/`: `flutter analyze`, passende Tests mit
`flutter test test/<datei>_test.dart`, Release-Build mit
`flutter build windows --release`. Die Gesamtsuite ist noch nicht vollständig
grün; siehe TASKS.md. Die manuelle Geräteprüfung übernimmt der Nutzer.
In `scanner/` gelten dieselben Analyse-/Testbefehle; ein APK-Build benötigt
zusätzlich Android SDK und Java.
Den Rust-Kern bei Änderungen separat mit `cargo test` in `rust/onote_core/` prüfen.

### Website auf GitHub Pages aktivieren

Einmal im GitHub-Repository **Settings → Pages → Build and deployment → Source:
GitHub Actions** wählen. Danach veröffentlicht **Publish website** bei Pushes auf
`master`, wenn sich Website-Dateien oder der Pages-Workflow ändern. Manuelles
Starten ist ebenfalls möglich. Zieladresse:
`https://kingdaniel4747.github.io/openote/`. Die statischen Dateien in `website/`
benötigen keinen Build und können lokal mit einem HTTP-Server angezeigt werden.

Download-Knöpfe ermitteln die aktuellen Dateien über die öffentliche GitHub-API.
Ist sie nicht erreichbar oder begrenzt, bleiben Links zum neuesten Release aktiv.
Die Seiten enthalten lesbare Inhalte ohne JavaScript, Sprachverweise, Metadaten,
SoftwareApplication-Daten und eine `sitemap.xml`. Keine Analyse-Tracker oder
externen Schriftarten. GitHub übernimmt Hosting und Downloads.

Nach der Veröffentlichung kannst du die Website in Google Search Console als
URL-Präfix bestätigen und die Sitemap einreichen. Verlinke sie auch im
GitHub-„About“-Bereich. Suchbegriffe wie OneNote-Alternative Windows,
Handschrift-App Windows, PDF mit Stift beschriften und handwriting app Windows
stehen im sichtbaren Inhalt. Suchplatzierungen und KI-Empfehlungen lassen sich
nicht garantieren. Für Googles KI-Suche gelten die normalen
[SEO-Grundlagen](https://developers.google.com/search/docs/appearance/ai-features).
Ein Website-Unterpfad kann keine wirksame `robots.txt` für die gesamte
`github.io`-Domain setzen; deshalb liegt hier keine irreführende Robots-Datei.

### Ein neues Release veröffentlichen

**Jeder Push auf `master` startet „Release packages“**: Windows-Setup und
signierte Scanner-APK werden gemeinsam gebaut und erst nach beiden erfolgreichen
Builds veröffentlicht. Der Workflow erhöht die höchste vorhandene Versionsnummer
um einen Patch; die lokale Pubspec-Version ist die Untergrenze. Pushes auf andere
Branches und Tag-Pushes veröffentlichen nicht. Läufe werden serialisiert; GitHub kann bei
mehreren schnellen Pushes einen noch wartenden Lauf durch den neueren ersetzen.

Vor dem Push die sichtbaren Neuerungen im markierten Abschnitt **„Nächstes
Release“ in TASKS.md** eintragen. Schreibe kurz aus Nutzersicht, etwa „PDFs bleiben
beim Zoomen scharf“. Der Workflow übernimmt geänderte Notizen, Datum und Commitliste
in den Release-Text. Unveränderte Notizen werden nicht erneut als neue Features
ausgegeben; dann erscheint ein Wartungshinweis mit den tatsächlichen Commits.
Die Updateanzeige erhält denselben Release-Text über GitHub.

Ein manueller Start mit eigener Version und optionalem Markdown-Text bleibt
möglich. Bestehende Versions-Tags werden abgelehnt. Kein Push oder Live-Release
durch einen Agenten ohne ausdrücklichen Auftrag.
Release-Textlogik im Hauptordner prüfen:
`node --test .github/scripts/*.test.mjs`.

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
