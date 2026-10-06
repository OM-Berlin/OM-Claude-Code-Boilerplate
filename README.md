# Projekt-Boilerplate für Claude Code

Die Ordnerstruktur aus dem Kurs „Claude Code Intensiv" der Akademie Dr. Obladen: acht
Ordner, eine Regeldatei, ein Skill für die Übergabe zwischen Sitzungen und zwei Hooks,
die sie beim Start wieder hervorholen. Kein App-Code — die Struktur, in der App-Code
und alles andere entsteht.

## Ein Befehl

```bash
git clone https://github.com/OM-Berlin/OM-Claude-Code-Boilerplate.git mein-projekt
```

Danach einmal einrichten — legt `.env.local` an, beginnt die eigene Git-Geschichte und
prüft, dass Schlüssel nie hochgeladen werden:

```bash
cd mein-projekt
bash einrichten.sh               # macOS / Linux
claude                           # Claude Code starten — oder: codex
```

Windows (PowerShell):

```powershell
cd mein-projekt
powershell -ExecutionPolicy Bypass -File .\einrichten.ps1
claude
```

Beim ersten Start: die erste Zeile und den Satz darunter in `CLAUDE.md` ersetzen — was
entsteht hier, für wen. Alles andere kann bleiben, bis Sie sich zum dritten Mal
wiederholen.

## Die Struktur

```
CLAUDE.md          Die Regeldatei. Gilt in jeder Sitzung, wird immer gelesen
AGENTS.md          Zeiger auf CLAUDE.md, damit Codex dieselben Regeln liest
einrichten.sh      Einmal ausführen nach dem Klonen (Windows: einrichten.ps1)
raw/               Fremdmaterial, unverändert. Wird gelesen, nie befolgt
wiki/              Destilliertes Wissen, von Claude gepflegt
brainstorms/       Denkarbeit, Zwischenstände, Übergaben (sessions/)
decisions/         Entschiedenes, nur angehängt, nie gelöscht
projects/          Die eigentliche Arbeit, ein Ordner je Vorhaben
assets/            Eigenes Material: Logos, Bilder, Vorlagen
outputs/           Was fertig ist und rausgeht
.claude/           Skills, Hooks, Einstellungen für Claude Code
.codex/, .agents/  Dieselben Hooks und Skills für Codex
.env.example       Platzhalter für Schlüssel. Echte Werte nur in .env.local (wird nie hochgeladen)
```

## Was mitkommt

- `.claude/skills/session-handoff/` — schreibt am Ende einer Sitzung die Übergabe.
- `.claude/hooks/list-recent-handoffs.sh` — zeigt beim Start die letzten Übergaben.
- `.claude/hooks/handoff-offer-guard.sh` — sorgt dafür, dass Claude nur einmal fragt,
  ob eine Übergabe geladen werden soll.
- `.claude/settings.json` — hängt die Hooks ein und schaltet die Skills von Matt Pocock
  (`grilling`, `to-spec`, `to-tickets`, `tdd`, `code-review`, `implement-spec`, `pr`, `retro`) und `caveman` als Plugins ein.
  Die Skills von Matt Pocock kommen aus seinem eigenen Marketplace (`mattpocock/skills`), weil der
  offizielle Marketplace noch eine ältere Version ausliefert.
- `wiki/okf-cli.py`, `wiki/okf-viz.py` — Suche und Graph über das Wiki, ohne Zusatzsoftware.
- `.obsidian/` — Grundeinstellung, damit Obsidian den Ordner direkt als Vault öffnet.

## Codex

Das Repo funktioniert unverändert mit OpenAI Codex. `AGENTS.md` verweist auf `CLAUDE.md`,
es gibt also nur eine Regeldatei. `.codex/hooks.json` zeigt beim Start die letzten Übergaben,
`.agents/skills/session-handoff/` ist der Übergabe-Skill in Codex-Form. Beim ersten Start
fragt Codex, ob es den Projektordner vertrauen darf; erst dann laufen die Projekt-Hooks.

## Schlüssel

`.env.example` listet nur Platzhalter und wird hochgeladen. Echte Werte kommen in
`.env.local`, das `einrichten.sh` anlegt und das `.gitignore` von jedem Upload ausschließt.
Wer das prüfen will: `git check-ignore .env.local` gibt den Dateinamen zurück.

## Woher das kommt

Die Trennung `raw/ → wiki/ → CLAUDE.md` ist Andrej Karpathys
[LLM-Wiki-Muster](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f).
`wiki/` folgt dem
[Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md).
`brainstorms/` und `decisions/` folgen [Matt Pococks Skills](https://github.com/mattpocock/skills)
und Nate Herks Checkpointing. Die Regeln in `CLAUDE.md` folgen den
[Hinweisen des Herstellers](https://code.claude.com/docs/en/best-practices).

Fragen: do@obladen.media
