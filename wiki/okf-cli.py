#!/usr/bin/env python3
"""okf-cli.py — OKF v0.1 bundle navigator (stdlib only).

Navigate an OKF markdown bundle (pages with optional frontmatter) without
any third-party dependencies. Default bundle root is the directory this
script lives in, regardless of the current working directory.

Commands:
  index [subpath]              Print <dir>/index.md, or synthesize a listing
                               of direct children if no index.md exists.
                                 python3 okf-cli.py index
                                 python3 okf-cli.py index concepts
  read <slug-or-path>          Print one page; '.md' is appended to slugs.
                                 python3 okf-cli.py read concepts/alpha
  find "<query>" [--limit N]   Rank pages by term matches — 3 points per
                               frontmatter occurrence, 1 point (binary) for
                               a body hit. Default limit: 15.
                                 python3 okf-cli.py find "zebra" --limit 5

Global flag (may appear before or after the command):
  --root <dir>                 Operate on another bundle root instead of the
                               script's directory (e.g. raw/bundles/<name>/).
"""

import re
import sys
from pathlib import Path

RESERVED = {"index.md", "log.md", "README.md"}
DEFAULT_LIMIT = 15
FIELD_RE = re.compile(r"^([A-Za-z0-9_-]+)\s*:\s*(.*)$")


def reconfigure_utf8():
    """Best-effort UTF-8 output, ignore failures (exotic streams etc.)."""
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")
        except Exception:
            pass


def resolve_in_root(root, user_path):
    """Resolve user_path against root (symlinks included). Return the resolved
    path only if it is root itself or a descendant — otherwise None."""
    try:
        candidate = (root / user_path).resolve()
        candidate.relative_to(root)
    except (ValueError, OSError):
        return None
    return candidate


def read_text(path):
    # utf-8-sig strips a leading BOM (which would otherwise hide the
    # frontmatter delimiter) and still decodes plain UTF-8.
    return path.read_text(encoding="utf-8-sig", errors="replace")


def split_frontmatter(text):
    """Return (frontmatter_text, body). Frontmatter only counts if the file
    starts with a '---' line and another pure '---' line follows."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return "", text
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return "\n".join(lines[1:i]), "\n".join(lines[i + 1:])
    return "", text


def parse_fields(frontmatter):
    """Extract flat 'key: value' fields per line, strip surrounding quotes."""
    fields = {}
    for line in frontmatter.splitlines():
        m = FIELD_RE.match(line)
        if not m:
            continue
        key, value = m.group(1), m.group(2).strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
            value = value[1:-1]
        fields[key] = value
    return fields


def slug_for(path, root):
    return path.relative_to(root).as_posix()[:-len(".md")]


def contained(root, path):
    """True if path (symlinks resolved) stays inside the bundle root."""
    return resolve_in_root(root, path.relative_to(root)) is not None


def corpus(root):
    # The containment check keeps symlinked .md files that point outside
    # the bundle from leaking external content into search results.
    return sorted(p for p in root.rglob("*.md")
                  if p.is_file() and p.name not in RESERVED
                  and contained(root, p))


def cmd_index(root, args):
    sub = args[0] if args else ""
    target = resolve_in_root(root, sub) if sub else root
    if target is None or not target.is_dir():
        print(f"✗ no such directory in bundle: {sub}")
        return 1
    index_file = target / "index.md"
    if index_file.is_file():
        print(read_text(index_file), end="")
        return 0
    print(f"(no index.md in {sub or 'root'}; synthesizing a listing)")
    for child in sorted(target.iterdir(), key=lambda p: p.name):
        if not contained(root, child):
            continue  # symlink escaping the bundle
        if child.is_dir():
            print(f"* {child.name}/")
        elif child.suffix == ".md" and child.name not in RESERVED:
            print(f"* {slug_for(child, root)}")
    return 0


def cmd_read(root, args):
    if not args:
        print("usage: python3 okf-cli.py read <path>"
              "   e.g. read concepts/alpha")
        return 1
    arg = args[0]
    rel = arg if arg.endswith(".md") else arg + ".md"
    target = resolve_in_root(root, rel)
    if target is None or not target.is_file():
        print(f"✗ not found: {arg}")
        return 1
    print(read_text(target), end="")
    return 0


def cmd_find(root, args):
    limit, rest, i = DEFAULT_LIMIT, [], 0
    while i < len(args):
        if args[i] == "--limit":
            try:
                limit = int(args[i + 1])
            except (IndexError, ValueError):
                limit = 0
            if limit < 1:
                print("✗ --limit requires a positive number")
                return 1
            i += 2
        else:
            rest.append(args[i])
            i += 1
    query = " ".join(rest).strip()
    terms = query.lower().split()
    if not terms:
        print('usage: python3 okf-cli.py find "<query>" [--limit N]')
        return 1
    results = []
    for path in corpus(root):
        frontmatter, body = split_frontmatter(read_text(path))
        fm_lower, body_lower = frontmatter.lower(), body.lower()
        score = sum(3 * fm_lower.count(t) + (1 if t in body_lower else 0)
                    for t in terms)
        if score > 0:
            title = parse_fields(frontmatter).get("title", "")
            results.append((score, slug_for(path, root), title))
    if not results:
        print(f"No matches for '{query}'.")
        return 0
    results.sort(key=lambda r: (-r[0], r[1]))
    print(f"Matches for '{query}':")
    for score, slug, title in results[:limit]:
        print(f"  [{score:>3}] {slug}")
        if title:
            print(f"        {title}")
    return 0


def extract_root(argv):
    """Pull a global '--root <dir>' out of argv (any position)."""
    root, rest, i = Path(__file__).resolve().parent, [], 0
    while i < len(argv):
        if argv[i] == "--root" and i + 1 < len(argv):
            root = Path(argv[i + 1])
            i += 2
        else:
            rest.append(argv[i])
            i += 1
    return root, rest


def main(argv):
    reconfigure_utf8()
    root, args = extract_root(argv)
    if not args:
        print(__doc__.strip())
        return 1
    command, rest = args[0], args[1:]
    if command in ("-h", "--help"):
        print(__doc__.strip())
        return 0
    handlers = {"index": cmd_index, "read": cmd_read, "find": cmd_find}
    if command not in handlers:
        print(__doc__.strip())
        return 1
    root = root.resolve()
    if not root.is_dir():
        print(f"✗ bundle root is not a directory: {root}")
        return 1
    return handlers[command](root, rest)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
