# Switch Commit agent plugin

Teach Claude Code and Codex how to use the `switch-commit` CLI safely for end users: inspect identity, switch the active profile, and manage folder assignments.

This pack does **not** let agents create/edit/delete profiles or run `switch-commit update`. Those stay in the menu bar app or a user-run terminal.

## Requirements

- macOS with Switch Commit installed
- `switch-commit` on `PATH` (DMG `Install Switch Commit.pkg`, or Settings → General → **Install CLI**)

## What’s included

```
agent-plugins/switch-commit/
├── .claude-plugin/plugin.json
├── .codex-plugin/plugin.json
└── skills/using-switch-commit/
    ├── SKILL.md
    └── references/cli-safe-commands.md
```

## Install — Claude Code

From a clone of this repository (or an extracted Release zip of this directory):

```bash
claude --plugin-dir /path/to/switch-commit/agent-plugins/switch-commit
```

Or add the directory as a local plugin in Claude Code’s plugin settings, pointing at `agent-plugins/switch-commit`.

## Install — Codex

**Option A — plugin pack:** load this directory if your Codex build supports `.codex-plugin/plugin.json` (skills path: `./skills/`).

**Option B — portable skill:** copy or symlink the skill folder into your Codex skills directory:

```bash
mkdir -p ~/.agents/skills
ln -s /path/to/switch-commit/agent-plugins/switch-commit/skills/using-switch-commit \
  ~/.agents/skills/using-switch-commit
```

Exact Codex skill paths can vary by install; the skill itself is a standard `SKILL.md` directory.

## What the skill allows

| Action | Commands |
|---|---|
| Inspect | `version`, `list`, `status`, `show`, `doctor` |
| Switch | `use <profile>` |
| Folder rules | `folder list`, `folder add`, `folder remove` |

Prefer `--json` when parsing output. After changes, re-check with `status` / `doctor`.

## Full CLI docs

Human-facing reference (including create/edit/delete/update): [README.md § CLI](../../README.md#cli).

## Publishing notes

- Source of truth: this directory in the product repo
- Optional later: zip as a GitHub Release asset; Claude marketplace listing
