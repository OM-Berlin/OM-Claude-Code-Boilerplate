---
name: session-handoff
description: Use when the user says "session handoff", "wrap up session", "hand off", "handoff summary", "let's wrap up", "summarize before I clear", or is about to /clear — and use it PROACTIVELY whenever a working session is winding down. Produces a structured end-of-session handoff so a fresh agent can continue seamlessly. In an OM-Boilerplate project it PERSISTS the handoff as a security-scrubbed, Obsidian-tagged file in brainstorms/sessions/ (parallel-session-safe) AND still prints the full handoff in chat so you can copy it, /clear, and paste it straight back; anywhere else it falls back to chat-only output.
---

# Session Handoff

> OM-Skill nach Nate Herks Handoff-Doc-Konzept (AI-OS: Wissen/Status explizit übergeben statt im Context verlieren).

Produce a repeatable end-of-session summary so the user can `/clear` and start a fresh agent without losing continuity. The next agent should be able to pick up by reading this summary alone.

This is a **context-handoff artifact**, not a status report. The audience is a future instance of you, not a stakeholder.

**What changed vs. the old chat-only version:** in an OM-Boilerplate project this skill now *persists* the handoff to a file so session knowledge survives `/clear`, terminal crashes, and multi-day gaps — and a fresh session can offer to reload it. Outside such a project it behaves exactly as before (chat-only). The persistence is what turns a one-shot summary into durable, greppable session memory.

## When to invoke

User says: "session handoff", "wrap up session", "hand off", "handoff summary", "let's wrap up", "summarize before I clear", or any near-equivalent. Also invoke proactively if the user signals they're about to `/clear` without having run it yet.

## Step 0 — pick the mode (this decides everything below)

Determine whether you are inside an **OM-Boilerplate project**. The reliable marker is the knowledge-layer structure: the project root contains **`brainstorms/` AND `decisions/` AND `wiki/`** (check the current working directory / git root).

- **All three present → PERSIST mode.** Write the handoff to a file *and* print a short confirmation in chat. Follow the whole skill.
- **Not present → FALLBACK mode (chat-only).** Behave exactly like the classic handoff: produce the summary in chat, write no file, touch no memory. Skip to "Output template" and "Hard rules", ignore the persistence sections. This keeps the skill portable — it must not litter files into arbitrary repos that don't expect them.

## How to gather the content (both modes)

1. **Review the full conversation**, not just the last few turns. Handoffs miss things when they only summarize recent context.
2. **Pull state from these sources (in order):**
   - Plan files referenced this session (check `~/.claude/plans/` if a plan was mentioned).
   - TodoWrite / task state — any in-progress or pending items.
   - Background processes you started with `run_in_background` — shell IDs are load-bearing for the next agent.
   - Files created or modified this session — you know what you touched; don't grep to re-discover.
   - Memory files written or updated (`~/.claude/projects/<project>/memory/`).
   - Unresolved questions — things you asked the user that never got a clear answer, or things the user asked that got deflected.
3. **Do NOT audit the filesystem.** This is synthesis of what happened in THIS session. No `git log`, no broad `Glob` sweeps. If you didn't touch it this session, it doesn't belong here.
4. **Do not restate what another artifact already holds.** If a decision lives in a plan, an ADR, `brainstorms/`, a commit message or a diff, reference it **by absolute path** instead of repeating it. A handoff that re-tells the plan is a second copy that will disagree with the first. Adopted from `mattpocock/skills` `/handoff` (2026-08-06) — it keeps handoffs short enough to actually be read.

## Output template — use exactly this structure, every time

The body below is identical in both modes. In PERSIST mode it becomes the file body (under the frontmatter from the next section); in FALLBACK mode it is the chat output.

```
# Session Handoff — <one-line title of what this session was about>

## Where it started
<2-3 sentences: what the user asked for, key framing or constraints that emerged>

## Decisions locked + what shipped
- <decision or change> — <why, and where it lives (absolute path if a file)>
- ...

## Key files for next session
- `<absolute path>` — <why the next agent should read this first>
- Plan file: `<path>` (if a plan drove the session)
- Memory files touched: `<paths>` (if any)

## Running state
- Background processes: <shell IDs + what they are + how to kill> — or "none"
- Dev servers / ports: <url + port> — or "none"
- Open worktrees / branches: <paths> — or "none"

## Verification — how to confirm things still work
- `<command>` — <expected outcome>
- ...

## Deferred + open questions
- Deferred: <item> — <why pushed to later>
- Open: <question needing the user's input> — <context>

## Suggested skills
- `<skill>` — <why the next session will need it>
- ... (omit the section entirely if none apply)

## Pick up here
<1-2 sentences: the single most likely next action for a fresh agent>
```

> **Suggested skills** is there because a fresh agent does not know what this session
> reached for. Naming the skills is cheaper than letting it rediscover them — and it is
> the one thing a handoff can carry that a plan file cannot. Adopted from
> `mattpocock/skills` `/handoff` (2026-08-06).

---

## PERSIST mode — writing the file

Everything from here down applies only when Step 0 selected PERSIST mode.

### 1. Security scrub (mandatory, before you write anything)

The handoff gets **committed to git** (shared team memory). A secret that slips into it is a secret in git history *forever* — deleting the file later does not undo that. So scrub the drafted body before writing.

Scan for these and replace the value with `‹REDACTED: <what it was>›`, keeping the surrounding context:

- API keys / tokens: `sk-…`, `ghp_…` `gho_…` `ghs_…`, `AKIA…`, `xox[baprs]-…`, `Bearer <token>`, anything matching `api[_-]?key`
- Passwords / connection strings: `password=…`, `postgres://user:pass@…`, `mysql://…:…@…`
- Private keys: any `-----BEGIN … PRIVATE KEY-----` block
- Concrete values read out of `.env` / `.env.local` this session

Rules of thumb that make this cheap:
- Prefer referencing the **env-var name or file path**, never the value — e.g. "reads `STRIPE_KEY` from `.env.local`", not the key itself.
- If you actually redacted something, add one line at the top of the body: `> Security: N value(s) redacted before persisting.` so the next agent knows to source them from `.env.local`.
- If genuinely secret context is load-bearing for continuation, put that file under `brainstorms/sessions/private/` (gitignored) instead of the normal location, and note the pointer in the committed handoff.

In practice handoffs rarely contain secrets — this is a cheap guard, not a reason to water down the content.

### 2. Timestamp + session id (use real values, not guesses)

Run `date "+%Y-%m-%d %H:%M"` (and `date "+%Y-%m-%d-%H%M"` for the filename) via Bash — do not invent the time.

Derive an 8-character `session-id` from the current session's UUID (it appears in your scratchpad/transcript path, e.g. `…/<uuid>/scratchpad`). Take the first 8 chars. If you cannot determine it, fall back to `date "+%H%M%S"`. This id is what disambiguates and links parallel sessions.

### 3. Filename + location

`brainstorms/sessions/YYYY-MM-DD-HHmm-<topic-slug>.md`

- `<topic-slug>`: kebab-case, ~2-4 words capturing the session topic (e.g. `stateful-session-handoff`).
- The date+time+slug combination is what keeps **parallel terminals** from colliding — several sessions in the same project write distinct files, never the same one.
- Create `brainstorms/sessions/` if it does not exist yet.

**Re-handoff in the same session:** if a file with the *same `session-id`* already exists in `brainstorms/sessions/`, update it in place — bump `updated`, refresh `status`, rewrite the body — rather than creating a second file. One session, one file.

### 4. Frontmatter (Obsidian-conform — the vault convention this project uses)

Prepend exactly this YAML block, then the body template above:

```yaml
---
type: session-handoff
session-id: <8-char id>
topic: <human-readable topic, same as the H1 title>
started: <YYYY-MM-DD HH:mm>   # when this session began, best estimate
updated: <YYYY-MM-DD HH:mm>   # now
status: status/aktiv          # aktiv = continue next time · abgeschlossen = done · blockiert = waiting on something
tags: [thema/<topic-slug>, status/aktiv]
---
```

Pick `status` honestly: `status/aktiv` if there's a clear next action, `status/abgeschlossen` if the work is fully done, `status/blockiert` if it's waiting on the user or an external thing. The `status` line and the matching `tags` entry must agree. Add a `firma/<ADO|OM|DO>` tag only if the project clearly belongs to one — otherwise leave it off.

### 5. Write the file, then ALSO print the full handoff in chat

Use the Write tool. Do **not** append to `brainstorms/sessions/index.md` — that file is a static guide, and appending to it from parallel sessions would race. Discovery works by listing the folder + reading frontmatter, so each self-describing file is enough.

Then output the **complete handoff in chat as well** — not just a pointer. The persisted file is the durable, greppable record; the chat copy is what the user grabs to `/clear` and paste straight into a fresh session (Cmd/Ctrl+C → `/clear` → Ctrl+V). Both must carry the same content.

Format the chat output like this:

```
Saved: /abs/path/to/brainstorms/sessions/<file>.md

<the full handoff body, verbatim — same Markdown you wrote to the file>
```

Lead with the one-line `Saved:` pointer so the path is obvious, then the whole handoff below it. The frontmatter itself does not need to be echoed — the body (from the `# Session Handoff …` heading down) is what the user pastes back.

## Hard rules

1. **PERSIST mode writes exactly one file** (in `brainstorms/sessions/`) and never edits `index.md`. **FALLBACK mode writes no file at all** — chat only. Never write memory from this skill in either mode.
2. **Never invent state.** If a section has nothing to report, write "none" — do not omit the section. Structure stability is the whole point.
3. **Absolute paths in the body.** The next agent may have a different working directory.
4. **If a plan file drove the session, name it first** in "Key files" so the next agent reads it before anything else.
5. **No emojis, no hype, no "great job" summaries.** Terse and concrete — paths, commands, shell IDs, decisions. Match the tone of a seasoned engineer handing off at end-of-shift.
6. **Background process IDs are critical.** If you started any `run_in_background` shells, their IDs must appear in "Running state" with the kill command — the next agent cannot find them otherwise.
7. **Scrub before you persist.** No secret values in a committed file — ever.

## Anti-patterns — do not do these

- Summarizing the last 3 turns and calling it a handoff.
- Listing files by relative path in the body.
- Skipping the "Running state" section because "nothing is running" — write "none" instead.
- In PERSIST mode: writing only the file and giving the user nothing to paste. Always echo the full handoff in chat too — the copy → `/clear` → paste path depends on it.
- Appending each session to a shared index/log file — that races across parallel terminals. One file per session.
- Adding a "what went well / what went poorly" retrospective. This isn't a retro (that's `os-audit --retro`).
- Recommending next steps beyond the single "Pick up here" line. The next agent decides; you just hand off.
