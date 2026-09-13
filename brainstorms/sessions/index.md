# brainstorms/sessions/ — Session-Handoff-Archiv

Persistiertes Session-Memory. Der Skill `session-handoff` legt hier **pro Session eine Markdown-Datei** ab, damit Wissen `/clear`, Terminal-Absturz und Tage-Pausen überlebt. Beim nächsten Session-Start bietet Claude an, den letzten Handoff wieder zu laden (SessionStart-Hook + CLAUDE.md-Regel).

## Konvention

Dateiname: `YYYY-MM-DD-HHmm-<topic-slug>.md`

Frontmatter (Obsidian-konform):

```yaml
---
type: session-handoff
session-id: <8-Zeichen der Session-UUID>   # verknüpft/entwirrt parallele Sessions
topic: <lesbares Thema>
started: <YYYY-MM-DD HH:mm>
updated: <YYYY-MM-DD HH:mm>
status: status/aktiv          # aktiv | abgeschlossen | blockiert
tags: [thema/<slug>, status/aktiv]
---
```

Body: `# Session Handoff — <Titel>` → Where it started · Decisions+shipped · Key files · Running state · Verification · Deferred+open · **Pick up here**.

## Warum kein index-Katalog wie in anderen Ordnern

Diese `index.md` ist bewusst ein **statischer Guide**, kein gepflegter Katalog. Grund: in einem Projekt laufen oft **mehrere Terminals parallel**. Würde jede Session in eine gemeinsame Index-/Log-Datei schreiben, kollidieren die Writes. Stattdessen ist **jede Handoff-Datei self-describing** (Frontmatter) und der Einstieg läuft dynamisch:

- Neueste zuerst: `ls -t brainstorms/sessions/*.md` bzw. der SessionStart-Hook listet die letzten 3.
- Zu einem Thema: nach `topic:`/`tags:` im Frontmatter greppen.
- Offene Fäden: `grep -l "status/aktiv" brainstorms/sessions/*.md`.

## Parallele Sessions

`HHmm` + `topic-slug` im Dateinamen machen Kollisionen praktisch unmöglich — vier offene Terminals schreiben vier getrennte Dateien. Die `session-id` (aus der Session-UUID) im Frontmatter erlaubt, denselben Faden über mehrere Handoffs derselben Session eindeutig fortzuschreiben (gleiche id → Datei wird geupdatet, nicht dupliziert).

## Vertraulichkeit

`brainstorms/sessions/` wird **committed** (Team-Memory). Der Skill scrubbt vor dem Schreiben Secrets (Keys, Tokens, Passwörter, `.env`-Werte). Wirklich sensibler Kontext, der gebraucht wird, gehört nach `brainstorms/sessions/private/` (gitignored).
