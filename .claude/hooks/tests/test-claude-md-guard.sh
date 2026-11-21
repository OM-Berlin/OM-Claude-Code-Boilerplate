#!/usr/bin/env bash
# Wächter für die Regeldateien: Er prüft CLAUDE.md, AGENTS.md und README.md im
# ganzen Projekt und schlägt an, wenn
#   (a) eine CLAUDE.md zu lang ist (Wurzel: 4000 Zeichen, jede andere: 2500; eine Zahl
#       in .claude/hooks/tests/claude-md-budget.txt ersetzt die 4000 für die Wurzel),
#   (b) neben einer CLAUDE.md die AGENTS.md fehlt, nicht auf CLAUDE.md zeigt oder mehr
#       als ein Zeiger ist (über 600 Zeichen), oder der AGENTS.md in der Wurzel die
#       Zeile @[CLAUDE.md](./CLAUDE.md) fehlt, mit der Google Antigravity CLAUDE.md einbindet,
#   (c) eine CLAUDE.md einen Pfad in Backticks nennt, den es nicht gibt,
#   (d) eine der drei Dateien einen ausgemusterten Namen enthält.
# Warum: Eine lange oder veraltete CLAUDE.md kostet bei jeder Sitzung Aufmerksamkeit
# und verleitet Claude zu Fehlern. Der Wächter hält sie kurz und wahr.
# Der zweite Teil dieser Datei prüft den Wächter selbst mit absichtlich kaputten Mustern.
# Lauf: bash .claude/hooks/tests/test-claude-md-guard.sh
# bash 3.2 kompatibel (macOS).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

MAX_ROOT=4000
BUDGET_FILE="$ROOT/.claude/hooks/tests/claude-md-budget.txt"
if [ -f "$BUDGET_FILE" ]; then
  MAX_ROOT="$(tr -cd '0-9' < "$BUDGET_FILE")"
  [ -n "$MAX_ROOT" ] || { echo "FAIL: $BUDGET_FILE enthält keine Zahl"; exit 1; }
fi
MAX_OTHER=2500
MAX_AGENTS=600
INCLUDE='@[CLAUDE.md](./CLAUDE.md)'
RETIRED='caveman|context-mode|superpowers|claude-mem'
# Dateien, die erst beim Einrichten entstehen und deshalb im Startpaket fehlen dürfen.
CREATED_BY_SETUP=".env .env.local"

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; }

# Zeichen, nicht Bytes: Fortsetzungsbytes von UTF-8 (0x80-0xBF) zählen nicht mit.
chars() { LC_ALL=C tr -d '\200-\277' < "$1" | wc -c | tr -d ' '; }

# find_files <root> <name>: Dateien dieses Namens, ohne .git, node_modules und dist.
find_files() {
  find "$1" \( -name .git -o -name node_modules -o -name dist \) -prune -o -type f -name "$2" -print 2>/dev/null | sort
}

# Pfade in Backticks, ohne Codeblöcke (```), einer pro Zeile.
backtick_spans() {
  awk '/^[ \t]*```/ { fenced = !fenced; next } !fenced' "$1" | grep -o '`[^`]*`' | sed 's/^`//; s/`$//'
}

# Soll dieser Text als Pfad geprüft werden? Platzhalter, ~, absolute Pfade und Links nicht.
is_checkable_path() {
  case "$1" in
    ""|*[[:space:]]*|"~"*|/*|http*|-*|*"<"*|*">"*|*"{"*|*"}"*|*"*"*|*"$"*|*"|"*|*"="*|*":"*|*"("*|*")"*|*"\\"*) return 1 ;;
  esac
  case "$1" in
    */*) return 0 ;;
  esac
  printf '%s' "$1" | grep -qE '^[A-Za-z0-9._-]+\.[A-Za-z][A-Za-z0-9]*$'
}

# check_repo <root>: schreibt pro Befund eine Zeile auf stdout.
check_repo() {
  local root="$1" f dir rel n max span path w known c
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    dir="$(dirname "$f")"; rel="${f#"$root"/}"
    if [ "$dir" = "$root" ]; then max=$MAX_ROOT; else max=$MAX_OTHER; fi
    n="$(chars "$f")"
    if [ "$n" -gt "$max" ]; then
      echo "$rel ist zu lang: $n Zeichen, erlaubt sind $max. Kürzen Sie die Datei oder lagern Sie Details nach wiki/ oder decisions/ aus."
    fi
    if [ ! -f "$dir/AGENTS.md" ]; then
      echo "Neben $rel fehlt die AGENTS.md. Legen Sie sie an; sie soll nur auf CLAUDE.md im selben Ordner zeigen."
    elif ! grep -q 'CLAUDE\.md' "$dir/AGENTS.md"; then
      echo "${rel%CLAUDE.md}AGENTS.md erwähnt CLAUDE.md nicht. Sie soll nur auf die CLAUDE.md im selben Ordner zeigen."
    else
      n="$(chars "$dir/AGENTS.md")"
      [ "$n" -gt "$MAX_AGENTS" ] &&
        echo "${rel%CLAUDE.md}AGENTS.md ist mit $n Zeichen mehr als ein Zeiger (erlaubt sind $MAX_AGENTS). Regeln gehören nur in CLAUDE.md."
      [ "$dir" = "$root" ] && ! grep -qF "$INCLUDE" "$dir/AGENTS.md" &&
        echo "AGENTS.md fehlt die Zeile $INCLUDE. Ohne sie bindet Google Antigravity CLAUDE.md nicht ein."
    fi
    while IFS= read -r span; do
      is_checkable_path "$span" || continue
      path="${span%%#*}"
      known=0
      for c in $CREATED_BY_SETUP; do [ "$path" = "$c" ] && known=1; done
      [ "$known" = 1 ] && continue
      if [ ! -e "$dir/$path" ] && [ ! -e "$root/$path" ]; then
        echo "$rel nennt den Pfad \`$span\`, aber es gibt ihn nicht. Korrigieren Sie den Pfad oder entfernen Sie den Verweis."
      fi
    done <<EOF
$(backtick_spans "$f")
EOF
  done <<EOF
$(find_files "$root" CLAUDE.md)
EOF
  for name in CLAUDE.md AGENTS.md README.md; do
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      rel="${f#"$root"/}"
      for w in $(grep -i -o -E "$RETIRED" "$f" | tr 'A-Z' 'a-z' | sort -u); do
        echo "$rel enthält den ausgemusterten Namen '$w'. Entfernen Sie ihn oder ersetzen Sie ihn durch das, was heute gilt."
      done
    done <<EOF
$(find_files "$root" "$name")
EOF
  done
}

# --- 1. Das echte Projekt ---
real="$(check_repo "$ROOT")"
if [ -z "$real" ]; then
  ok
else
  bad "Regeldateien verletzen den Wächter:"
  printf '%s\n' "$real" | sed 's/^/      - /'
fi

# --- 2. Der Wächter selbst: kaputte Muster müssen anschlagen, saubere nicht ---
fixture() { rm -rf "$WORK/fx"; mkdir -p "$WORK/fx/unter" "$WORK/fx/docs"; echo "$WORK/fx"; }
clean_fx() { # saubere Grundlage mit allem, was der Wächter prüft
  local fx; fx="$(fixture)"
  printf '# Regeln\n\nSiehe `docs/info.md` und `unter/`.\n' > "$fx/CLAUDE.md"
  printf 'Zeigt auf CLAUDE.md.\n\n%s\n' "$INCLUDE" > "$fx/AGENTS.md"
  printf '# Unter\n' > "$fx/unter/CLAUDE.md"
  printf 'Zeigt auf CLAUDE.md.\n' > "$fx/unter/AGENTS.md"
  echo "info" > "$fx/docs/info.md"
  echo "# Lies mich" > "$fx/README.md"
  echo "$fx"
}
filler() { head -c "$1" /dev/zero | tr '\0' 'a'; }
expect_hit() { # expect_hit <name> <fx> <teil der meldung>
  local out; out="$(check_repo "$2")"
  case "$out" in *"$3"*) ok ;; *) bad "Wächter schlägt nicht an: $1" "erwartet '$3', bekommen: ${out:-nichts}" ;; esac
}
expect_clean() { # expect_clean <name> <fx>
  local out; out="$(check_repo "$2")"
  [ -z "$out" ] && ok || bad "Wächter schlägt zu Unrecht an: $1" "$out"
}

fx="$(clean_fx)"; expect_clean "saubere Grundlage" "$fx"

# (a) Länge
fx="$(clean_fx)"; { printf '# R\n'; filler $((MAX_ROOT - 4)); } > "$fx/CLAUDE.md"
expect_clean "Wurzel genau $MAX_ROOT Zeichen" "$fx"
fx="$(clean_fx)"; { printf '# R\n'; filler $((MAX_ROOT - 3)); } > "$fx/CLAUDE.md"
expect_hit "Wurzel $((MAX_ROOT + 1)) Zeichen" "$fx" "CLAUDE.md ist zu lang"
fx="$(clean_fx)"; { printf '# U\n'; filler $((MAX_OTHER - 4)); } > "$fx/unter/CLAUDE.md"
expect_clean "Unterordner genau $MAX_OTHER Zeichen" "$fx"
fx="$(clean_fx)"; { printf '# U\n'; filler $((MAX_OTHER - 3)); } > "$fx/unter/CLAUDE.md"
expect_hit "Unterordner $((MAX_OTHER + 1)) Zeichen" "$fx" "unter/CLAUDE.md ist zu lang"
fx="$(clean_fx)"; { printf '# U\n'; for i in $(seq 1 2000); do printf 'ä'; done; } > "$fx/unter/CLAUDE.md"
expect_clean "Umlaute zählen als ein Zeichen (2000 Zeichen, 4000 Bytes)" "$fx"

# (b) AGENTS.md
fx="$(clean_fx)"; rm "$fx/AGENTS.md"
expect_hit "AGENTS.md fehlt in der Wurzel" "$fx" "Neben CLAUDE.md fehlt die AGENTS.md"
fx="$(clean_fx)"; rm "$fx/unter/AGENTS.md"
expect_hit "AGENTS.md fehlt im Unterordner" "$fx" "Neben unter/CLAUDE.md fehlt die AGENTS.md"
fx="$(clean_fx)"; echo "Eigener Inhalt." > "$fx/unter/AGENTS.md"
expect_hit "AGENTS.md ohne Verweis" "$fx" "unter/AGENTS.md erwähnt CLAUDE.md nicht"
fx="$(clean_fx)"; { printf 'Zeigt auf CLAUDE.md.\n'; filler "$MAX_AGENTS"; } > "$fx/unter/AGENTS.md"
expect_hit "AGENTS.md mit eigenem Inhalt" "$fx" "unter/AGENTS.md ist mit"
fx="$(clean_fx)"; printf 'Zeigt auf CLAUDE.md.\n' > "$fx/AGENTS.md"
expect_hit "AGENTS.md ohne Antigravity-Zeile" "$fx" "AGENTS.md fehlt die Zeile"

# (c) Pfade in Backticks
fx="$(clean_fx)"; printf '# R\n\nSiehe `docs/fehlt.md`.\n' > "$fx/CLAUDE.md"
expect_hit "Pfad mit Ordner fehlt" "$fx" 'nennt den Pfad `docs/fehlt.md`'
fx="$(clean_fx)"; printf '# R\n\nSiehe `notiz.txt`.\n' > "$fx/CLAUDE.md"
expect_hit "Dateiname ohne Ordner fehlt" "$fx" 'nennt den Pfad `notiz.txt`'
fx="$(clean_fx)"; echo "lokal" > "$fx/unter/lokal.md"
printf '# U\n\nSiehe `lokal.md` und `docs/info.md`.\n' > "$fx/unter/CLAUDE.md"
expect_clean "Pfad relativ zur Wurzel oder zum eigenen Ordner" "$fx"
fx="$(clean_fx)"
cat > "$fx/CLAUDE.md" <<'MD'
# Regeln

Ausgenommen: `~/.claude/x.md`, `/etc/hosts`, `https://example.com/a`, `brainstorms/<thema>.md`,
`src/{a,b}.ts`, `docs/*.md`, `$HOME/x`, `.env.local`, `git status`, `grilling`, `python -m pytest`.
Anker `docs/info.md#abschnitt` gilt.

```bash
cat docs/gibt-es-nicht.md
```
MD
expect_clean "Platzhalter, ~, /, http, Codeblöcke und .env.local werden nicht geprüft" "$fx"

# (d) ausgemusterte Namen
for datei in CLAUDE.md AGENTS.md README.md unter/CLAUDE.md docs/README.md; do
  for wort in Caveman context-mode SUPERPOWERS claude-mem; do
    fx="$(clean_fx)"; printf '\nSiehe auch %s.\n' "$wort" >> "$fx/$datei"
    expect_hit "$wort in $datei" "$fx" "$datei enthält den ausgemusterten Namen"
  done
done

echo "$pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
