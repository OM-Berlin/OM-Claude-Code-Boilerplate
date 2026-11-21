# Startpaket Claude Code

Dieses Startpaket ist ein leerer Projektordner mit allem, was ein gutes KI-Projekt von Anfang an braucht: eine kurze Regeldatei für die KI, eine feste Ordnerordnung, eine Übergabe zwischen Sitzungen und ein paar Schutzschalter. Es gehört zum Lehrgang der Akademie Dr. Obladen (Woche 4, Agentic Coding) und ist für Claude Code gebaut. Codex, Google Antigravity und Pi können es mitbenutzen, mit Lücken; die stehen im Abschnitt „Welches Programm kann was“.

Es enthält keinen App-Code, keine Zugangsdaten und keine echten Daten. Alles, was Sie bauen, entsteht in diesem Ordner.

## In 10 Minuten startklar

**Sie brauchen:** Claude Code (im Terminal oder in der Desktop-App im Bereich „Code“) oder eines der anderen Programme aus der Tabelle unten, jeweils angemeldet, und Git. Unter Windows installieren Sie dafür „Git für Windows“; es bringt Git Bash mit, das die Hooks brauchen.

**Zusätzlich Python 3:** Zwei der Handoff-Hooks (der Prompt-Wächter und die Schreibsperre) und die Hook-Tests brauchen Python 3. Die Hooks suchen es unter den Namen `python3`, `python` und `py -3` und nehmen den ersten, der wirklich läuft und sich als Python 3 meldet. Unter macOS und Linux ist `python3` meist schon da. Unter Windows installieren Sie Python von python.org. Dort heißt das Programm danach in der Regel `python` oder `py`, nicht `python3`; das reicht, es muss nichts umbenannt werden. Der Platzhalter `python3` aus dem Microsoft Store zählt nicht, er verweist nur auf den Store, und die Hooks überspringen ihn. Ob es klappt, zeigt `python --version` oder `py -3 --version` in Git Bash. Ohne Python 3 setzen die beiden Hooks still aus: Ein geladener Handoff wird dann nicht als bloßer Kontext behandelt, und die Schreibsperre nach dem Laden fehlt. Außerdem überspringt `einrichten.sh` die Hook-Tests. Der Hook gegen gefährliche Befehle, der Formatierer und die Liste offener Handoffs laufen auch ohne Python.

1. **Entpacken.** Entpacken Sie `startpaket-claude-code.zip` und geben Sie dem Ordner einen Namen für Ihr Vorhaben, zum Beispiel `abfuhr-erinnerung`. Legen Sie ihn am besten nicht in einen OneDrive- oder Dropbox-Ordner, weil die Synchronisierung beim Arbeiten stört.
2. **Terminal im Ordner öffnen.** macOS: Rechtsklick auf den Ordner, dann „Dienste“ und „Neues Terminal beim Ordner“. Windows: im Ordner Rechtsklick, dann „In Terminal öffnen“.
3. **Einrichten.** Das Skript legt `.env.local` für Ihre Schlüssel an, beginnt eine eigene Git-Geschichte und prüft die Hooks. Es ändert nichts außerhalb des Ordners.
   ```bash
   bash einrichten.sh                                          # macOS und Linux
   powershell -ExecutionPolicy Bypass -File .\einrichten.ps1   # Windows
   ```
4. **Claude Code starten.** Tippen Sie `claude` (oder `codex`). In der Desktop-App wählen Sie stattdessen den Ordner aus. Bestätigen Sie, dass Sie dem Ordner vertrauen; erst dann laufen die Hooks.
5. **Skills von Matt Pocock installieren.** Claude Code bietet beim ersten Start an, die Skill-Sammlung `mattpocock-skills` zu installieren. Bestätigen Sie das. Kommt keine Frage, geben Sie ein: `/plugin marketplace add mattpocock/skills#4ae2317ddb22b046e26455e4f9c9b3aaaf62212d` und danach `/plugin install mattpocock-skills@mattpocock`. Das braucht Claude Code ab Version 2.1.324 (`claude --version`); warum, steht im Abschnitt „Skills von Matt Pocock“.
6. **Prüfen.** Geben Sie `/hooks` ein. Dort sollten die fünf Hooks aus dem Abschnitt „Die Hooks“ stehen.
7. **Regeldatei ausfüllen lassen.** Schreiben Sie: „Frag mich mit dem Skill grilling zu meinem Vorhaben aus und füll danach CLAUDE.md aus. Bleib unter 60 Zeilen.“

Danach geht es mit den Übungen in `uebungen/index.md` weiter.

**Ohne Abo:** Laden Sie `CLAUDE.md` und die Dateien aus `uebungen/` in einen KI-Chat hoch und stellen Sie dieselben Fragen. Hooks und Skills gibt es dort nicht, die Übungen funktionieren trotzdem.

## Was im Paket steckt

```
CLAUDE.md            Regeldatei. Claude liest sie bei jedem Start. Vorlage mit Platzhaltern
AGENTS.md            Zeiger auf CLAUDE.md für Codex, Antigravity und Pi
README.md            diese Anleitung
einrichten.sh/.ps1   einmal ausführen nach dem Entpacken
.env.example         Namen möglicher Schlüssel, ohne Werte. Echte Werte nur in .env.local
.gitignore           was Git nie hochlädt, vor allem Schlüssel
raw/                 fremdes Material, nur lesen, wird nicht hochgeladen
wiki/                geprüftes Wissen, das Sie später nachschlagen (Vorlage: _vorlage.md)
brainstorms/         Überlegungen und Pläne; sessions/ enthält die Übergaben
decisions/log.md     Entscheidungen mit Datum, nur unten anhängen
projects/            die eigentliche Arbeit, ein Ordner je Vorhaben
outputs/             fertige Ergebnisse
uebungen/            erfundene Übungsdateien für Dienstag und Donnerstag
.claude/             Einstellungen, Hooks und der Skill session-handoff für Claude Code
.codex/              Hooks für Codex
.agents/             der Skill session-handoff für Codex, Antigravity und Pi, Hooks für Antigravity
.pi/                 Erweiterung für Pi, die gefährliche Befehle sperrt
.obsidian/           eine Einstellung für Obsidian: normale Markdown-Links
```

## Die Hooks

Ein Hook ist ein kleines Programm, das Claude Code bei einem bestimmten Ereignis selbst startet, zum Beispiel vor jedem Befehl. Anders als eine Regel in `CLAUDE.md` läuft ein Hook jedes Mal und kann nicht vergessen werden. Alle Hooks liegen in `.claude/hooks/` und sind in `.claude/settings.json` eingehängt.

| Hook | Wann | Was er tut |
|---|---|---|
| `block-dangerous-commands.sh` | vor Bash, Read und Grep | Er sperrt `rm -rf` auf `/` oder den Home-Ordner, `git push --force` auf main, `git reset --hard` und das Lesen von `.env`-Dateien. Dafür endet er mit Exitcode 2; Claude Code bricht den Befehl ab, Claude liest den Grund und sucht einen anderen Weg. |
| `list-recent-handoffs.sh` | beim Start | Er zeigt die drei neuesten offenen Übergaben aus `brainstorms/sessions/`. So sehen Sie und Claude sofort, wo die letzte Sitzung aufgehört hat. |
| `handoff-offer-guard.sh` | bei jeder Nachricht | Er erkennt, ob Sie nur einen Handoff laden oder einen echten Auftrag geben. Lädt jemand nur den Handoff, bittet er Claude um ein kurzes Fazit statt um Arbeit. |
| `handoff-briefing-gate.sh` | vor jedem Werkzeug | Nach dem bloßen Laden eines Handoffs erlaubt er nur Lese-Werkzeuge. Ihre nächste Nachricht hebt die Sperre auf, damit Claude nicht von selbst mit dem „nächsten Schritt“ loslegt. |
| `format-after-edit.sh` | nach jeder Dateiänderung | Er formatiert die geänderte Datei, wenn das Projekt Prettier (lokal in `node_modules`) oder Ruff (mit `pyproject.toml`) mitbringt. Ohne Formatierer tut er nichts und lädt auch nichts nach. |

**Selbst ausprobieren:**

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"git reset --hard"}}' \
  | bash .claude/hooks/block-dangerous-commands.sh; echo "Exitcode: $?"
```

Das ergibt die Sperrmeldung und `Exitcode: 2`. Mit `git status` statt `git reset --hard` ist der Exitcode 0.

**Alle Tests:** `bash .claude/hooks/tests/run-all.sh`. Jeder Hook hat dort eine eigene Testdatei.

**Wächter für die Regeldateien:** Derselbe Lauf prüft auch `CLAUDE.md`, `AGENTS.md` und `README.md` (Testdatei `test-claude-md-guard.sh`). Er schlägt an, wenn eine `CLAUDE.md` zu lang wird (Wurzel 4000 Zeichen, andere Ordner 2500), neben einer `CLAUDE.md` die `AGENTS.md` fehlt, nicht auf sie zeigt oder eigene Regeln enthält (über 600 Zeichen), der Wurzel-`AGENTS.md` die Zeile für Antigravity fehlt, eine `CLAUDE.md` einen Pfad in Backticks nennt, den es nicht gibt, oder ein ausgemusterter Werkzeugname auftaucht. Jede Meldung sagt, was Sie ändern müssen. So bleibt die Regeldatei kurz und stimmt mit dem Ordner überein.

**Abschalten:** Den passenden Eintrag aus `.claude/settings.json` löschen. Die Übergabe-Liste allein schalten Sie mit `"env": { "HANDOFF_HINWEIS": "aus" }` in derselben Datei ab.

Wichtig: Die Hooks sind eine Bremse gegen Versehen, keine Sicherheitsgrenze. Wer will, kommt mit Umwegen daran vorbei. Echte Geheimnisse gehören deshalb gar nicht erst in den Projektordner, sondern nur in `.env.local`.

## Welches Programm kann was

Das Paket ist für Claude Code gebaut. Die Regeln stehen nur in `CLAUDE.md`. Die anderen Programme lesen zuerst `AGENTS.md`, einen kurzen Zeiger, der sie auffordert, `CLAUDE.md` vollständig zu lesen. Google Antigravity bindet `CLAUDE.md` über die Zeile `@[CLAUDE.md](./CLAUDE.md)` sogar direkt ein. Den Skill `session-handoff` gibt es zweimal mit gleichem Inhalt: in `.claude/skills/` für Claude Code und in `.agents/skills/` für die anderen.

| Programm | Regeln | Skill `session-handoff` | Schutz-Hooks | Geprüft am 21.11.2026 |
|---|---|---|---|---|
| Claude Code 2.1.328 | `CLAUDE.md` direkt | ja | alle fünf | Tests grün; Probelauf nicht möglich, weil das Nutzungslimit erreicht war |
| Codex CLI 0.171.0 | liest den Zeiger, öffnet dann `CLAUDE.md` selbst | ja | Übergabe-Liste beim Start, Sperre gefährlicher Befehle | Probelauf: Regel und Skill gefunden; Hooks nur mit Testdaten geprüft |
| Google Antigravity | `CLAUDE.md` über den Zeiger eingebunden | ja | Übergabe-Liste beim Start, Sperre gefährlicher Befehle, Lesen und Suchen in `.env` | nur mit Testdaten aus der Doku; die Antigravity-CLI war nicht installiert |
| Pi 1.1.0 | liest den Zeiger, öffnet dann `CLAUDE.md` selbst | ja, nach Freigabe des Ordners | nur die Sperre gefährlicher Befehle, nach Freigabe des Ordners | Probelauf: Regel gefunden, Sperre wirkt |

Was Sie wissen sollten:

- **Nur in Claude Code:** der Prompt-Wächter und die Schreibsperre nach dem Laden eines Handoffs, der Formatierer und die Sperre des Modus ohne Rückfragen.
- **Codex** startet Hooks aus `.codex/hooks.json` erst, wenn Sie dem Ordner vertrauen und die Hooks mit `/hooks` freigeben.
- **Pi** fragt vor Befehlen nicht nach; es hat kein Berechtigungssystem. Die Erweiterung `.pi/extensions/schutz-hooks.ts` lädt Pi erst, wenn Sie dem Ordner vertrauen (Frage beim Start oder `/trust`). Ohne diese Freigabe läuft Pi ganz ohne Schutz. Nutzen Sie Pi deshalb nur in einem Ordner ohne Geheimnisse.
- **Windows:** Die Hooks für Codex, Antigravity und Pi sind nur unter macOS geprüft.
- Die **Gemini CLI** ist ein anderes Programm als Antigravity. Sie liest in der getesteten Version 0.19.4 weder `AGENTS.md` noch Skills von selbst und gehört nicht zum Paket.

## Übergaben zwischen Sitzungen

Am Ende einer Sitzung sagen Sie „Mach einen Handoff“. Der Skill `session-handoff` schreibt dann eine Übergabe nach `brainstorms/sessions/` und zeigt sie im Chat. Danach können Sie `/clear` eingeben oder den Rechner ausschalten. Beim nächsten Start sagen Sie „Lade den neuesten Handoff“: Claude liest ihn, fasst ihn kurz zusammen und wartet auf Ihren Auftrag. Mehr dazu in `brainstorms/sessions/index.md`.

## Skills von Matt Pocock

Aus der Sammlung `mattpocock-skills` nutzt das Paket `grilling`, `diagnosing-bugs`, `tdd` und `code-review`. In `.claude/settings.json` ist die Sammlung mit `ref` auf einen festen Stand gelegt: den Commit `4ae2317`, Version 1.3.2. So ändern sich die Skills während des Lehrgangs nicht von selbst. Claude Code kann einen solchen Commit-Stand erst ab Version 2.1.324 lesen.

Die Festlegung greift nur, wenn Claude Code die Sammlung zum ersten Mal einträgt. Wer sie schon früher ohne Festlegung eingetragen hat, behält seinen Stand. Auf einen neueren Stand wechseln Sie so: Suchen Sie auf github.com/mattpocock/skills den Commit der gewünschten Version, tragen Sie seine volle Kennung (40 Zeichen) in `.claude/settings.json` bei `ref` ein, geben Sie in Claude Code `/plugin marketplace remove mattpocock` ein und starten Sie Claude Code neu. Dann bietet es die Installation wieder an.

## CLAUDE.md gesund halten

- **Wächter:** `bash .claude/hooks/tests/run-all.sh` startet auch `test-claude-md-guard.sh` (Abschnitt „Die Hooks“). Lassen Sie den Lauf nach jeder Änderung an `CLAUDE.md` laufen.
- **`/doctor`** in Claude Code prüft die Einrichtung und schlägt vor, Zeilen aus `CLAUDE.md` zu streichen, die Claude ohnehin aus den Dateien erschließen kann.
- **`/doctor prompt-audit`** sucht veraltete oder widersprüchliche Anweisungen und Verweise auf Dateien, die es nicht gibt. Es ändert nichts, bevor Sie zustimmen.
- **`/context`** zeigt, ob `CLAUDE.md` in der Sitzung wirklich geladen ist.
- **Optional:** Das Plugin `claude-md-management` von Anthropic (`/plugin install claude-md-management@claude-plugins-official`) bringt den Skill `claude-md-improver` und den Befehl `/revise-claude-md` mit. Es ist nicht vorinstalliert.

## Wiki und Obsidian

Das Wiki in `wiki/` folgt dem Open Knowledge Format (OKF) 0.3, einem offenen Format für Wissen aus Markdown-Dateien. Jede Seite beginnt mit einem Kopf zwischen zwei Zeilen `---` (Frontmatter), darin mindestens `type`. `wiki/_vorlage.md` zeigt alle Felder, `wiki/index.md` listet die Seiten, `wiki/log.md` hält die Änderungen fest, das neueste Datum oben. Die Testdatei `test-wiki-okf.sh` prüft das bei jedem Testlauf. Ausführlicher prüft auf Wunsch der Prüfer des OKF-Projekts (`skills/okf-generate/scripts/validate.py` auf github.com/open-knowledge-format/open-knowledge-format); er braucht das Python-Paket PyYAML und liegt nicht im Paket.

Sie können den ganzen Ordner in Obsidian als Vault (Notizsammlung) öffnen. Die Datei `.obsidian/app.json` sorgt dafür, dass Obsidian normale Markdown-Links mit relativem Pfad schreibt statt Wikilinks mit doppelten eckigen Klammern, die andere Programme nicht verstehen. Für Agenten, die mit Obsidian-Dateien arbeiten sollen, gibt es offizielle Skills auf github.com/obsidianmd/obsidian-skills; sie sind nicht installiert.

## Best Practices

- **CLAUDE.md kurz halten.** Hinein gehört nur, was Claude nicht selbst aus den Dateien erschließen kann: Wissen über das Projekt, Ihre Vorlieben, Schutzregeln, die wichtigsten Befehle. Jede Zeile kostet in jeder Sitzung Aufmerksamkeit; eine lange Datei befolgt Claude schlechter als eine kurze.
- **Hooks statt Regeln, wo es prüfbar ist.** Lässt sich eine Regel mechanisch prüfen („nie `.env` lesen“, „Code immer formatieren“), bauen Sie einen Hook. Regeln in `CLAUDE.md` sind für Dinge, die Urteilsvermögen brauchen.
- **Erst fragen lassen, dann bauen.** Bei einem neuen Vorhaben fragt Sie der Skill `grilling` aus, bis das Ziel klar ist. Für größere Änderungen schalten Sie vorher den Plan-Modus ein (Umschalt und Tab).
- **Handoff vor `/clear`.** `/clear` leert das Gedächtnis der Sitzung. Schreiben Sie vorher einen Handoff, dann geht nichts verloren.
- **Prüfen lässt eine frische Sitzung.** Wer etwas gebaut hat, übersieht die eigenen Fehler. Öffnen Sie für die Prüfung eine neue Sitzung ohne Vorgeschichte und lassen Sie dort das Ergebnis prüfen, zum Beispiel mit dem Skill `code-review`.
- **Zurückspulen statt reparieren.** Ist Claude in eine falsche Richtung gelaufen, springen Sie mit `/rewind` zu einem früheren Stand zurück.
- **Berechtigungen bewusst wählen.** Im Standard fragt Claude vor jeder Änderung. Mit Umschalt und Tab wechseln Sie zu „Änderungen automatisch annehmen“ oder zum Plan-Modus. Mit `/permissions` sehen und ändern Sie, was Claude ohne Rückfrage darf. Den Modus, der alle Rückfragen abschaltet, sperrt dieses Paket in `.claude/settings.json`.
- **Schlüssel nur in `.env.local`.** Nie in den Chat, nie in eine andere Datei.

## Welches Modell?

Stand November 2026: Opus als Standard, Fable für die härtesten Aufgaben, Sonnet und Haiku für einfache. Wählen Sie immer die aktuelle Version der jeweiligen Stufe. Das Modell wechseln Sie mit `/model`. Fable verbraucht deutlich mehr von Ihrem Nutzungskontingent; nehmen Sie es nur, wenn Opus nicht weiterkommt.

## Was sich seit September geändert hat

Die erste Fassung dieses Pakets gab es zum Workshop im September 2026. Für den Lehrgang ist sie überarbeitet:

- **Kein Kurzstil-Plugin mehr.** Das Plugin aus der Septemberfassung ließ Claude im Telegrammstil antworten. Stattdessen steht in `CLAUDE.md` eine Sprachregel für klare, vollständige Sätze.
- **Neue CLAUDE.md.** Sie ist eine Vorlage mit Platzhaltern, deutlich unter 60 Zeilen, mit einem Kommentar, was hinein gehört und was nicht.
- **Neuer Schutz-Hook** gegen gefährliche Befehle und gegen das Lesen von `.env`-Dateien.
- **Neuer Formatier-Hook**, der nur arbeitet, wenn das Projekt einen Formatierer hat.
- **Übergaben sind Briefings, keine Aufträge.** Ein neuer Hook sperrt nach dem bloßen Laden eines Handoffs alle verändernden Werkzeuge, bis Sie antworten. Die Startliste zeigt nur offene Übergaben, die zuletzt bearbeitete zuerst.
- **Weniger Ballast.** Der Stop-Hook `run-gate`, die Wiki-Werkzeuge und der Ordner `assets/` sind entfallen.
- **Wiki im offenen Format OKF 0.3** mit Vorlage und Prüfung; Obsidian schreibt normale Markdown-Links.
- **Übungsdateien** für Dienstag und Donnerstag liegen in `uebungen/`.
- **Sicherer Standard:** Der Modus ohne Rückfragen ist gesperrt, und `einrichten.sh` prüft die Hooks mit ihren Tests.
- **Vier Programme:** Codex, Antigravity und Pi lesen dieselben Regeln und denselben Handoff-Skill; die Übergabe-Liste und die Sperre gefährlicher Befehle laufen auch dort (Tabelle oben).
- **Feste Skill-Version:** Die Skills von Matt Pocock sind auf Version 1.3.2 festgelegt.

## Woher das kommt

Die Trennung `raw/` → `wiki/` → `CLAUDE.md` folgt Andrej Karpathys [LLM-Wiki-Muster](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f). Die Skills `grilling`, `diagnosing-bugs`, `tdd` und `code-review` stammen von [Matt Pocock](https://github.com/mattpocock/skills). Die Hinweise zu Regeldatei und Hooks folgen der [Dokumentation von Claude Code](https://code.claude.com/docs/en/best-practices).

## Kontakt

Fragen zum Lehrgang stellen Sie über die Lernplattform oder über [obladen-akademien.de](https://www.obladen-akademien.de).
