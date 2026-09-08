# Openote – Projektstand, Funktionen und bekannte Probleme

Stand: 8. September 2026
Repository: `Kingdaniel4747/openote`
Upstream: `icmric/openote`
Hauptplattform: Windows
Weitere Plattformen: Android-Scanner und Linux-Quellcode
Nicht mehr vorgesehen: macOS

Diese Datei ist eine technische und funktionale Übergabe. Sie beschreibt den
aktuellen Stand des Forks, die Wünsche des Nutzers, bereits umgesetzte Arbeiten,
bekannte Risiken und die nächsten Prüfungen. Aussagen unter „Erledigt“ sind im
Code vorhanden. Punkte unter „Noch prüfen“ dürfen nicht ohne Gerätetest als
vollständig gelöst betrachtet werden.

## 1. Hauptziel

Openote soll eine freie, anpassbare Alternative zu OneNote und Goodnotes für
Schule und Studium werden. Besonders wichtig sind:

- echte Notizbücher, Abschnittsgruppen, Abschnitte, Unterabschnitte und Seiten;
- sehr gute Stiftbedienung auf einem Samsung Galaxy Book 360;
- Schreiben und Zeichnen über PDFs, Bilder und andere eingefügte Objekte;
- zuverlässiges Speichern und vollständige, wiederherstellbare Backups;
- eine aufgeräumte Oberfläche für Touch, Stift, Maus und Tastatur;
- Windows als primäre Desktopplattform;
- Linux soll langfristig funktionsfähig bleiben;
- ein kleiner Android-Scanner als Begleit-App;
- automatische Installer, APKs und Releases über GitHub Actions.

Speicherverbrauch ist für dieses Projekt weniger wichtig als Datenintegrität,
Qualität und ein flüssiges Schreibgefühl.

## 2. Technische Grundlage

- Oberfläche: Flutter und Dart.
- Nativer Kern: Rust über FFI.
- Notizspeicher: SQLite-basierter `.onote`-Container.
- Große eingebettete Dateien werden als Blobs verwaltet.
- PDFs werden einmal gespeichert und ihre Seiten bei Bedarf gerendert.
- Windows-Build liegt unter `app/windows`.
- Linux-Build liegt unter `app/linux`.
- Android-Scanner liegt als getrennte Flutter-App unter `scanner`.
- Der Basiseintrag in `app/pubspec.yaml` ist weiterhin `0.8.0+14`.
- Der Release-Workflow berechnet die nächste öffentliche Version aus den
  vorhandenen Git-Tags; die öffentliche Version ist daher höher als der
  Basiseintrag im Pubspec.

## 3. Erledigte Funktionen und Änderungen

### 3.1 Stift, Zeichnen und Radierer

- Normales Schreiben mit dem Samsung-Stift funktioniert.
- Der Stiftknopf beziehungsweise die Stiftrückseite kann temporär zum Radierer
  wechseln.
- Der Werkzeugwechsel wurde auch für PDF-Seiten berücksichtigt.
- Der Radierer besitzt eine einstellbare Größe.
- Der Radiermodus „Bereich“ beziehungsweise „ganzer Strich“ wird gespeichert.
- Stift, Pinsel und Textmarker speichern eigene Größen und Farben.
- Ein Kugelschreiber ohne Druckempfindlichkeit ist vorhanden.
- Die maximale Stiftdicke wurde für präzisere kleine Schrift reduziert.
- Der Textmarker besitzt einen eigenen, größeren Dickenbereich.
- Stift- und Textmarkerfarben beeinflussen sich nicht gegenseitig.
- Schwarz ist in der Farbpalette vorhanden.
- Auf einem weißen PDF-Hintergrund wird eine sichtbare dunkle Stiftfarbe
  bevorzugt, sofern Weiß nicht ausdrücklich gewählt wurde.
- Striche wurden geglättet, damit große Stiftspitzen weniger Ecken und Zacken
  zeigen.

### 3.2 Lasso und Auswahl

- Der Lasso-Umriss ist sichtbar.
- Nach einer Auswahl erscheint ein kleines Aktionsmenü.
- Auswahlaktionen umfassen unter anderem Löschen, Duplizieren und weitere
  objektbezogene Befehle.
- Markierte Handschrift kann mit dem Finger verschoben werden.
- Handschrift rastet beim Verschieben nicht am Objektraster ein.
- Andere Objekte dürfen weiterhin das Raster verwenden.
- Der Auswahlrahmen wird während einer Bewegung aktualisiert.

### 3.3 Lineal und Formerkennung

- Ein halbtransparentes Lineal ist im Zeichnen-Tab vorhanden.
- Es lässt sich mit einem Finger verschieben.
- Zwei Finger verändern Länge und Drehung.
- Stiftlinien werden an der richtigen Außenkante des Lineals geführt.
- Linealgesten sollen den Seitenhintergrund nicht mitbewegen.
- Formerkennung kann dauerhaft ein- oder ausgeschaltet werden.
- Gerade Linien, Kreise, Rechtecke und Dreiecke sind vorgesehen.
- Eine Form wird durch Zeichnen und kurzes Halten ausgelöst, nicht erst durch
  das Abheben des Stifts.
- Erkannte Formen verwenden eine gleichmäßige Dicke ohne Druckempfindlichkeit.
- Linien und andere Formen können radiert werden.
- Nicht kreisförmige Formen können nach dem Erkennen gedreht und skaliert
  werden.

### 3.4 PDFs und eingefügte Objekte

- PDFs werden als Originaldatei einmal im Notebook gespeichert.
- Einzelne PDF-Seiten werden bei Bedarf gerendert, statt jede Seite dauerhaft
  als große Kopie zu speichern.
- „PDF Slides“ legt mehrere Seiten mit gleichmäßigen Abständen untereinander.
- „Page only“ erzeugt eine PDF-orientierte Seite, auf der nur im PDF-Bereich
  gearbeitet wird.
- Ein PDF mit mehreren Seiten bleibt auf einer Openote-Seite untereinander,
  statt ungefragt viele Openote-Seiten zu erzeugen.
- Über PDF-Seiten kann geschrieben und radiert werden.
- PDF-Seiten können ausgewählt, bewegt, dupliziert, gelöscht und gesperrt
  werden.
- PDFs behalten ihr Seitenverhältnis und werden nicht verzerrt.
- Bilder behalten beim Skalieren ebenfalls ihr Seitenverhältnis.
- Tabellen und Boards dürfen zusätzlich in ihrer Form verändert werden.
- Eingefügte Objekte verwenden einen einheitlichen Auswahlrahmen und ein
  einheitliches Kontextmenü.
- Original-PDFs können wieder geöffnet beziehungsweise exportiert werden.
- Eingefügte Dateien, Bilder und PDFs werden in den Notebook-Daten gespeichert
  und nicht nur auf den ursprünglichen Dateipfad verlinkt.

### 3.5 Touch, Maus und Tastatur

- Finger zeichnen standardmäßig nicht, solange Touch-Zeichnen nicht aktiviert
  wurde.
- Finger können Objekte auswählen und nach kurzem Halten verschieben.
- Langes Drücken dient an geeigneten Stellen als Rechtsklick.
- Tabellen, Boards, Dateien, Bilder und PDFs sollen dasselbe Grundverhalten bei
  Auswahl und Bewegung besitzen.
- Beim Bearbeiten von Text auf einem umgeklappten Laptop wird die
  Bildschirmtastatur unterstützt.
- Openote soll durch die Bildschirmtastatur nicht verkleinert werden; die
  Tastatur liegt als Windows-Overlay über der App.
- Ein Klick auf „Untitled Page“ setzt den Fokus direkt in den Seitentitel.

### 3.6 Seitenfläche, Zoomen und Scrollen

- Endlose Seiten und feste Papierformate werden unterstützt.
- Die Seite besitzt eine obere und linke Grenze.
- Innerhalb einer großen beschriebenen Fläche soll der Zoom um den Mittelpunkt
  der beiden Finger erfolgen.
- Mausrad-Zoom mit Strg dient als Referenz für flüssiges Verhalten.
- Scrollen läuft mit Trägheit aus.
- Lineal- und Objektgesten werden vor Seiten-Pan und Seiten-Zoom behandelt.

### 3.7 Writing Mode

- Der Writing Mode zeigt die aktuelle Seite großflächig an.
- Eine kleine schwebende Zeichnen-Werkzeugleiste bleibt sichtbar.
- Ein erreichbarer Knopf beendet den Writing Mode.
- Die Werkzeugleiste startet oben in der Bildschirmmitte.
- Sie kann frei verschoben werden.
- Berührt sie den linken oder rechten Bildschirmrand, dockt sie als vertikale
  Werkzeugleiste an.
- Symbole bleiben dabei aufrecht; Schieber werden passend vertikal angeordnet.
- Startposition, Andocken und Verlassen wurden durch Widgettests abgedeckt.

### 3.8 Windows-Fenster und Oberfläche

- Windows ist die primäre Desktopplattform.
- Fenster können maximiert, wiederhergestellt und minimiert werden.
- Freie Bereiche der oberen Leiste dienen zum Verschieben des Fensters.
- Writing Mode, Undo und Redo sind schnell erreichbar.
- Home, Insert, Draw und View besitzen eine einheitliche Tab-Behandlung.
- Papierhintergrund, Raster, Punkte, Seitenformat und Theme befinden sich unter
  View.
- Dark Mode und Light Mode können schnell gewechselt werden.
- Automatische Schwarz-Weiß-Stiftfarben wechseln passend zum Hintergrund;
  selbst gewählte bunte Farben bleiben unverändert.
- Sichtbare Tag-Suche, Tags-Seitenleiste und Tag-Tastenkürzel wurden entfernt.
- Interne Tag-Datenstrukturen existieren teilweise weiter, weil alte Aufgaben
  und Lernkarten darauf beruhen. Sie dürfen nicht blind gelöscht werden, ohne
  Datenmigration und Tests für Planer und Lernkarten.

### 3.9 Notizbücher und Organisation

- Notizbücher, Abschnittsgruppen, Abschnitte, Unterstrukturen und Seiten sind
  vorhanden.
- Abschnittsgruppen können über ihr Kontextmenü umbenannt und farblich
  bearbeitet werden.
- Der Notebook-Manager wurde an eine Goodnotes-artige Cover-Ansicht angenähert.
- Bücher werden über ihr Cover geöffnet.
- Kontextaktionen liegen in einem Drei-Punkte-Menü.
- Mehrere Coverfarben sind vorgesehen.
- Backup und Wiederherstellung sind direkt im Notebook-Bereich erreichbar.

### 3.10 Planer, Hausaufgaben und Erinnerungen

- Ein globaler Planer ist oben erreichbar.
- Der Planer-Knopf zeigt eine kleine Benachrichtigungszahl für unerledigte
  Hausaufgaben und Erinnerungen, unabhängig von der geöffneten Seite.
- Hausaufgaben können Fach, Aufgabe, Datum und Uhrzeit enthalten.
- Eine Hausaufgabe kann mit der aktuellen Seite verknüpft werden.
- Ein kompakter Monatskalender ist standardmäßig immer geöffnet.
- Jeder Tag wird als klarer Kalenderblock dargestellt.
- Klick auf einen Tag öffnet direkt die Auswahl:
  - Hausaufgabe hinzufügen;
  - Erinnerung hinzufügen;
  - Klausur hinzufügen.
- Leere Texte wie „Nothing Data“ beziehungsweise „Nothing dated yet“ wurden
  aus der Planer-Oberfläche entfernt.
- „Add a date“, Planner Settings und Kalender-Abonnements wurden aus der
  sichtbaren Oberfläche entfernt.

### 3.11 Speichern, Backup und WebDAV

- Änderungen werden automatisch gespeichert.
- Zeichnungen, Objekte und Löschungen verwenden denselben dauerhaften
  Speicherweg.
- Alte wiederkehrende Stiftstriche wurden durch Bereinigung und Korrekturen am
  Speicherpfad behandelt.
- Lokale Backups können als ZIP erstellt werden.
- Wiederherstellung aus einem vollständigen ZIP-Backup ist vorhanden.
- Ein Backup kann den gesamten Arbeitsbereich mit Notizbüchern und Blobs
  enthalten.
- WebDAV beziehungsweise Nextcloud ist als vollständiges
  Arbeitsbereichs-Backup integriert.
- Das WebDAV-Ziel erhält ein aktuelles Gesamtarchiv und keinen unvollständigen
  Satz loser, gerade geöffneter Dateien.
- WebDAV zeigt Fortschritt, Fehler und „Synced“ an.
- Automatisches WebDAV-Backup wird etwa eine Minute nach Änderungen geplant.
- Wiederherstellung aus WebDAV ist vorhanden.
- Das WebDAV-Passwort wird über den lokalen Secret Store gespeichert.
- Die frühere Git-Synchronisationsoberfläche wurde auf Nutzerwunsch entfernt;
  lokale Extra-Kopien dürfen bestehen bleiben.

### 3.12 Windows-Updater und Release

- Der Windows-Updater prüft das Repository `Kingdaniel4747/openote`.
- Ein neues Update wird nur angeboten, wenn eine neuere Version existiert.
- Der Release-Workflow liegt in `.github/workflows/release.yml`.
- Der eigenständige Workflow `.github/workflows/ci.yml` prüft bei jedem Push
  und Pull Request Desktop-App, Scanner und Rust-Kern, ohne Release-Dateien zu
  erzeugen.
- Ein Release wird nur durch einen Tag `vX.Y.Z` oder einen manuellen Workflow
  mit einer expliziten Version gestartet.
- Windows-Installer und Android-APK werden in getrennten parallelen Jobs
  gebaut.
- Ein dritter Job prüft beide Dateien und erstellt den GitHub-Release zunächst
  als Entwurf; erst nach Sichtprüfung wird er veröffentlicht.
- Der Windows-Release enthält einen echten Setup-Installer und keine unnötige
  portable ZIP-Datei.
- Funktionstests sind vom schnellen Release-Build getrennt.
- Der frühere getrennte Workflow `scanner-apk.yml` wurde gelöscht, weil der
  Release-Workflow die APK bereits baut.

### 3.13 Android-Scanner

- Die Scanner-App ist getrennt von der Windows-App.
- Beim Start wird kurz nach einem Update gesucht.
- Ohne Update öffnet sich sofort die QR-Kamera.
- Nach dem QR-Code öffnet sich direkt der Android-Dokumentenscanner.
- Mehrere gescannte Seiten werden in derselben Reihenfolge mit einheitlichem
  Abstand untereinander in die gewählte Openote-Seite importiert.
- Nach erfolgreichem Import schließt sich das QR-/Empfangsfenster auf Windows.
- Die Scanner-App verwendet das Openote-App-Symbol.
- Die APK liegt zusammen mit dem Windows-Installer im GitHub Release.
- Der In-App-Updater lädt die neueste versionierte Scanner-APK aus dem Release
  und öffnet die normale Android-Installationsbestätigung.

## 4. Android-Signatur: behoben im Workflow, einmalig noch einzurichten

Android akzeptiert ein Update nur, wenn alte und neue APK mit derselben
Signatur erstellt wurden. Die veröffentlichten Scanner-APKs hatten tatsächlich
unterschiedliche Zertifikate:

- 0.8.29: `BF30E1E9A111EEC14D5F8FD20F10BB91CFC30610641591CA9EFA4C9356553646`
- 0.8.30: `9CE7AE00DDC4F3D9E81ABB7BD0DC1FA2423496E7ABB5CC4368341657DC8243C8`
- 0.8.31: `5B35048FDBBC76690450945E37F32A2D02E80955042E30A03250B2C8374B79C4`
- 0.8.32: `A6D3105F896D247A5288198463707AA4522568568A6BE9BB6B2ADCB84CD814B0`

Ursache war eine pro Runner zwischengespeicherte Debug-Signatur. Sie konnte
verlorengehen oder durch einen anderen Schlüssel ersetzt werden. Dadurch waren
die veröffentlichen Scanner-APKs untereinander nicht aktualisierbar.

Umgesetzt am 8. September 2026:

- `scanner/android/app/build.gradle.kts` akzeptiert für Release-Builds keine
  Debug-Signatur mehr und bricht ohne Schlüsseldaten ab.
- `.github/workflows/release.yml` liest den Keystore ausschließlich aus vier
  GitHub-Actions-Secrets (`ANDROID_KEYSTORE_BASE64`, Passwort, Alias,
  Schlüsselpasswort) und schreibt ihn nur auf den kurzlebigen Build-Runner.
- Der alte Cache-Schlüssel `openote-scanner-signing-linux-v2` wird nicht mehr
  verwendet. Er darf für keine neue Release-Signatur wiederbelebt werden.

Noch manuell erforderlich, bevor der nächste APK-Release starten kann:

1. Einen dauerhaften Release-Keystore erzeugen und sicher offline sichern.
2. Seine Werte als die vier in `scanner/README.md` genannten Repository-Secrets
   hinterlegen.
3. Die erste mit diesem Keystore signierte APK nach der bisherigen Scanner-App
   installieren. Wenn deren Signatur abweicht, ist einmalig Deinstallation und
   Neuinstallation nötig.
4. Zwei aufeinanderfolgende spätere Releases als In-App-Update testen.

Der private Schlüssel darf niemals öffentlich in das Repository gelangen. Bei
Verlust des endgültigen Schlüssels sind weitere direkte Updates derselben
Android-App nicht möglich.

## 5. Bekannte Probleme und noch notwendige Gerätetests

### Hohe Priorität

1. Pinch-Zoom auf echter Touch-Hardware weiter beobachten.
   - Historischer Fehler: Beim Hineinzoomen sprang die Seite nach unten, beim
     Herauszoomen nach oben.
   - Der Fehler trat mit leeren Seiten und besonders deutlich mit PDFs auf.
   - Maus-/Strg-Zoom war flüssig, nur Zwei-Finger-Gesten waren betroffen.
   - Gesten wurden mehrfach entkoppelt und getestet, benötigen aber weiterhin
     einen echten Galaxy-Book-Test.

2. Lineal mit zwei Fingern auf dem Gerät prüfen.
   - Zwei Finger vollständig auf dem Lineal dürfen nur das Lineal verändern.
   - Hintergrund, Zoom und Scrollposition dürfen sich dabei nicht bewegen.
   - Der Code besitzt dafür eigene Pointer-Zustände und Regressionstests.

3. Schließen unter realer Last beobachten.
   - Das Programm soll durch laufendes Autosave bereits schließbereit sein.
   - Bei großen PDFs, laufendem PDF-Rendering oder WebDAV darf das Schließen
     nicht lange hängen.
   - Falls es erneut langsam ist, müssen aktive PDF-Worker, Medienprozesse,
     WebDAV-Debounces und Datenbank-Flush getrennt gemessen werden.

4. WebDAV-Dateisperren weiter beobachten.
   - Gemeldeter Fehler: `PathAccessException`, weil ein anderer Prozess einen
     Teil einer Datei gesperrt hatte.
   - Die aktuelle Backup-Strategie erstellt deshalb zunächst ein konsistentes
     Gesamtarchiv und lädt dieses hoch.
   - Bei erneutem Fehler müssen Dateiname, Prozess, Zeitpunkt und letzter
     Fortschrittstext protokolliert werden.

### Mittlere Priorität

5. Formerkennung auf echte Handschrift prüfen.
   - Gerade und Kreis funktionierten zuletzt zuverlässig.
   - Rechteck und Dreieck waren historisch teilweise fälschlich als Kreis
     erkannt worden.
   - Größe, Endpunkt und Drehung müssen direkt an der Stiftspitze bleiben.

6. Radierer nach PDF-Wechsel prüfen.
   - Der ursprüngliche Fehler trat auf, nachdem eine Seite mit PDF geöffnet
     wurde.
   - Die PDF-Darstellung wurde inzwischen strukturell geändert und der
     Stiftknopf funktionierte danach im Nutzertest.
   - Nach weiteren Gestenänderungen weiterhin als Regression prüfen.

7. Bildschirmtastatur im umgeklappten Galaxy Book prüfen.
   - Sie soll über Openote erscheinen.
   - Das komplette Openote-Fenster darf nicht erst langsam nach oben geschoben
     oder verkleinert werden.

8. Große PDF-Stapel prüfen.
   - Importzeit, Scrollen, Speichern, erneutes Öffnen, Verschieben, Sperren,
     Schreiben, Radieren und Export testen.
   - Nach Neustart müssen PDF und Handschrift exakt erhalten bleiben.

9. Android-Updater mit dem neuen dauerhaften Release-Keystore prüfen.
   - Der erste Wechsel von einer anders signierten APK kann eine Deinstallation
     verlangen.
   - Danach mindestens zwei aufeinanderfolgende Releases ohne Deinstallation
     installieren.

## 6. Nicht umgesetzt oder bewusst verworfen

- Direkte OneNote-Live-Integration in das Lehrer-Notizbuch wurde besprochen und
  anschließend vom Nutzer verworfen.
- Eine KI-Quizfunktion ist noch nicht eingebaut.
- Die aktuelle ChatGPT-/Codex-Sitzung kann nicht direkt als eingebettete,
  kostenlose App-Funktion verwendet werden.
- Für eine Online-KI-Funktion wäre eine getrennte API-Anbindung mit
  Nutzerzustimmung, Internetzugang, Datenschutzregeln und separater Abrechnung
  nötig.
- Alternativ kann später ein lokales Modell untersucht werden; Qualität,
  Speicher- und Rechenbedarf müssten dann getestet werden.
- Kalender-Abonnements wurden aus der sichtbaren Planer-Oberfläche entfernt.
- Sichtbare Tags wurden entfernt. Interne Tag-Daten dürfen wegen alter Aufgaben
  und Lernkarten erst nach einer geplanten Migration vollständig gelöscht
  werden.
- Aktuell veröffentlicht der vereinfachte Release-Workflow Windows und Android.
  Linux-Quellcode bleibt erhalten, ein Linux-Release-Job kann später wieder
  getrennt ergänzt werden.

## 7. Wichtige Verhaltensregeln für weitere Änderungen

- Bestehende Notizdaten niemals durch ein Update löschen oder still migrieren.
- Vor Änderungen an Speicherung, Blobs, PDFs oder Backups immer Rückwärts-
  kompatibilität prüfen.
- PDFs nur einmal speichern; keine erneute vollständige Rasterkopie pro Seite
  als Standardlösung einführen.
- Stift-, Touch-, Maus- und Linealgesten besitzen verschiedene Absichten und
  dürfen nicht gleichzeitig dieselbe Geste verarbeiten.
- Stiftknopf/Radierer muss auch über PDFs und nach Seitenwechsel funktionieren.
- Writing Mode muss immer einen sichtbaren Ausgang und erreichbare
  Zeichenwerkzeuge besitzen.
- Keine private Android-Signaturdatei in Git einchecken.
- Android-Releases ausschließlich mit den vier geschützten `ANDROID_*`-Secrets
  bauen. Keinen Debug-Keystore und keinen Actions-Cache als Release-Signatur
  verwenden.
- Windows-Installer und Android-APK getrennt und parallel bauen.
- Pushes und Pull Requests nur über CI prüfen; Pakete ausschließlich für einen
  expliziten Release-Tag oder manuellen Release-Entwurf bauen.
- Keine macOS-Arbeit hinzufügen, solange der Nutzer dies nicht ausdrücklich
  wieder verlangt.
- Keine Emojis in Code, Workflow-Texten oder technischen UI-Beschriftungen.
- Nach UI-Arbeiten mindestens die betroffenen Widgettests ausführen.
- Nach Gestenarbeiten zusätzlich echte Tests mit Finger und Samsung-Stift
  durchführen; Emulator- und Mausverhalten reichen nicht als Beweis.

## 8. Bereits vorhandene wichtige Tests

- `app/test/drawing_regressions_test.dart`
  - Writing Mode, Toolbar-Position, vertikales Andocken und Verlassen;
  - Stift-/Textmarkerzustände;
  - Lasso-Bewegung;
  - Tabellenbewegung und Raster;
  - Linealbewegung ohne Canvas-Bewegung;
  - Formerkennung und Radiererregressionen.
- `app/test/planner_panel_test.dart`
  - leerer Planer ohne störenden Leertext;
  - Klausuren, Aufgaben und Erinnerungen;
  - dauerhaft sichtbarer Monatskalender;
  - Tagesklick mit Hausaufgabe, Erinnerung und Klausur;
  - schmales und niedriges Fenster ohne Überlauf.
- `app/test/command_bar_compact_test.dart`
  - Toolbar bei breiten und schmalen Fenstern;
  - globaler Hausaufgaben-Zähler.
- `scanner/test/pairing_test.dart`
  - QR-/Pairingdaten;
  - Erkennung der passenden APK im neuesten GitHub Release;
  - Versionsvergleich des Scanner-Updaters.

Bei der letzten gezielten Desktopprüfung bestanden 27 relevante Widgettests.
Die Analyse enthielt keine Fehler; nur ältere Stilhinweise in `app_state.dart`
waren noch vorhanden.

## 9. Empfohlene nächste Reihenfolge

1. Aktuellen Stand über GitHub Desktop hochladen und den grünen CI-Lauf prüfen.
2. Dauerhaften Android-Release-Keystore erzeugen und die vier `ANDROID_*`
   Secrets aus `scanner/README.md` in GitHub hinterlegen.
3. Einen neuen Tag `vX.Y.Z` pushen; den erzeugten Release-Entwurf auf EXE und
   APK prüfen und erst danach veröffentlichen.
4. Scanner bei abweichender alter Signatur einmal deinstallieren, die neue APK
   installieren und danach einen zweiten Release für den In-App-Updater testen.
5. Auf dem Galaxy Book einen kurzen Regressionstest durchführen:
   - leere endlose Seite;
   - Zwei-Finger-Zoom;
   - Lineal mit einem und zwei Fingern;
   - Schreiben und Radieren auf PDF;
   - Writing Mode links und rechts andocken;
   - Bildschirmtastatur;
   - App schließen.
6. Ein großes reales Schul-PDF importieren, bearbeiten, schließen, neu öffnen,
   lokal sichern und über WebDAV wiederherstellen.
7. Erst nach diesen Stabilitätstests neue große Funktionen wie KI-Quiz oder
   Linux-Pakete beginnen.

## 10. Kurzer Abnahmetest für jede neue Version

- Neue Seite erstellen und Titel per Touch ändern.
- Mit Stift schreiben; Knopf halten; radieren; Knopf lösen; weiterschreiben.
- Dasselbe auf einer PDF-Seite wiederholen.
- Stift, Kugelschreiber und Textmarker wechseln; Größen und Farben prüfen.
- Lasso verwenden, Auswahl mit Finger bewegen und löschen.
- Lineal mit einem Finger bewegen und mit zwei Fingern drehen/strecken.
- Linie, Kreis, Rechteck und Dreieck zeichnen und halten.
- Seite mit zwei Fingern zoomen; kein Sprung darf auftreten.
- Writing Mode öffnen, Toolbar mittig prüfen, links/rechts andocken und
  verlassen.
- Hausaufgabe mit Fach und Datum anlegen; Badge und Kalender prüfen.
- Programm schließen und neu öffnen; gelöschte Striche dürfen nicht
  zurückkehren.
- Backup erstellen und testweise wiederherstellen.
- WebDAV-Syncstatus und Wiederherstellung prüfen.
- Scanner koppeln, mehrere Seiten scannen und Reihenfolge kontrollieren.
- Wenn eine neuere APK existiert, Update ohne Deinstallation testen.

## 11. Bereinigung und Release-Workflow vom 8. September 2026

- Entfernt: die veraltete automatische Versionsberechnung
  (`packaging/windows/release-version.ps1` samt Test) und das doppelte
  `sync-core.bat`. Der Windows-CMake-Build erstellt und bündelt den Rust-Kern
  bereits selbst.
- Entfernt: die alte, nicht mehr zutreffende plattformübergreifende
  Release-Anleitung. `docs/RELEASING.md` beschreibt jetzt ausschließlich den
  tatsächlichen Windows-Installer-/Android-APK-Ablauf.
- Neu: CI (`.github/workflows/ci.yml`) für Analyse und Tests auf Push/PR.
- Neu: explizite, tag-basierte Release-Pipeline mit parallelem EXE-/APK-Build,
  Dateiprüfung und GitHub-Release-Entwurf.
- Neu: gesicherte Android-Release-Signatur per GitHub-Secrets; Debug-/Cache-
  Signaturen werden für Releases abgelehnt.
- Verbessert: der Windows-Packer verlangt `onote_core.dll` und löscht vor einem
  erneuten Paketlauf nur seinen bekannten versionsspezifischen Staging-Ordner,
  damit keine alten DLLs im Installer landen.
- Lokale Flutter-, Dart- und Rust-Tools waren in dieser Arbeitsumgebung nicht
  installiert. Deshalb konnten die Builds hier nicht ausgeführt werden; sie
  laufen als erster Check im neuen CI-Workflow.
- Gelöscht wurden zusätzlich nur lokal erzeugte und bereits ignorierte Flutter-
  Build-/Cache-Dateien sowie IntelliJ-Metadaten unter `app/` und `scanner/`.
- Für die einmalige GitHub-Secrets-Einrichtung liegt die kurze Anleitung mit
  den vier exakten Namen in `ANDROID_SECRETS_SETUP.md` im Projektstamm.
- Auf ausdrücklichen Nutzerwunsch wurde ein einmaliger Android-Release-Keystore
  erzeugt. Die passende, ausdrücklich ignorierte lokale Secret-Datei darf nie
  committed oder geteilt werden.
