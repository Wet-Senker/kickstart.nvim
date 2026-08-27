# NeoVim Texttools agent instructions

This repository is a client of the Texttools Python core. Before any
non-trivial analysis, design decision, or code change, read the canonical
principles in:

`/Users/nickdevries/workspace/texttools/ARCHITECTUURPRINCIPES.md`

Also read the relevant sections of the Texttools `DECISIONS.md` and
`VERBETERPLAN.md`, and inspect both repositories when a workflow crosses the
Lua/Python boundary.

Mandatory working rules:

- Keep NeoVim a thin but first-class client. Do not place new journalistic,
  edition, planning, publication, or integration rules only in Lua when they
  belong in a shared callable Python action.
- A NeoVim keymap and a future visual button must be able to invoke the same
  domain action and receive the same typed result.
- Keep UI work asynchronous and prevent late callbacks from overwriting newer
  buffer edits.
- Preserve headless testability and avoid hidden UI-only state as the sole
  durable source of truth.
- Report scalability, compatibility, and performance impact. Explicitly call
  out extra AI calls, subprocesses, scans, waits, or cross-process roundtrips.
- Prefer small client adapters and explicit contracts over duplicating Python
  tables, validation, resolution, or workflow state in Lua.
- Do not add future-facing abstraction without a current responsibility and a
  tested boundary.

Run the headless NeoVim suite for relevant changes and the Texttools Python
suite when shared contracts or publication behavior are affected.
