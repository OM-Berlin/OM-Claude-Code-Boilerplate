#!/usr/bin/env python3
# Pattern adapted from Google knowledge-catalog reference agent (Apache-2.0)
#
# okf-viz.py — dependency-free OKF bundle visualizer (Python 3, stdlib only).
#
# Reads an OKF bundle (a Markdown tree with optional YAML-ish frontmatter)
# and generates ONE self-contained viz.html with an interactive knowledge
# graph (Cytoscape.js force layout, search, type filter, detail panel with
# rendered Markdown, in-viewer link navigation, backlinks).
#
# Offline limitation: the generated HTML loads Cytoscape.js 3.28.1 and
# marked 12.0.0 from cdn.jsdelivr.net (same approach as Google's original,
# hardened with SRI pins), so VIEWING the graph needs internet access —
# this script itself does not.
#
# Security: raw HTML inside page bodies is rendered as TEXT, not executed
# (marked renderer override) — bundles under raw/bundles/ are untrusted
# input, so <script>/<img onerror> payloads must never reach the DOM live.
#
# Usage:
#   python3 okf-viz.py [--root <bundle-dir>] [--out <path>] [--name <label>]
#
# Prints stats JSON on stdout: {"concepts": N, "edges": N, "bytes": N}

import argparse
import json
import os
import posixpath
import re
import sys
from html import escape as html_escape

# Files reserved for bundle plumbing — never treated as concepts.
RESERVED_BASENAMES = {"index.md", "log.md", "readme.md"}

# Fixed color palette; one color per distinct concept type, overflow -> gray.
PALETTE = ["#8b5cf6", "#3b82f6", "#10b981", "#f59e0b", "#ef4444", "#06b6d4", "#94a3b8"]
OVERFLOW_COLOR = "#6b7280"

NODE_SIZE_BASE = 30
NODE_SIZE_MAX_BONUS = 60
NODE_SIZE_CHARS_PER_UNIT = 200

# Markdown link targets ending in .md, optional #anchor: ](path/to/page.md#sec)
LINK_RE = re.compile(r"\]\(([^)\s]+\.md)(?:#[^)]*)?\)")

FM_KV_RE = re.compile(r"^\s*([A-Za-z0-9_-]+)\s*:\s*(.*)$")
FM_LIST_ITEM_RE = re.compile(r"^\s*-\s+(.*)$")


# ---------------------------------------------------------------------------
# Frontmatter parsing (tolerant, no yaml import)
# ---------------------------------------------------------------------------

def _clean_scalar(value):
    """Strip whitespace and one layer of matching quotes."""
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        value = value[1:-1]
    return value.strip()


def parse_frontmatter(text):
    """Parse a '---'-delimited frontmatter block at the start of `text`.

    Supports 'key: value', inline lists '[a, b]' and block lists
    ('key:' followed by '- item' lines). Anything unparseable is skipped.
    Returns (meta_dict, body_str). Without valid frontmatter: ({}, text).
    """
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return {}, text
    end = -1
    for i in range(1, len(lines)):
        if lines[i].strip() in ("---", "..."):
            end = i
            break
    if end == -1:  # unterminated frontmatter -> treat whole file as body
        return {}, text

    meta = {}
    i = 1
    while i < end:
        match = FM_KV_RE.match(lines[i])
        if not match:
            i += 1
            continue
        key, raw = match.group(1), match.group(2).strip()
        if raw == "":
            # Possible block list: collect following '- item' lines.
            items = []
            j = i + 1
            while j < end:
                item_match = FM_LIST_ITEM_RE.match(lines[j])
                if not item_match:
                    break
                item = _clean_scalar(item_match.group(1))
                if item:
                    items.append(item)
                j += 1
            if items:
                meta[key] = items
                i = j
                continue
            meta[key] = ""
        elif raw.startswith("[") and raw.endswith("]"):
            parts = (_clean_scalar(p) for p in raw[1:-1].split(","))
            meta[key] = [p for p in parts if p]
        else:
            meta[key] = _clean_scalar(raw)
        i += 1

    body = "\n".join(lines[end + 1:])
    return meta, body


def _as_scalar(value, default=""):
    if isinstance(value, list):
        value = value[0] if value else ""
    if not isinstance(value, str):
        value = str(value) if value is not None else ""
    value = value.strip()
    return value if value else default


def _as_list(value):
    if isinstance(value, list):
        return [str(v).strip() for v in value if str(v).strip()]
    if isinstance(value, str) and value.strip():
        return [value.strip()]
    return []


# ---------------------------------------------------------------------------
# Bundle scanning
# ---------------------------------------------------------------------------

def collect_docs(root):
    """Walk the bundle and return a sorted list of concept docs.

    Broken or frontmatter-less docs are kept with defaults, never dropped.
    """
    docs = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
        for filename in sorted(filenames):
            if filename.startswith("."):
                continue  # dotfiles + macOS/SMB AppleDouble sidecars (._foo.md)
            lower = filename.lower()
            if not lower.endswith(".md") or lower in RESERVED_BASENAMES:
                continue
            path = os.path.join(dirpath, filename)
            try:
                with open(path, "r", encoding="utf-8", errors="replace") as fh:
                    text = fh.read()
            except OSError as exc:
                print(f"warning: skipping unreadable {path}: {exc}", file=sys.stderr)
                continue
            concept_id = os.path.relpath(path, root).replace(os.sep, "/")[:-3]
            meta, body = parse_frontmatter(text)
            docs.append({
                "id": concept_id,
                "title": _as_scalar(meta.get("title"), default=concept_id),
                "type": _as_scalar(meta.get("type"), default="Unknown"),
                "description": _as_scalar(meta.get("description"), default=""),
                "tags": _as_list(meta.get("tags")),
                "body": body,
            })
    docs.sort(key=lambda d: d["id"])
    return docs


def extract_edges(docs):
    """Directed edges from in-body Markdown links.

    Discards external (http/https), /-absolute, broken (target not a node)
    and self links; deduplicates.
    """
    node_ids = {doc["id"] for doc in docs}
    edges = []
    seen = set()
    for doc in docs:
        base_dir = posixpath.dirname(doc["id"])
        # Strip fenced + inline code first: link syntax shown as an EXAMPLE
        # inside code must not become a graph edge.
        scan_body = re.sub(r"```.*?```", "", doc["body"], flags=re.S)
        scan_body = re.sub(r"`[^`\n]*`", "", scan_body)
        for raw in LINK_RE.findall(scan_body):
            if raw.startswith(("http://", "https://")) or raw.startswith("/"):
                continue
            target = posixpath.normpath(posixpath.join(base_dir, raw))
            if target.lower().endswith(".md"):
                target = target[:-3]
            if target not in node_ids or target == doc["id"]:
                continue
            key = (doc["id"], target)
            if key in seen:
                continue
            seen.add(key)
            edges.append({"source": doc["id"], "target": target})
    return edges


def build_graph(docs):
    """Assemble the graph payload embedded into the HTML."""
    types = sorted({doc["type"] for doc in docs})
    type_colors = {
        t: (PALETTE[i] if i < len(PALETTE) else OVERFLOW_COLOR)
        for i, t in enumerate(types)
    }
    nodes = [{
        "id": doc["id"],
        "label": doc["title"],
        "type": doc["type"],
        "color": type_colors[doc["type"]],
        "size": NODE_SIZE_BASE + min(
            NODE_SIZE_MAX_BONUS, len(doc["body"]) // NODE_SIZE_CHARS_PER_UNIT
        ),
        "tags": doc["tags"],
        "description": doc["description"],
    } for doc in docs]
    return {
        "nodes": nodes,
        "edges": extract_edges(docs),
        "bodies": {doc["id"]: doc["body"] for doc in docs},
        "types": type_colors,
        "palette": PALETTE,
    }


# ---------------------------------------------------------------------------
# HTML rendering
# ---------------------------------------------------------------------------

def render_html(graph, bundle_name):
    payload = json.dumps(graph, ensure_ascii=False, separators=(",", ":"))
    # Make the blob safe inside a <script> tag / JS source.
    payload = (payload
               .replace("<", "\\u003c")
               .replace(" ", "\\u2028")
               .replace(" ", "\\u2029"))
    html = HTML_TEMPLATE.replace("__BUNDLE_NAME__", html_escape(bundle_name))
    return html.replace("__BUNDLE_DATA__", payload)


HTML_TEMPLATE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>__BUNDLE_NAME__ · OKF Graph</title>
<script src="https://cdn.jsdelivr.net/npm/cytoscape@3.28.1/dist/cytoscape.min.js"
        integrity="sha384-J7Q85oZE4GJ/e7+n2aOQsLXfDwwfnA8S2nZAL5BpFsfpCF84zQD7LroZ/dMnLgex"
        crossorigin="anonymous"></script>
<script src="https://cdn.jsdelivr.net/npm/marked@12.0.0/marked.min.js"
        integrity="sha384-NNQgBjjuhtXzPmmy4gurS5X7P4uTt1DThyevz4Ua0IVK5+kazYQI1W27JHjbbxQz"
        crossorigin="anonymous"></script>
<style>
  :root {
    --bg: #0b0f1a;
    --surface: #111827;
    --surface-2: #1b2436;
    --line: #273449;
    --text: #e2e8f0;
    --text-dim: #94a3b8;
    --accent: #8b5cf6;
    --radius: 10px;
    --font: ui-sans-serif, system-ui, "Segoe UI", Roboto, sans-serif;
    --mono: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  }
  * { box-sizing: border-box; }
  html, body { height: 100%; }
  body {
    margin: 0;
    background: var(--bg);
    color: var(--text);
    font-family: var(--font);
    font-size: 14px;
    display: grid;
    grid-template-rows: auto 1fr;
    grid-template-columns: 270px 1fr auto;
    grid-template-areas: "header header header" "controls graph detail";
    overflow: hidden;
  }
  [hidden] { display: none !important; }

  header {
    grid-area: header;
    display: flex;
    align-items: baseline;
    gap: 1rem;
    padding: 0.75rem 1.25rem;
    background: var(--surface);
    border-bottom: 1px solid var(--line);
  }
  header h1 { margin: 0; font-size: 1.05rem; letter-spacing: 0.02em; }
  header .badge {
    font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.1em;
    color: var(--accent); border: 1px solid var(--accent);
    border-radius: 999px; padding: 0.1rem 0.5rem;
  }
  header #stats { margin: 0 0 0 auto; color: var(--text-dim); font-size: 0.8rem; }

  #controls {
    grid-area: controls;
    padding: 1rem;
    background: var(--surface);
    border-right: 1px solid var(--line);
    overflow-y: auto;
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }
  .field { display: flex; flex-direction: column; gap: 0.35rem; }
  .field > span {
    font-size: 0.7rem; text-transform: uppercase;
    letter-spacing: 0.08em; color: var(--text-dim);
  }
  .field input, .field select {
    background: var(--surface-2); color: var(--text);
    border: 1px solid var(--line); border-radius: 6px;
    padding: 0.45rem 0.6rem; font: inherit; width: 100%;
  }
  .field input:focus, .field select:focus {
    outline: 2px solid var(--accent); outline-offset: 1px;
  }
  fieldset#type-filter {
    border: 1px solid var(--line); border-radius: var(--radius);
    padding: 0.6rem 0.75rem; margin: 0;
    display: flex; flex-direction: column; gap: 0.4rem;
  }
  fieldset#type-filter legend {
    font-size: 0.7rem; text-transform: uppercase;
    letter-spacing: 0.08em; color: var(--text-dim); padding: 0 0.3rem;
  }
  .type-row {
    display: flex; align-items: center; gap: 0.5rem;
    cursor: pointer; font-size: 0.85rem;
  }
  .type-row input { accent-color: var(--accent); }
  .chip-dot {
    width: 0.7rem; height: 0.7rem; border-radius: 50%;
    flex: none; box-shadow: 0 0 0 2px rgba(255,255,255,0.08);
  }
  .empty { color: var(--text-dim); font-style: italic; margin: 0; }
  #controls .hint { font-size: 0.72rem; color: var(--text-dim); line-height: 1.5; }

  #graph { grid-area: graph; min-width: 0; min-height: 0; background:
    radial-gradient(circle at 30% 20%, #131b2e 0%, var(--bg) 60%); }

  #detail {
    grid-area: detail;
    width: min(420px, 38vw);
    background: var(--surface);
    border-left: 1px solid var(--line);
    overflow-y: auto;
    padding: 1rem 1.25rem 2rem;
    position: relative;
  }
  #detail-close {
    position: absolute; top: 0.6rem; right: 0.6rem;
    background: var(--surface-2); color: var(--text-dim);
    border: 1px solid var(--line); border-radius: 6px;
    width: 1.8rem; height: 1.8rem; cursor: pointer; font-size: 1rem;
  }
  #detail-close:hover, #detail-close:focus-visible { color: var(--text); border-color: var(--accent); }
  #detail h2 { margin: 0.25rem 6ch 0.2rem 0; font-size: 1.15rem; }
  #detail-id { margin: 0 0 0.6rem; font-family: var(--mono); font-size: 0.72rem; color: var(--text-dim); }
  #detail-chips { display: flex; flex-wrap: wrap; gap: 0.35rem; margin-bottom: 0.75rem; }
  .chip {
    font-size: 0.7rem; padding: 0.15rem 0.55rem; border-radius: 999px;
    background: var(--surface-2); border: 1px solid var(--line); color: var(--text-dim);
  }
  .chip.type-chip { color: #0b0f1a; font-weight: 600; border: none; }
  #detail-desc { color: var(--text-dim); font-style: italic; margin: 0 0 0.75rem; }
  article#detail-body { line-height: 1.6; font-size: 0.88rem; }
  article#detail-body h1, article#detail-body h2, article#detail-body h3 {
    font-size: 1rem; border-bottom: 1px solid var(--line); padding-bottom: 0.25rem;
  }
  article#detail-body code {
    font-family: var(--mono); font-size: 0.8em;
    background: var(--surface-2); padding: 0.1em 0.35em; border-radius: 4px;
  }
  article#detail-body pre {
    background: var(--surface-2); border: 1px solid var(--line);
    border-radius: 8px; padding: 0.75rem; overflow-x: auto;
  }
  article#detail-body pre code { background: none; padding: 0; }
  article#detail-body a { color: var(--accent); }
  article#detail-body a.internal { text-decoration-style: dotted; }
  article#detail-body a.dead { color: var(--text-dim); text-decoration: line-through; cursor: not-allowed; }
  article#detail-body blockquote {
    margin: 0.5rem 0; padding: 0.1rem 0.9rem;
    border-left: 3px solid var(--accent); color: var(--text-dim);
  }
  article#detail-body img { max-width: 100%; }
  article#detail-body table { border-collapse: collapse; }
  article#detail-body th, article#detail-body td {
    border: 1px solid var(--line); padding: 0.3rem 0.55rem;
  }
  #detail-backlinks h3 {
    font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.08em;
    color: var(--text-dim); border-top: 1px solid var(--line);
    padding-top: 0.9rem; margin-top: 1.25rem;
  }
  #backlink-list { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 0.3rem; }
  #backlink-list a { color: var(--accent); cursor: pointer; text-decoration: none; }
  #backlink-list a:hover, #backlink-list a:focus-visible { text-decoration: underline; }
</style>
</head>
<body>
<header>
  <h1>__BUNDLE_NAME__</h1>
  <span class="badge">OKF Graph</span>
  <p id="stats"></p>
</header>

<aside id="controls" aria-label="Graph controls">
  <label class="field">
    <span>Search</span>
    <input id="search" type="search" placeholder="title, id, tag …" autocomplete="off">
  </label>
  <label class="field">
    <span>Layout</span>
    <select id="layout">
      <option value="cose" selected>cose (force)</option>
      <option value="concentric">concentric</option>
      <option value="breadthfirst">breadthfirst</option>
      <option value="circle">circle</option>
      <option value="grid">grid</option>
    </select>
  </label>
  <fieldset id="type-filter">
    <legend>Types</legend>
  </fieldset>
  <p class="hint">Click a node for details. Internal links in the panel navigate inside the viewer.</p>
</aside>

<main id="graph" aria-label="Knowledge graph"></main>

<aside id="detail" aria-label="Concept details" hidden>
  <button id="detail-close" type="button" aria-label="Close details">&times;</button>
  <h2 id="detail-title"></h2>
  <p id="detail-id"></p>
  <div id="detail-chips"></div>
  <p id="detail-desc" hidden></p>
  <article id="detail-body"></article>
  <section id="detail-backlinks">
    <h3>Cited by</h3>
    <ul id="backlink-list"></ul>
  </section>
</aside>

<script>
"use strict";
const DATA = __BUNDLE_DATA__;

const nodeById = Object.create(null);
DATA.nodes.forEach(function (n) { nodeById[n.id] = n; });

const backlinks = Object.create(null);
DATA.edges.forEach(function (e) {
  (backlinks[e.target] = backlinks[e.target] || []).push(e.source);
});

document.getElementById("stats").textContent =
  DATA.nodes.length + " concepts · " + DATA.edges.length + " links";

// ---- Cytoscape ------------------------------------------------------------
const cy = cytoscape({
  container: document.getElementById("graph"),
  elements: DATA.nodes.map(function (n) {
    return { group: "nodes", data: n };
  }).concat(DATA.edges.map(function (e, i) {
    return { group: "edges", data: { id: "e" + i, source: e.source, target: e.target } };
  })),
  style: [
    { selector: "node", style: {
        "background-color": "data(color)",
        "width": "data(size)",
        "height": "data(size)",
        "label": "data(label)",
        "color": "#cbd5e1",
        "font-size": 11,
        "text-valign": "bottom",
        "text-margin-y": 7,
        "text-wrap": "wrap",
        "text-max-width": 130,
        "border-width": 2,
        "border-color": "#0b0f1a",
        "transition-property": "opacity",
        "transition-duration": "150ms"
    }},
    { selector: "edge", style: {
        "width": 1.5,
        "line-color": "#334155",
        "target-arrow-color": "#334155",
        "target-arrow-shape": "triangle",
        "arrow-scale": 0.9,
        "curve-style": "bezier",
        "transition-property": "opacity",
        "transition-duration": "150ms"
    }},
    { selector: "node:selected", style: {
        "border-color": "#f8fafc",
        "border-width": 3
    }},
    { selector: ".dimmed", style: { "opacity": 0.12, "events": "no" } },
    { selector: ".hidden-el", style: { "display": "none" } }
  ],
  layout: { name: DATA.nodes.length > 0 ? "cose" : "grid", animate: false, padding: 40 },
  wheelSensitivity: 0.25
});

document.getElementById("layout").addEventListener("change", function (ev) {
  cy.stop(true);  // kill pending viewport animations so they cannot pan the new layout off-screen
  cy.layout({ name: ev.target.value, animate: false, fit: true, padding: 40 }).run();
});

// ---- Search (dims non-matches on title / id / tags) -----------------------
function applySearch() {
  const q = document.getElementById("search").value.trim().toLowerCase();
  cy.batch(function () {
    if (!q) { cy.elements().removeClass("dimmed"); return; }
    cy.nodes().forEach(function (n) {
      const d = n.data();
      const hay = (d.label + " " + d.id + " " + (d.tags || []).join(" ")).toLowerCase();
      n.toggleClass("dimmed", hay.indexOf(q) === -1);
    });
    cy.edges().forEach(function (e) {
      e.toggleClass("dimmed", e.source().hasClass("dimmed") || e.target().hasClass("dimmed"));
    });
  });
}
document.getElementById("search").addEventListener("input", applySearch);

// ---- Type filter -----------------------------------------------------------
const filterBox = document.getElementById("type-filter");
const typeNames = Object.keys(DATA.types).sort();

function applyTypeFilter() {
  const active = new Set();
  filterBox.querySelectorAll("input:checked").forEach(function (cb) { active.add(cb.value); });
  cy.batch(function () {
    cy.nodes().forEach(function (n) {
      n.toggleClass("hidden-el", !active.has(n.data("type")));
    });
    cy.edges().forEach(function (e) {
      e.toggleClass("hidden-el",
        e.source().hasClass("hidden-el") || e.target().hasClass("hidden-el"));
    });
  });
}

if (typeNames.length === 0) {
  const p = document.createElement("p");
  p.className = "empty";
  p.textContent = "No concepts in this bundle.";
  filterBox.appendChild(p);
}
typeNames.forEach(function (t) {
  const label = document.createElement("label");
  label.className = "type-row";
  const cb = document.createElement("input");
  cb.type = "checkbox"; cb.checked = true; cb.value = t;
  cb.addEventListener("change", applyTypeFilter);
  const dot = document.createElement("span");
  dot.className = "chip-dot"; dot.style.background = DATA.types[t];
  const txt = document.createElement("span");
  txt.textContent = t;
  label.appendChild(cb); label.appendChild(dot); label.appendChild(txt);
  filterBox.appendChild(label);
});

// ---- Markdown hardening ----------------------------------------------------
// Raw HTML in page bodies renders as text, never executes: bundles mounted
// from raw/bundles/ are untrusted input, so <script>/<img onerror> payloads
// must not reach the live DOM. Handles both marked v12 (string) and newer
// token-object renderer signatures.
(function () {
  function esc(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }
  marked.use({ renderer: { html: function (token) {
    return esc(typeof token === "string" ? token : (token && token.text) || "");
  } } });
})();

// ---- Detail panel ----------------------------------------------------------
const panel = document.getElementById("detail");

function dirOf(id) {
  const i = id.lastIndexOf("/");
  return i === -1 ? "" : id.slice(0, i);
}

function resolveRel(dir, href) {
  const raw = href.replace(/\.md$/i, "");
  const parts = (dir ? dir.split("/") : []).concat(raw.split("/"));
  const out = [];
  for (const p of parts) {
    if (p === "" || p === ".") continue;
    if (p === "..") {
      if (out.length === 0) return null; // escapes the bundle root -> dead link
      out.pop();
    } else out.push(p);
  }
  return out.join("/");
}

function makeChip(text, bg) {
  const chip = document.createElement("span");
  chip.className = bg ? "chip type-chip" : "chip";
  if (bg) chip.style.background = bg;
  chip.textContent = text;
  return chip;
}

function wireBodyLinks(container, currentId) {
  container.querySelectorAll("a").forEach(function (a) {
    const href = a.getAttribute("href") || "";
    if (/^https?:\/\//i.test(href)) {
      a.target = "_blank"; a.rel = "noopener noreferrer";
      return;
    }
    const m = href.match(/^([^#]+\.md)(#.*)?$/i);
    if (m && href.charAt(0) !== "/") {
      const target = resolveRel(dirOf(currentId), m[1]);
      if (nodeById[target]) {
        a.classList.add("internal");
        a.addEventListener("click", function (ev) {
          ev.preventDefault();
          showNode(target);
        });
        return;
      }
    }
    a.classList.add("dead");
    a.title = "Target not in this bundle";
    a.addEventListener("click", function (ev) { ev.preventDefault(); });
  });
}

function renderBacklinks(id) {
  const list = document.getElementById("backlink-list");
  list.textContent = "";
  const sources = backlinks[id] || [];
  if (sources.length === 0) {
    const li = document.createElement("li");
    li.className = "empty";
    li.textContent = "No inbound links.";
    list.appendChild(li);
    return;
  }
  sources.forEach(function (src) {
    const li = document.createElement("li");
    const a = document.createElement("a");
    a.href = "#";
    a.textContent = (nodeById[src] ? nodeById[src].label : src) + " (" + src + ")";
    a.addEventListener("click", function (ev) {
      ev.preventDefault();
      showNode(src);
    });
    li.appendChild(a);
    list.appendChild(li);
  });
}

function showNode(id) {
  const n = nodeById[id];
  if (!n) return;
  cy.$(":selected").unselect();
  const el = cy.$id(id);
  el.select();

  document.getElementById("detail-title").textContent = n.label;
  document.getElementById("detail-id").textContent = n.id;

  const chips = document.getElementById("detail-chips");
  chips.textContent = "";
  chips.appendChild(makeChip(n.type, n.color));
  (n.tags || []).forEach(function (t) { chips.appendChild(makeChip("#" + t)); });

  const desc = document.getElementById("detail-desc");
  desc.hidden = !n.description;
  desc.textContent = n.description || "";

  const body = document.getElementById("detail-body");
  body.innerHTML = marked.parse(DATA.bodies[id] || "*No content.*");
  wireBodyLinks(body, id);
  renderBacklinks(id);

  const wasHidden = panel.hidden;
  panel.hidden = false;
  panel.scrollTop = 0;
  if (wasHidden) cy.resize();
  cy.stop(true);
  cy.animate({ center: { eles: el } }, { duration: 250 });
}

cy.on("tap", "node", function (ev) { showNode(ev.target.id()); });

document.getElementById("detail-close").addEventListener("click", function () {
  panel.hidden = true;
  cy.$(":selected").unselect();
  cy.resize();
});
</script>
</body>
</html>
"""


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv=None):
    script_dir = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(
        description="Generate a self-contained interactive knowledge-graph "
                    "viz.html from an OKF Markdown bundle (stdlib only).")
    parser.add_argument("--root", default=script_dir,
                        help="bundle directory (default: directory of this script)")
    parser.add_argument("--out", default=None,
                        help="output HTML path (default: <root>/viz.html)")
    parser.add_argument("--name", default=None,
                        help="display name (default: name of the root folder)")
    args = parser.parse_args(argv)

    root = os.path.abspath(args.root)
    if not os.path.isdir(root):
        print(f"error: --root is not a directory: {root}", file=sys.stderr)
        return 1

    out_path = args.out or os.path.join(root, "viz.html")
    bundle_name = args.name or os.path.basename(os.path.normpath(root)) or "OKF Bundle"

    docs = collect_docs(root)
    graph = build_graph(docs)
    html = render_html(graph, bundle_name)
    encoded = html.encode("utf-8")
    try:
        with open(out_path, "wb") as fh:
            fh.write(encoded)
    except OSError as exc:
        print(f"error: cannot write {out_path}: {exc}", file=sys.stderr)
        return 1

    print(json.dumps({
        "concepts": len(graph["nodes"]),
        "edges": len(graph["edges"]),
        "bytes": len(encoded),
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
