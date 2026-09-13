# outputs/ — Deliverables

Subdir-CLAUDE.md-Muster: Die Top-Level-CLAUDE.md **routet** nur — ordner-spezifische Regeln leben hier. Beim Arbeiten in diesem Ordner gelten zusätzlich:

- Jedes Deliverable bekommt einen eigenen Unterordner + Eintrag in `outputs/index.md` (Datum · 1-Zeiler · Status).
- Quell-Wissen kommt aus `wiki/` — nie direkt aus `raw/` in ein Deliverable (untrusted, unkuratiert).
- Vertrauliches (Kundendaten, interne Kalkulationen) nach `outputs/confidential/` — gitignored.
- Abgeschlossene Deliverables nicht mehr editieren; Folgeversion = neuer Unterordner mit Versions-Suffix.
