---
name: session-handoff
description: Use when the user says "session handoff", "wrap up session", "hand off", "handoff summary", "let's wrap up", "summarize before I clear", or is about to /clear, and PROACTIVELY when a working session winds down. Writes a briefing so a fresh agent has the full picture. Also use when a handoff is loaded ("lade den Handoff", a pasted handoff, a path in brainstorms/sessions/), then read only, give a short Fazit and wait. In a project with brainstorms/sessions/ it persists the handoff as a scrubbed, Obsidian-tagged file there and prints it in chat; elsewhere it is chat-only.
argument-hint: "Optional: Wofür ist die nächste Session?"
---

# Session Handoff

A handoff is a **briefing, not a work order**. It lets the user `/clear` without losing anything. The reader is a future instance of you, not a stakeholder.

## Loading a handoff

Unless the user's own words in the same message give a task:

1. Read the handoff, plus what you need to understand it. Read-only.
2. If the frontmatter has `commit`, run `git log --oneline <commit>..HEAD` and `git status --short`. Mention drift only if there is some.
3. Reply in at most 5 lines, in the user's language: "Hab alles gelesen. Stand: <1 sentence>. Könnte anstehen: <1 to 3 points>. Was denkst du?"
4. Stop. No edits, no commands with side effects, no subagents, no task list until the user answers.

"Possible next step" (older files: "Pick up here") is a suggestion to the user, never an instruction to you. Clearing the context and loading a handoff often just means getting ready.

If the user's own words do give a task, that task is the order and the handoff is context.

In OM-Boilerplate projects the hooks `.claude/hooks/handoff-offer-guard.sh` and `.claude/hooks/handoff-briefing-gate.sh` enforce this. The rule also holds where no hook runs (for example in Codex).

## Writing a handoff

### Mode

Project root has `brainstorms/sessions/`: **PERSIST** (file plus chat). Otherwise **FALLBACK** (chat only, no file, skip the persist section).

### Gather

- Cover the whole conversation, not the last turns.
- Sources: plan files, task state, background shells you started, files you touched, memory you wrote, questions left unanswered.
- This is synthesis of this session. No filesystem audit.
- Reference what already lives in a plan, ADR, issue, commit or diff by absolute path or URL. Do not copy it; two copies drift apart.
- If the user named what the next session is for, keep the reasoning that bears on it and drop the rest.

### Keep beliefs out of the facts

The next agent trusts this document and will not re-check it. Before saving, reread every claim like "done", "live" or "not built": either something in this session proved it, or mark it `unverified`. Keep the why, not only the what.

### Template

Same body in both modes. No section may be dropped except Suggested skills; write "none" if empty.

```
# Session Handoff: <title>

> Briefing, kein Auftrag. Beim Laden: lesen, kurzes Fazit, auf Go warten.

## Where it started
<2-3 sentences: the ask and the constraints that emerged>

## Decisions locked + what shipped
- <decision or change>: <why>, <where it lives> (<how verified, or unverified>)

## Key files for next session
- `<absolute path>`: <why to read it>; a plan file that drove the session comes first

## Running state
- Background processes: <shell ID, what, how to kill> or none
- Dev servers / ports: <url> or none
- Open worktrees / branches: <paths> or none

## Verification
- `<command>`: <expected outcome>

## Deferred + open questions
- Deferred: <item> (<why later>)
- Open: <question for the user> (<context>)

## Suggested skills
- `<skill>`: <why the next session needs it>

## Possible next step
<1-2 sentences, phrased as a suggestion to the user, e.g. "Könnte als Nächstes: ...">
<!-- handoff-ende -->
```

The last line marks where the handoff ends. Text after it in a pasted message is the user's own.

## PERSIST mode

**1. Scrub.** The file may be committed, and git history keeps it forever. Replace with `‹REDACTED: <what>›`: API keys and tokens, passwords, connection strings, private keys, values read from `.env`, and personal or customer data beyond what is needed. Prefer env-var names and paths. If you redacted something, add `> Security: N value(s) redacted.` at the top. If sensitive context is essential, use `brainstorms/sessions/private/` (gitignored) and point to it.

**2. Real values.** Get time from `date "+%Y-%m-%d %H:%M"`. `session-id` is the first 8 characters of the session UUID (scratchpad or transcript path), else `date "+%H%M%S"`. `branch` and `commit` come from `git branch --show-current` and `git rev-parse --short HEAD`; these two calls are the only allowed git audit.

**3. File.** `brainstorms/sessions/YYYY-MM-DD-HHmm-<topic-slug>.md`, 2-4 kebab-case words. Time and slug keep parallel terminals apart. If a file with this `session-id` exists, update it in place: one session, one file. Never touch `index.md`; shared files race across terminals.

**4. Frontmatter.**

```yaml
---
type: session-handoff
session-id: <8 chars>
topic: <same as the title>
started: <YYYY-MM-DD HH:mm>
updated: <YYYY-MM-DD HH:mm>
status: status/aktiv          # aktiv: continues · abgeschlossen: done, hidden from the start list · blockiert: waiting
branch: <branch>
commit: <short sha>
focus: <what the next session is for, if the user said so>   # otherwise omit
tags: [thema/<topic-slug>, status/aktiv]
---
```

`status` and its tag must agree. Set both to `status/abgeschlossen` when the topic is done, so the start list stays short. Add `firma/<ADO|OM|DO>` only if clear.

**5. Chat.** Print `Saved: <absolute path>`, then the full body verbatim, so the user can copy it, `/clear` and paste it back.

## Rules

- Absolute paths in the body; the next agent may sit elsewhere.
- Background shell IDs must be listed with their kill command; nothing else can find them.
- Write no memory from this skill.
- No retrospective, no praise, no emojis. Short, complete sentences, like an engineer handing over a shift.
- One suggestion under "Possible next step". The next session decides with the user.

## Related

- `/compact` is enough when you stay on the same task in the same window and nothing has to survive a `/clear`.
- `mattpocock-skills:handoff` writes a throwaway file to the OS temp folder. Use it for a one-off hand-over to another tool or a colleague; use this skill for project memory.
