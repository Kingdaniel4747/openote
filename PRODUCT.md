# Produkt

Openote ist eine lokale Schreib- und Notizapp für Schule und Studium.
Windows hat Vorrang, besonders Stift und Touch auf einem Galaxy Book 360.
Der Android-Scanner ist eine Begleitapp, kein zweiter Notizeditor.

## Was erhalten bleiben soll

- Notizbücher, Abschnitte und Seiten mit zuverlässigem lokalem Speichern.
- Freie Seitenfläche: Text, Handschrift, Formeln, Tabellen, Bilder, PDFs,
  Videos, Dateien und Aufgabenboards. Alte Dateiverweise bleiben lesbar.
- PDF-Import, Beschriften, Leser mit Textauswahl und PDF-Export.
- Gemeinsames Verhalten von Maus, Tastatur, Touch und Stift; Undo/Redo.
- Planer für Hausaufgaben, Aufgaben, Erinnerungen, Prüfungen und Lesekalender.
- Sicherung und Wiederherstellung der vollständigen Notizbücher.
- QR-Kopplung und direkte Scan-Übertragung vom Android-Handy im lokalen Netz.
- OneNote-Import über den optionalen Rust-Kern.
- Optionaler, rein lesender MCP-Lernzugriff für die aktuelle Seite oder ein
  ausdrücklich freigegebenes Notizbuch; Text, Handschrift, Bilder und PDFs.

## Aktuelle Bedienung

- „Meine Handschrift · Beta“ neben den Einstellungen: geführte Einrichtung aller
  84 Klein-/Großbuchstaben, Zahlen und Satzzeichen. Ein Zeichen mit Stift oder Maus
  schreiben, bestätigen und automatisch zum nächsten wechseln; Fortschritt lokal
  speichern und beim ersten fehlenden Zeichen fortsetzen. Die Textumwandlung ist
  bis zum vollständigen Profil gesperrt und öffnet danach automatisch. Bestätigen
  und Einfügen bleiben unten erreichbar; Größe/Abstände sind aufklappbar. Danach
  bis zu fünf Varianten je Zeichen ergänzen und weitere Sonderzeichen direkt aus
  dem Text einlernen. Das Schreibfeld samt blassem Größenbeispiel ist auf 160
  statt 300 Pixel verkleinert; gespeicherte Schriftgröße und Ausgabe bleiben
  gleich. Unter dem Feld steht nur ein mittiger Kreis-Pfeil zum Leeren und
  Neuschreiben; Werkzeugauswahl, Undo-Stroke und doppelter Retry-Knopf entfallen.
  Beim Hover ist der Cursor unsichtbar, die Stifttaste radiert weiterhin.
  Einlernen und Bearbeiten verwenden stets die feste mittlere Dicke 2,5 ohne
  Druckempfindlichkeit, auch für ältere Vorlagen. Erzeugte Handschrift bleibt
  druckunabhängig; ihre Dicke lässt sich weiterhin nachträglich ändern.
  Verlorene Stift-Endmeldungen, Geräteentfernung, Fokusverlust und Hot Reload
  schließen den offenen Entwurfskontakt ab, statt das Schreibfeld zu blockieren.
  „Schrift bearbeiten“ zeigt alle Zeichen mit eigener Schrift und Größenbeispiel;
  je Zeichen sind die bis zu fünf Varianten nebeneinander auswählbar. Gezielt
  ersetzen oder hinzufügen, ohne die Zeichenansicht nach dem Speichern zu verlassen.
  „Gespeichert“ bestätigt den Vorgang und wählt automatisch den nächsten leeren
  Entwurf, solange noch keine fünf Varianten gespeichert sind. Bei fünf bleibt
  die gespeicherte Variante ausgewählt; der Pfeil führt zurück. Leere gespeicherte
  Varianten werden beim Wechsel oder Zurückgehen entfernt, neue leere Entwürfe
  belegen keinen Platz. Es gibt höchstens eine Kachel „Neue Variante“ und maximal
  fünf gespeicherte Varianten; volle Listen verdrängen nichts.
  Frische Fingertipps auf Dialogknöpfe funktionieren nach dem Abheben auch bei
  Stift-Hover; bereits aufliegende Handkontakte bleiben ausgeschlossen.
  Der Neustart-Knopf neben dem X löscht nach Bestätigung sämtliche Schriftproben
  und Varianten und beginnt wieder bei „a“. Bereits eingefügte Handschrift auf
  Notizseiten bleibt erhalten; Umwandeln ist bis zur neuen Einrichtung gesperrt.
  Vorschau mit Schriftgröße, Zeilenbreite, Wort-/Zeilenabstand. Die bisherigen
  Standards 28/600/1/1 stehen bei allen vier Reglern mittig; nach links lassen
  sich alle Werte verkleinern, der Zeilenabstand bis 0,5. Feste Papierbreiten
  begrenzen die Ausgabe weiterhin.
  Einfügen als normale radierbare, verschiebbare
  Stiftstriche mit Undo/Redo. Beta setzt Einzelzeichen zusammen, ohne verbundene
  Schreibschrift oder automatisches Lernen aus Notizen. Geräte-Workflow noch prüfen.
- Lasso-Auswahl: Farben einschließlich Farbmischer/Pipette und Strichdicke in
  „Zeichnen“ ändern die ausgewählten Striche; nicht ausgewählte bleiben erhalten.
- Kalender: Monatsraster und Tageszähler bleiben der Einstieg. Ein Datum öffnet
  direkt rechts eine Hausaufgabe ohne Datums-/Uhrzeitdialog. Aufgabe genügt,
  Notizen, Eintragsart, Farbe und Seitenverknüpfung sind optional. Enter speichert;
  Speichern/Abbrechen und „Alle anzeigen“ bleiben erreichbar. Einträge öffnen
  zum vollständigen Lesen/Bearbeiten, verknüpfte Seiten über einen eigenen Knopf.
  Der Knopf neben dem X kehrt zum aktuellen Monat und zur Übersicht zurück.
  Entwürfe bleiben beim Wechsel zwischen Tagen/Übersicht innerhalb des Panels
  erhalten; alte datierte und undatierte Einträge bleiben lesbar/bearbeitbar.
- Einstellungen: feste Themenleiste links, bei schmalen Fenstern eine kompakte
  Themenauswahl. Zusammengehörige Optionen stehen in ruhigen Gruppen mit kurzen
  Erklärungen und einheitlichen Auswahlfeldern. System/Hell/Dunkel sind direkt
  wählbare Flächen ohne Haken. Ganze Schalterzeilen sind bedienbar; Änderungen
  werden direkt gespeichert. Handschriftprüfung zeigt ihre Abhängigkeit von der
  Rechtschreibprüfung, statt einen wirkungslosen Schalter anzubieten.
- Nach dem Löschen der geöffneten Seite folgt die nächste Seite derselben Sektion,
  am Ende die vorherige. Ist die Sektion leer, bleibt sie ohne geöffnete Seite aktiv.
- Ruhiges Halten auf Sektionen und Seiten öffnet nach 0,6 Sekunden das Kontextmenü,
  auch in der eingeklappten Navigation. Bewegung vor Ablauf startet Verschieben.
- Ein ausdrücklich gewählter Stift, Textmarker oder Radierer bleibt nach dem
  Abheben aktiv. Nur aus dem Auswahlmodus vorübergehend aktiviertes Schreiben
  kehrt danach zur Auswahl zurück.
- Notizbuchauswahl: anpassbares Bücher-Raster mit mehrzeiligen Titeln,
  deutlicher Markierung des aktuellen Buchs und direkt sichtbarer Suche.
  Die Farbpalette markiert auch automatisch vergebene Farben. „Backup“ öffnet
  eine durchsuchbare Auswahl für ein Buch oder alle Bücher; die Auswahl bleibt
  beim Filtern erhalten. Danach wird der Speicherort der ZIP-Sicherung gewählt.
- Sektionen oben und links sowie Seiten werden direkt an ihrer Position mit
  Maus oder Finger verschoben. Nachbarn weichen animiert aus; kein schwebendes
  Drag-Pop-up, keine Einfügestriche. Griffpunkt und Begrenzung bleiben in der
  Leiste; lange Listen scrollen am Rand. Obere Sektionstabs sind 130 × 36 Pixel.
- Eine Seite 0,5 Sekunden über einer anderen halten zeigt die Unterseiten-
  Vorschau; Loslassen übernimmt sie. Wegziehen oder Abbrechen verwirft sie.
  Beim Umordnen bleiben vorhandene Unterseiten bei ihrer Hauptseite.
- Seitenexport liegt im Rechtsklickmenü als „Export“-Untermenü, erreichbar per
  Hover oder Klick und mit Ausweichrichtung am Fensterrand. Exportiert wird die
  angeklickte Seite. Formate: Markdown, Vektor-PDF, Bild-PDF, JSON Canvas und
  InkML; zusätzlich Export des ganzen Buchs als offene Ordnerstruktur.
- Sektionsmenüs enthalten Farbpunkte, Umbenennen, Gruppenzuordnung, Sperren und
  Löschen. Reihenfolgen werden manuell gesetzt; Prüfungen nur im Kalender.
- Import und Export verwenden Fortschrittsbalken, Prozent, erledigte und
  verbleibende Dateien/Seiten bzw. Arbeitsschritte. Fehler werden gesondert
  gezählt. Solange die Gesamtzahl unbekannt ist, erscheint „Preparing…“;
  mehrere PDFs zeigen zusätzlich Seitenfortschritt der aktuellen Datei.
- Jeder ausdrücklich ausgelöste Dateiexport fragt nach einem Ziel, auch
  „Save original“/„Save a copy“. Eine eindeutige Quelle verwendet einen
  Speichern-Dialog, mehrere Originale eine Ordnerauswahl. Mehrere markierte
  Blätter derselben PDF ergeben ein vollständiges Original; andere Quellen
  werden zusätzlich gespeichert. Das ändert weder Autosave noch Clipboard-Copy.
- Neue Bilder/PDFs und Handy-Scans landen standardmäßig unter bestehendem Inhalt
  mit 36 Pixel Abstand; Standardbreite 280–760 Pixel. Erkennbare horizontale
  Medienreihen werden rechts, vertikale Spalten unten fortgesetzt, ohne alte
  Blätter umzustellen. Bei unklarer Anordnung wird unter allem angehängt.
  Auf festen Papierseiten gelten weiterhin die Papiergrenzen.

## Bewusst entfernte Funktionen

Keine Move-up/down-Befehle, Favoriten/Sterne, native Druckfunktion, automatischen
Sektionssortierungen, Sektions-PDF-Exporte oder Prüfungsdialoge im Sektionsmenü.
Kein separater Share-as-PDF-Eintrag und kein Exportknopf oben.
draw.io-Einfügen und Spezialeditor, Anki-/Browser-Start, Anki-Export sowie
ungenutzte Lernkarten-Erstellung, Wiederholungsplanung und Study-Panel sind
entfernt. Die MCP-Einrichtung liegt ausschließlich hinter dem KI-Symbol,
nicht zusätzlich in den Einstellungen.

Bestehende Lernkartenblöcke und Inline-Karten bleiben lesbar/bearbeitbar;
alte draw.io-Dateien bleiben gewöhnliche Anhänge. Unbekannte Metadaten,
Originaldateien und alte Prüfungsdaten werden nicht beim Aufräumen gelöscht.

## Grenzen

Kein Benutzerkonto und kein benötigter Cloudserver. Die öffentliche Projektwebsite
erklärt Funktionen und Bedienung und verlinkt Windows- und Scanner-Downloads;
sie speichert keine Notizbücher und ist für die Apps nicht erforderlich.
Website und öffentliche README sind Englisch. Die Produktdarstellung verwendet
Ansichten der echten Oberfläche mit Beispieldaten; keine gezeichneten App-Mockups.
Kein eingebautes KI-Modell und kein neuer Lernkarten-Workflow. MCP verbindet
einen externen Desktop-KI-Client; Freigaben sind nach einem App-Neustart aus.
Alte Sync-, CRDT- oder Plattformpläne sind keine aktuellen Anforderungen.
Kompatibilitätsleser für ältere Notizbücher bleiben erhalten.
Zusätzliche macOS- und Linux-Pakete werden im gemeinsamen Release-Workflow gebaut;
erste erfolgreiche Builds und Geräteprüfungen stehen noch aus. Linux erhält
x64-DEB/RPM mit Menüeintrag, macOS eine Universal-DMG. Windows behält Vorrang.

## Arbeitspriorität

Zuerst die Windows-App zuverlässig und angenehm benutzbar machen.
Der Nutzer prüft Bedienung, Stiftgefühl und Scanner am echten Gerät.
Neue Funktionen oder größere Umbauten nur nach konkreter Anforderung.
Sechs kurze zentrale Projektdateien statt zusätzlicher Planungs-, Prüfbericht-
oder PDF-Sammlungen.

## Öffentliche Positionierung

Kostenlose Open-Source-Alternative zu OneNote für handschriftliches Arbeiten
unter Windows mit Stift und Touch. Schule, Studium, PDF-Aufgabenblätter und
Lernmaterialien stehen im Mittelpunkt; Android ist der begleitende Scanner.
Kein universeller Plattform-Support und keine vollständige OneNote-Kompatibilität
versprechen. Lokale `.one`/`.onepkg`-Importe brauchen den nativen Kern; Originale
behalten und importierte Inhalte prüfen. Keine Aussage über einen Alleinstatus
unter Alternativen, garantierte Suchplatzierungen oder KI-Empfehlungen.
