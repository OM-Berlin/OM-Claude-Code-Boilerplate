#!/usr/bin/env bash
# Prüft wiki/ gegen das Open Knowledge Format (OKF) 0.3 und schlägt an, wenn
#   (a) wiki/index.md den Kopf des Wikis nicht hat (okf_version "0.3", title,
#       description, license) oder ein index.md in einem Unterordner einen Kopf hat,
#   (b) eine Seite keinen Kopf mit `type` hat oder ein Schlüssel doppelt vorkommt,
#   (c) eine Seite in keinem index.md verlinkt ist,
#   (d) irgendwo ein Wikilink mit doppelten eckigen Klammern steht,
#   (e) wiki/log.md fehlt, einen Kopf hat, eine Überschrift "## " ohne Datum
#       JJJJ-MM-TT enthält oder ein älteres Datum über einem neueren steht.
# Dateien und Ordner, die mit einem Punkt beginnen, gehören laut OKF nicht dazu.
# Der zweite Teil prüft die Prüfung selbst mit absichtlich kaputten Mustern.
# Optional und ausführlicher: der Prüfer aus dem OKF-Projekt (README, Abschnitt Wiki).
# Lauf: bash .claude/hooks/tests/test-wiki-okf.sh
# Nur bash, find, grep, sed und awk; bash 3.2 kompatibel (macOS).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; }

# fm <datei>: gibt den Kopf ohne die beiden Zeilen --- aus.
# Rückgabe 0: Kopf da, 1: kein Kopf, 2: Kopf nicht geschlossen.
fm() {
  awk '{ sub(/\r$/, "") }
    NR == 1 { if ($0 != "---") { absent = 1; exit } next }
    $0 == "---" { closed = 1; exit }
    { print }
    END { if (absent || NR == 0) exit 1; if (!closed) exit 2 }' "$1"
}

# value <kopf> <schlüssel>: Wert eines Schlüssels der obersten Ebene.
value() { printf '%s\n' "$1" | sed -n -E "s/^$2:[[:space:]]*//p" | head -n 1 | sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//'; }

# index_links <index.md>: Linkziele, ohne #Anker und ohne führendes ./
index_links() { grep -o '\]([^)]*)' "$1" 2>/dev/null | sed -e 's/^](//' -e 's/)$//' -e 's/#.*//' -e 's|^\./||'; }

# check_wiki <wiki-ordner>: schreibt pro Befund eine Zeile auf stdout.
check_wiki() {
  local wiki="$1" f rel head rc key dir base listed
  local index="$wiki/index.md" log="$wiki/log.md"
  if [ ! -f "$index" ]; then
    echo "index.md fehlt. Legen Sie wiki/index.md mit dem Kopf des Wikis an."
  else
    head="$(fm "$index")"
    if [ $? -ne 0 ]; then
      echo "index.md hat keinen Kopf. Oben gehören okf_version, title, description und license hin."
    else
      case "$(value "$head" okf_version)" in
        '"0.3"' | "'0.3'") ;;
        *) echo "index.md: okf_version muss \"0.3\" sein, in Anführungszeichen." ;;
      esac
      for key in title description license; do
        [ -n "$(value "$head" "$key")" ] || echo "index.md: Im Kopf fehlt $key."
      done
    fi
  fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel="${f#"$wiki"/}"; base="${rel##*/}"; dir="$(dirname "$f")"
    grep -q '\[\[' "$f" && echo "$rel enthält einen Wikilink mit [[ ]]. Schreiben Sie [Titel](datei.md)."
    head="$(fm "$f")"; rc=$?
    [ "$rc" -eq 2 ] && echo "$rel: Der Kopf wird nicht mit einer Zeile --- geschlossen."
    if [ "$rc" -eq 0 ]; then
      for key in $(printf '%s\n' "$head" | grep -o -E '^[A-Za-z0-9_-]+:' | sort | uniq -d); do
        echo "$rel: Der Schlüssel ${key%:} steht doppelt im Kopf."
      done
    fi
    case "$base" in
      index.md)
        [ "$dir" != "$wiki" ] && [ "$rc" -ne 1 ] &&
          echo "$rel: Ein index.md in einem Unterordner hat keinen Kopf. Nehmen Sie ihn heraus."
        continue
        ;;
      log.md)
        [ "$rc" -ne 1 ] && echo "$rel: log.md hat keinen Kopf. Nehmen Sie ihn heraus."
        awk -v rel="$rel" '{ sub(/\r$/, "") }
          /^## / {
            d = substr($0, 4); sub(/[[:space:]]+$/, "", d)
            if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) {
              print rel ": Die Überschrift \"" $0 "\" ist kein Datum JJJJ-MM-TT. Unter ## steht in log.md nur das Datum."
            } else {
              if (prev != "" && d > prev) print rel ": " d " steht unter " prev ". Das neueste Datum gehört nach oben."
              prev = d
            }
          }' "$f"
        continue
        ;;
    esac
    if [ "$rc" -ne 0 ] || [ -z "$(value "$head" type)" ]; then
      echo "$rel hat keinen Kopf mit type. Kopieren Sie den Kopf aus wiki/_vorlage.md."
    fi
    listed=0
    index_links "$index" | grep -qxF -e "$rel" -e "/$rel" && listed=1
    [ -f "$dir/index.md" ] && index_links "$dir/index.md" | grep -qxF "$base" && listed=1
    [ "$listed" = 1 ] || echo "$rel steht in keinem index.md. Ergänzen Sie in wiki/index.md: - [Titel]($rel) - ein Satz"
  done <<EOF
$(find "$wiki" -mindepth 1 -name '.*' -prune -o -type f -name '*.md' -print 2>/dev/null | sort)
EOF
  [ -f "$log" ] || echo "log.md fehlt. Legen Sie wiki/log.md an: Überschrift, dann je Tag ## JJJJ-MM-TT."
}

# --- 1. Das echte Wiki ---
real="$(check_wiki "$ROOT/wiki")"
if [ -z "$real" ]; then
  ok
else
  bad "wiki/ verletzt OKF 0.3:"
  printf '%s\n' "$real" | sed 's/^/      - /'
fi

# --- 2. Die Prüfung selbst ---
clean_fx() {
  local fx="$WORK/fx"
  rm -rf "$fx"; mkdir -p "$fx/teil" "$fx/.obsidian"
  printf -- '---\nokf_version: "0.3"\ntitle: T\ndescription: D\nlicense: CC-BY-4.0\n---\n\n# Seiten\n\n- [A](a.md) - a\n- [B](teil/b.md) - b\n' > "$fx/index.md"
  printf -- '# Log\n\n## 2026-11-21\n- neu\n\n## 2026-11-20\n- alt\n' > "$fx/log.md"
  printf -- '---\ntype: Begriff\n---\n\nText mit [Link](teil/b.md).\n' > "$fx/a.md"
  printf -- '---\ntype: Ablauf\n---\n\nText.\n' > "$fx/teil/b.md"
  printf -- '# Unterordner\n\n- [B](b.md) - b\n' > "$fx/teil/index.md"
  printf -- 'ohne Kopf, aber versteckt\n[[egal]]\n' > "$fx/.obsidian/notiz.md"
  echo "$fx"
}
expect_hit() { # expect_hit <name> <fx> <teil der meldung>
  local out; out="$(check_wiki "$2")"
  case "$out" in *"$3"*) ok ;; *) bad "Prüfung schlägt nicht an: $1" "erwartet '$3', bekommen: ${out:-nichts}" ;; esac
}

fx="$(clean_fx)"; out="$(check_wiki "$fx")"
[ -z "$out" ] && ok || bad "Prüfung schlägt zu Unrecht an: saubere Grundlage" "$out"

fx="$(clean_fx)"; rm "$fx/index.md"
expect_hit "index.md fehlt" "$fx" "index.md fehlt"
fx="$(clean_fx)"; sed -i.bak 's/^okf_version: "0.3"$/okf_version: 0.3/' "$fx/index.md"
expect_hit "okf_version ohne Anführungszeichen" "$fx" 'okf_version muss "0.3" sein'
fx="$(clean_fx)"; sed -i.bak '/^license:/d' "$fx/index.md"
expect_hit "license fehlt" "$fx" "Im Kopf fehlt license"
fx="$(clean_fx)"; printf -- '---\nokf_version: "0.3"\n---\n# Unter\n' > "$fx/teil/index.md"
expect_hit "Unterordner-index.md mit Kopf" "$fx" "teil/index.md: Ein index.md in einem Unterordner"
fx="$(clean_fx)"; printf -- 'Nur Text.\n' > "$fx/a.md"
expect_hit "Seite ohne Kopf" "$fx" "a.md hat keinen Kopf mit type"
fx="$(clean_fx)"; printf -- '---\ntitle: Ohne Typ\n---\n' > "$fx/a.md"
expect_hit "Seite ohne type" "$fx" "a.md hat keinen Kopf mit type"
fx="$(clean_fx)"; printf -- '---\ntype: Begriff\n' > "$fx/a.md"
expect_hit "Kopf nicht geschlossen" "$fx" "a.md: Der Kopf wird nicht"
fx="$(clean_fx)"; printf -- '---\ntype: Begriff\ntype: Ablauf\n---\n' > "$fx/a.md"
expect_hit "doppelter Schlüssel" "$fx" "Der Schlüssel type steht doppelt"
fx="$(clean_fx)"; printf -- '---\ntype: Begriff\n---\n' > "$fx/neu.md"
expect_hit "Seite fehlt im Index" "$fx" "neu.md steht in keinem index.md"
fx="$(clean_fx)"; printf -- '---\ntype: Ablauf\n---\n' > "$fx/teil/c.md"
expect_hit "Seite im Unterordner fehlt im Index" "$fx" "teil/c.md steht in keinem index.md"
fx="$(clean_fx)"; printf '\nSiehe [[b]].\n' >> "$fx/a.md"
expect_hit "Wikilink" "$fx" "a.md enthält einen Wikilink"
fx="$(clean_fx)"; rm "$fx/log.md"
expect_hit "log.md fehlt" "$fx" "log.md fehlt"
fx="$(clean_fx)"; printf -- '# Log\n\n## Neuigkeiten\n' > "$fx/log.md"
expect_hit "log.md ohne Datum" "$fx" "ist kein Datum JJJJ-MM-TT"
fx="$(clean_fx)"; printf -- '# Log\n\n## 21.11.2026\n' > "$fx/log.md"
expect_hit "log.md mit deutschem Datum" "$fx" "ist kein Datum JJJJ-MM-TT"
fx="$(clean_fx)"; printf -- '# Log\n\n## 2026-11-20\n\n## 2026-11-21\n' > "$fx/log.md"
expect_hit "log.md alt vor neu" "$fx" "2026-11-21 steht unter 2026-11-20"
fx="$(clean_fx)"; printf -- '---\ntype: Log\n---\n# Log\n' > "$fx/log.md"
expect_hit "log.md mit Kopf" "$fx" "log.md hat keinen Kopf"

echo "$pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
