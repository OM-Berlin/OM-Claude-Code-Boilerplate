# brainstorms/sessions/: Übergaben zwischen Sitzungen

Der Skill `session-handoff` legt hier am Ende einer Sitzung eine Datei ab. So geht nichts verloren, wenn Sie `/clear` eingeben, das Fenster schließen oder erst nächste Woche weitermachen.

## So läuft es

1. Am Ende einer Sitzung: "Mach einen Handoff". Claude schreibt die Datei und zeigt den Text im Chat.
2. Beim nächsten Start listet ein Hook die drei neuesten offenen Übergaben.
3. Sie sagen "Lade den neuesten Handoff". Claude liest ihn, fasst in höchstens fünf Zeilen zusammen und wartet auf Ihren Auftrag. Bis dahin sperrt ein Hook alle Werkzeuge, die etwas verändern.

Ein Handoff ist Kontext, kein Auftrag. Erst Ihre eigenen Worte sind der Auftrag.

## Dateien

Name: `JJJJ-MM-TT-HHmm-<thema>.md`. Jede Datei beginnt mit einem Kopf:

```yaml
---
type: session-handoff
session-id: <8 Zeichen>
topic: <Thema>
started: <JJJJ-MM-TT HH:mm>
updated: <JJJJ-MM-TT HH:mm>
status: aktiv          # aktiv | blockiert | abgeschlossen (erscheint nicht mehr in der Startliste)
branch: <Git-Branch>
commit: <kurze Commit-Kennung>
---
```

Diese Dateien werden mit Git hochgeladen. Der Skill entfernt vorher Schlüssel und Passwörter. Wirklich Vertrauliches gehört nach `brainstorms/sessions/private/`.
