# uebungen/: Übungsdateien für Woche 4

Alle Daten hier sind erfunden. Es gibt keine echten Personen, Adressen oder Schlüssel darin.

## Dienstag: Beispiel-JSON verstehen

Datei: `di-abfuhrtermine.json`, die Antwort einer erfundenen Abfuhrkalender-Schnittstelle.

Aufgabe für Claude Code oder Codex:

1. "Erklär mir `uebungen/di-abfuhrtermine.json` so, dass ich es einem Kollegen erklären kann."
2. "Welche Stellen in der Datei würden in einem n8n-Workflow Ärger machen? Nenn jede mit Grund."
3. "Bau mir daraus eine Liste: Straße, Tonne, Datum. Ein Eintrag je Zeile."

Tipp: Achten Sie darauf, ob Claude die unsauberen Stellen findet. Davon gibt es mindestens vier.

## Donnerstag: kaputten Workflow reparieren lassen

Datei: `do-workflow-kaputt.json`, ein kleiner n8n-Workflow. Er soll für jeden Biotonnen-Termin eine Erinnerung formulieren. Am Ende kommt aber keine einzige Erinnerung heraus.

1. Neue Sitzung, Plan-Modus an (Umschalt und Tab). "Der Workflow in `uebungen/do-workflow-kaputt.json` liefert keine Erinnerung. Finde die Ursache, ändere noch nichts."
2. Ursache verstanden? Dann reparieren lassen. Wer n8n hat, importiert die Datei vorher und nachher und vergleicht.
3. Zweite Sitzung mit frischem Kontext als Prüfer: "Prüf die Änderung an `uebungen/do-workflow-kaputt.json`. Ist der Fehler behoben, und ist sonst nichts kaputtgegangen?"
