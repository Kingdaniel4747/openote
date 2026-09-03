# Windows-first fork

## Hochladen und neue Version installieren

1. In GitHub Desktop dieses Repository öffnen und alle Änderungen auswählen,
   einschließlich der neuen Test- und Versionsskripte.
2. Als Zusammenfassung z. B. `Fix school pen input and automate Windows releases`
   eintragen. **Commit to master** (bzw. den aktuellen Branch), dann **Push origin**.
3. Auf GitHub **Actions → Release** öffnen. Jeder Branch-Push baut ausschließlich
   Windows x64 und führt Dart-/Rust-Tests und die Lizenzprüfung aus.
4. Nach dem grünen Lauf auf der Repository-Seite **Releases** öffnen. Dort die
   `openote-<Version>-windows-x64-setup.exe` herunterladen. Kein Artefakt-ZIP nötig.
   Unter **Actions → Artifacts → windows-x64** liegt zusätzlich die gleiche EXE im ZIP.
5. Notizbücher vor dem ersten Test sichern, Openote schließen und die EXE installieren.
   Visual Studio ist auf dem Laptop nicht nötig; Laufzeit- und Video-DLLs sind enthalten.

Alternativ: **Actions → Release → Run workflow**, `platform: windows`, Version leer lassen.
Nicht zusätzlich **Windows checks and installer** starten: Release verwendet ihn bereits.
Der Einzelworkflow baut nur ein Test-Artefakt und veröffentlicht keinen Release.

## Automatische Versionsnummern

- Ein **Push**, nicht jeder lokale Speichervorgang, startet einen Release-Lauf.
  Mehrere Commits in einem Push ergeben einen Release des letzten Commits.
- Die höchste Version aus den vorhandenen `vX.Y.Z`-Tags und der Pubspec-Basis
  wird um eine Patch-Version erhöht, z. B. `0.8.0 → 0.8.1 → 0.8.2`.
- Windows-Läufe werden über alle Branches hinweg nacheinander abgearbeitet
  (bis zu 100 wartende Läufe). Ein neuer Push bricht den laufenden Build nicht ab.
- Nur nach erfolgreichen Tests, Build und Paketierung wird ein neuer Release
  veröffentlicht. Bei einem Fehler den roten Schritt in Actions prüfen.
- Ein erneuter Lauf desselben bereits veröffentlichten Commits überschreibt nichts
  und veröffentlicht keine zweite Version desselben Stands.
- Die EXE-Dateieigenschaften, Installer und App-Update-Anzeige bekommen dieselbe
  berechnete Version. Die Quelldateien benötigen dafür keinen Bot-Commit.
  `app/pubspec.yaml` bleibt die Basis für lokale und Linux-Builds.
- Der Tag verweist auf den gebauten Commit; GitHub bietet dazu automatisch
  **Source code (zip/tar.gz)** an.
- Der Windows-Build bekommt den Namen seines GitHub-Repositories als
  `OPENOTE_REPOSITORY` mit. Der In-App-Updater sucht deshalb in deinem Fork,
  nicht im Originalprojekt. Die erste neue Version bitte über die EXE installieren.
- Der Workflow benötigt `contents: write`. Falls GitHub das durch eine übergeordnete
  Richtlinie blockiert, muss diese Berechtigung für Actions erlaubt werden.
  Ein persönlicher Zugriffstoken ist nicht nötig.

## Bedienung und Änderungen

- Windows startet standardmäßig im Vollbild. **Settings → Appearance →
  Start in full screen** speichert einen anderen Startmodus.
- Eine gemeinsame obere Windows-Leiste enthält die Zusatzfunktionen, **Settings**
  und Minimieren, Maximieren/Wiederherstellen, Schließen. Die alte zusätzliche
  Windows-Titelleiste entfällt; der schmale Systemrahmen folgt auf Windows 11 der
  Hintergrundfarbe. **Home / Insert / Draw** bleiben darunter.
  Den freien Bereich links bei „Openote“ ziehen, um das Fenster zu bewegen;
  Doppelklick maximiert es. **F11** bzw. Settings schaltet Vollbild um.
  Im Vollbild verlässt der mittlere Fensterknopf zuerst den Vollbildmodus.
  Es gibt keine zusätzliche Leiste durch Stift-Hover oder Wischen.
- Tatsächlicher Stiftkontakt mit einem Zeichenwerkzeug öffnet den **Draw**-Tab.
  Auch aus Select/Text heraus beginnt Stiftkontakt mit dem Stift. Bewusst
  ausgewähltes Lasso, Textmarker oder Radierer bleiben benutzbar.
  Reines Hover wechselt keinen Tab. Die Stifttaste schaltet sichtbar zum Radierer
  und zurück; während des Kontakts werden Änderungen bis zum Abheben zurückgestellt.
- Unter **Draw → Eraser** stellt der Schieberegler den Durchmesser von 4 bis 100
  Bildschirmpixeln ein. Die Größe wird gespeichert und gilt auch beim Radieren
  mit der Stifttaste. Bereichs- und Ganzstrichradierer bleiben erhalten.
- Der Lasso-Umriss zeichnet bei jedem neuen Punkt neu. Eine helle Kontur macht
  ihn sowohl auf dunklem Papier als auch auf weißen PDF-Seiten sichtbar.
  Nach der Auswahl erscheint ein kleines Menü mit Löschen, Duplizieren,
  Kopieren, Ausschneiden und Auswahl aufheben. Lasso bleibt aktiv: zum erneuten
  Einkreisen einfach auf der freien Fläche beginnen.
- Der erste Stiftfarbpunkt zeigt im Dark Mode die tatsächlich verwendete helle
  Schreibfarbe, im Light Mode die dunkle. Bunte Farben bleiben unverändert.
  Zusätzlich gibt es festes Schwarz und Weiß: Für ein weißes Arbeitsblatt im
  Dark Mode das feste Schwarz wählen.
- Handschrift liegt über Bildern, PDF-Ausdrucken, Tabellen und anderen
  Seitenobjekten, auch beim PDF-Export. Im Zeichen-/Lasso-Modus nehmen diese
  Objekte keine Bearbeitungs- oder Verschiebe-Gesten entgegen.
- PDFs als **PDF printout** auf die Notizseite einfügen, um darauf zu schreiben.
  Der separate PDF-Lesedialog bleibt ein Leser mit Textauswahl.
- Im Zusatzmenü des PDF-Imports **PDF editor (pages only)** wählen:
  mehrere PDFs auswählen; jede PDF-Seite wird eine feste Openote-Seite in einem
  Abschnitt pro Datei. Schreiben funktioniert nur innerhalb des PDF-Papiers,
  und der PDF-Export behält dessen Seitenverhältnis ohne Titelband bei.
- Der Import wartet auf die PDF-Initialisierung. Gleichzeitige Ansichten teilen
  einen Öffnungs-/Rendervorgang. Fehler und Zeitüberschreitungen beenden den
  Ladezustand; **Retry / Erneut versuchen** erlaubt einen neuen Versuch.
- Im **Select / move**-Modus lange auf ein Objekt oder die freie Seite drücken:
  Das jeweilige Kontextmenü öffnet sich wie beim Rechtsklick. Das gilt auch für
  gesperrte PDF-Seiten. Buch-/Abschnitt-/Seitenmenüs sind per langem Drücken erreichbar.
  In aktiven Texteditoren bleibt langes Drücken für die Textauswahl erhalten;
  das Objektmenü ist dort über den Griff oberhalb erreichbar.
- Schließen speichert weiterhin lokal. Zusätzliche Datenbank-Komprimierung und
  ein neu gestarteter Git-Netzwerkabgleich werden nicht mehr beim Beenden abgewartet.
  Noch nicht hochgeladene Änderungen bleiben lokal; Git-Sync läuft in der Sitzung
  bzw. beim nächsten Start. Für sofortige Übertragung vor dem Schließen manuell
  synchronisieren. Komprimierung bleibt als manuelle Wartungsaktion verfügbar.
- Beim Start steht ein Ladehinweis im Fenster; beim Schließen erscheint
  „Saving and closing…“. Scheitert das Speichern, bleibt Openote mit einem
  Hinweis geöffnet, statt ungesicherte Änderungen zu verwerfen.

## Deutsch und lokale Rechtschreibprüfung

- **Settings → Interface language → Deutsch** übersetzt Hauptoberfläche,
  Menübefehle und Einstellungen. Spezialisierte Dialoge und manche dynamischen
  Statusmeldungen sind noch Englisch. Notizbuchnamen und Inhalte bleiben unverändert.
- Unabhängig davon **Writing language → Deutsch** auswählen und **Spell check**
  sowie bei Bedarf **Check handwriting** einschalten.
- Getippter Text erhält im aktiven Texteditor deutsche Unterstreichungen.
  Handschrift wird nach einer kurzen Schreibpause lokal erkannt; als falsch
  erkannte Wörter werden auf der Seite rot unterstrichen. Es wird nichts
  automatisch ersetzt und kein Notizinhalt an einen Server geschickt.
- Windows muss die gewählte Sprache einschließlich Handschrift unterstützen.
  Über **Check language support** lässt sich die Verfügbarkeit prüfen. Fehlende
  Komponenten in den Windows-Sprachoptionen nachinstallieren und Openote neu öffnen.
  Nur diese Erstinstallation benötigt gegebenenfalls einen Download.
- Kein zusätzliches großes KI-Modell und kein API-Schlüssel. Windows verwendet
  CPU/RAM während der Prüfung; der Bedarf hängt von Umfang und Handschrift ab.
  Erkennung kann Wörter falsch lesen oder Fehler übersehen. Die Markierungen
  sind Hinweise, keine zuverlässige Benotung oder automatische Korrektur.
- Linux behält die vorhandene englische Textprüfung. Die neue deutsche Prüfung
  und Handschrifterkennung sind derzeit Windows-spezifisch; die deutsche
  Hauptoberfläche und übrigen Funktionen bleiben auch unter Linux verfügbar.

## Hardwaretest nach Installation

1. Normal schreiben; Druck, Farben, Stiftstärke und automatischen Draw-Tab prüfen.
2. Stift nahe über dem Display halten und die Taste mehrmals drücken/loslassen,
   ohne ihn wegzunehmen. Radierer-Cursor und Rückkehr zum Stift prüfen.
3. Während des Schreibens die Taste drücken: der laufende Strich bleibt Stift.
   Abheben, dann radieren. Während des Radierens loslassen: erst nach dem
   Abheben zurück zum vorherigen Werkzeug. Mit Textmarker wiederholen; Undo prüfen.
4. Kleine/große Radierergröße vergleichen. Über ein Bild, einen PDF-Ausdruck und
   eine Tabelle schreiben. Die Objekte dürfen dabei nicht verrutschen.
5. Lasso langsam über freie, dunkle und weiße Flächen ziehen. Der Umriss muss
   sichtbar bleiben; die Auswahl muss weiterhin die gewünschten Striche nehmen.
6. Mit dem Stift über die obere Leiste fahren: keine Überlagerung. Alle drei
   Fensterknöpfe testen, anschließend ausschließlich per Finger Kontextmenüs öffnen.
7. Direkt nach einer Änderung schließen und wieder öffnen: die Änderung bleibt erhalten.
8. Bei gedrückter Stifttaste zu einer anderen App und zurück wechseln:
   kein klemmender Radierer; Maus und Finger dürfen nicht zum Stiftradierer werden.
9. PDF direkt nach dem Start importieren, mehrere PDF-Seiten öffnen, danach den
   PDF-only-Modus testen. Bei beschädigter Datei darf kein endloser Spinner bleiben.
10. Deutsche Schreibsprache aktivieren, bewusst einen Tippfehler schreiben und
    dasselbe handschriftlich versuchen. Sprachstatus und Unterstreichungen prüfen.

Die Windows-S-Pen-Brücke aus dem vorherigen Stand bleibt erhalten. Sie beobachtet
Pointer-/HID-Tastensignale nur für die aktive App. Automatisierte Tests simulieren
Eingaben und prüfen auch gerenderte Pixel; sie ersetzen keinen Samsung-Hardwaretest.

## Linux und Apple

**Actions → Release → Run workflow → platform: linux** baut nur Linux
(.deb, .rpm, .tar.gz), ohne Windows-Release. Linux-Ziel, Rust-Kern und Paketskripte
bleiben erhalten. Die Fenster-/native Stiftbrücke ist Windows-spezifisch.
Das Apple-Buildziel ist weiterhin entfernt; historische Dokumentation und
Apple-Code in Drittbibliotheken bleiben unangetastet.

## Lokale Prüfung am 03.09.2026 (aktuelle Erweiterung)

- 44 gezielte Tests bestanden, darunter Stiftwechsel erst nach Abheben, Lasso-Auswahlmenü,
  PDF-Ladefehler/Wiederholen, gemeinsame PDF-Ladevorgänge und feste PDF-Seitengröße.
- Oberflächentests für deutsche Hauptoberfläche, Sprachwechsel ohne Neustart,
  zusammengeführte Windows-Leiste und den Speicherhinweis beim Schließen.
- Die Brücke zur Rechtschreibprüfung wird mit simulierten Windows-Antworten
  geprüft: deutsche Textranges, sichtbare Handschrift-Unterstreichung und Abbruch
  veralteter Prüfungen. Das ersetzt keinen Test der installierten Sprachpakete.
- 5 PowerShell-Tests der Versionsberechnung bestanden; alle Windows-Skripte in
  den Workflows syntaktisch geprüft.
- Gesamtsuite: 2.784 Tests bestanden und 20 optionale Tests ausgelassen;
  zwei zusätzliche Schreibprüfungs-Integrationstests bestanden separat.
  Der Windows-Credential-Store-Test bestand separat außerhalb der Sandbox.
  Er verwendete nur seinen temporären Selftest-Eintrag.
- Flutter-Analyse: keine Fehler oder Warnungen; 103 Info-Hinweise bleiben.
- Rust ist unverändert. C++ wurde für Fensterleiste und lokale Schreibdienste
  erweitert, kann hier ohne die entfernten Microsoft-Bauwerkzeuge aber nicht
  kompiliert werden. Der native Windows-Build und Installer-Test laufen nach deinem Push.
  Echtes PDF-Rendering ist im Flutter-Testläufer weiterhin nicht verfügbar;
  die echten PDFs und der Samsung-Stift müssen im neuen Build geprüft werden.
  Keine Notizbücher, installierten Apps oder GitHub-Releases wurden lokal verändert.
