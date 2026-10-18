# Arbeitsregeln für Openote

- Einstieg: README.md. Produktumfang in PRODUCT.md, Aufbau in ARCHITECTURE.md,
  offene Arbeit in TASKS.md und bekannte Stolperstellen in LEARNINGS.md nachlesen,
  soweit sie zur Aufgabe passen. Der aktuelle Code ist die technische Wahrheit.
- Windows-App und Android-Scanner bleiben gemeinsam im Repository. Bestehende
  Funktionen, Notizformate, unbekannte Blöcke, Sicherungen und QR-Übertragung erhalten.
- Kleine, gezielte Änderungen bevorzugen. Vorhandene lokale Änderungen erhalten.
  Keine globalen SDK-/Pub-Cache-Patches und keine pauschalen Paketupdates.
- Projektwissen ausschließlich in diesen sechs zentralen Markdown-Dateien pflegen.
  Kurz und aktuell halten; keine zusätzlichen Berichte, Handbücher oder Planarchive.
  Lizenztexte, Fremdcode-Dokumente und notwendige Testdaten sind Ausnahmen.
- Passende Analyse und aussagekräftige Tests ausführen. Funktionale Regressionstests
  behalten; Fehler nicht durch Löschen oder Abschwächen von Tests verstecken.
  Für reine Dokumentationsänderungen keine vollständige Testsuite starten.
  Manuelle Geräte- und Bedienprüfungen übernimmt der Nutzer.
- Flutter-Befehle im jeweiligen Paket app/ oder scanner/ ausführen.
  Für Windows-Buildprobleme zuerst LEARNINGS.md und die lokalen Overrides prüfen.
- Kein Push und kein Release ohne ausdrücklichen Nutzerauftrag. Der bestehende
  GitHub-Workflow veröffentlicht bei Branch-Pushes automatisch; beachten.
- Keine Schlüssel, persönlichen Notizen oder lokalen Testdaten einchecken.
