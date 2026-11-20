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

Keine Projektwebsite, kein Benutzerkonto und kein benötigter Cloudserver.
Kein eingebautes KI-Modell und kein neuer Lernkarten-Workflow. MCP verbindet
einen externen Desktop-KI-Client; Freigaben sind nach einem App-Neustart aus.
Alte Sync-, CRDT- oder Plattformpläne sind keine aktuellen Anforderungen.
Kompatibilitätsleser für ältere Notizbücher bleiben erhalten.
Linux-Quellcode und Packaging bleiben für später bestehen.

## Arbeitspriorität

Zuerst die Windows-App zuverlässig und angenehm benutzbar machen.
Der Nutzer prüft Bedienung, Stiftgefühl und Scanner am echten Gerät.
Neue Funktionen oder größere Umbauten nur nach konkreter Anforderung.
Sechs kurze zentrale Projektdateien statt zusätzlicher Planungs-, Prüfbericht-
oder PDF-Sammlungen.
