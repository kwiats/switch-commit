---
name: using-switch-commit
description: Use when the user needs to switch Git identity or GitHub account on macOS, check which Switch Commit profile is active, fix wrong git author/email, assign a profile to a folder, or mentions switch-commit / Switch Commit / work vs personal Git accounts.
---

# Using Switch Commit CLI

Switch Commit is a local-only macOS app + `switch-commit` CLI for switching Git identities globally and per folder. Prefer the CLI over hand-editing `~/.gitconfig` or `~/.ssh/config`.

## Safety contract (agent)

**Allowed:** `version`, `list`/`ls`, `status`, `show`, `doctor`, `use`, `folder list`, `folder add`, `folder remove`.

**Forbidden — refuse and redirect the user to the menu bar app or their own terminal:**

- `add`, `edit`, `delete`, `update`
- Bare interactive `switch-commit` (TTY menu)
- Guessing Keychain secrets or writing credentials into files/chat
- Replacing `~/.gitconfig` / `~/.ssh/config` wholesale

For command flags and examples, read [references/cli-safe-commands.md](references/cli-safe-commands.md).

## Workflow

1. **Verify CLI:** `switch-commit version`. If missing, tell the user to install via the DMG `Install Switch Commit.pkg` or Settings → General → **Install CLI**.
2. **Orient:** `switch-commit status --json` (add `--path` when inspecting another directory). Use `list --json` when choosing a profile.
3. **Mutate only with clear intent:** `use <profile>` or `folder add` / `folder remove`.
4. **Verify:** `status` and/or `doctor` (prefer `--json`).
5. Prefer `--json` for parsing. Never ask for or echo secret payloads (the CLI does not emit them).

If the profile name is ambiguous, show `list`/`status` and ask which profile — do not switch blindly.

## Common user intents

| User says | Agent does |
|---|---|
| Which account / wrong author? | `status --json`, optionally `doctor --json` |
| Switch to work/personal | `list --json` if needed → `use <profile>` → `status --json` |
| Use this folder with profile X | `folder add <path> --profile <name>` → `status --path <path> --json` |
| Remove folder assignment | `folder list --json` → `folder remove …` (add `--yes` only after explicit confirm) |
| Create/edit/delete profile or update app | Refuse; point to menu bar Settings / user-run CLI outside agent scope |
