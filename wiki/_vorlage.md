---
type: Vorlage
title: Vorlage für neue Seiten
description: Muster für eine Wiki-Seite mit allen Kopf-Feldern; kopieren, umbenennen, ausfüllen.
tags: [vorlage]
sources:
  - id: okf
    resource: https://github.com/open-knowledge-format/open-knowledge-format/blob/main/SPEC.md
    title: Open Knowledge Format, Version 0.3
generated: { by: "team:akademie-dr-obladen", at: "2026-11-21T12:00:00Z" }
status: stable
---

# Worum es geht

Ein bis drei Sätze: Was steht auf dieser Seite, und wann braucht man sie?

# Das Wichtigste

Hier steht das Wissen selbst, kurz und in eigenen Worten. Stammt eine Aussage aus einer Quelle, bekommt sie eine Fußnote mit der `id` der Quelle aus dem Kopf.[^okf]

Verweise auf andere Seiten sind normale Markdown-Links, zum Beispiel auf die [Übersicht](index.md).

# So füllen Sie den Kopf aus

- `type` (Pflicht): die Art der Seite, frei wählbar, zum Beispiel `Begriff`, `Ablauf`, `Ansprechstelle` oder `Entscheidung`.
- `title` und `description`: Name der Seite und ein Satz, worum es geht. Den Satz übernehmen Sie in `index.md`.
- `tags`: Stichwörter in eckigen Klammern, zum Beispiel `[abfuhr, termine]`.
- `sources`: je Quelle ein Eintrag mit `id` (kurzer Name für die Fußnote), `resource` (Link oder Pfad) und `title`.
- `generated`: wer den Text geschrieben hat und wann. Menschen schreiben `human:<kürzel>`, Claude schreibt `claude-code/<version>`.
- `verified`: wer den Text geprüft hat, zum Beispiel `verified: { by: "human:<kürzel>", at: "2026-12-01T09:00:00Z" }`. Als von Menschen geprüft gilt eine Seite nur mit `human:` und nur, wenn die Prüfung nach der letzten Änderung lag.
- `status`: `draft` (Entwurf), `stable` (fertig) oder `deprecated` (veraltet, bleibt für alte Links stehen).

Danach: eine Zeile in `index.md` und ein Eintrag in `log.md` unter dem heutigen Datum.

[^okf]: Open Knowledge Format, Version 0.3
