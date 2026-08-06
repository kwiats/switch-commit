# Switch Commit CLI — safe commands for agents

Use only the commands below. Prefer `--json` for machine-readable output. Global flags also work on every subcommand: `--json`, `--no-color` (and `NO_COLOR`).

Profile references accept a display name or id (names are case-insensitive). Ambiguous names error with candidates.

## `version`

```bash
switch-commit version
switch-commit version --json
```

## `list` / `ls`

List profiles; the active profile is marked.

```bash
switch-commit list
switch-commit ls --json
```

## `status`

Active global profile plus folder-rule context for the current directory (or `--path`).

```bash
switch-commit status
switch-commit status --json
switch-commit status --path ~/Dev/acme --json
```

## `show`

Profile metadata only (no Keychain secret values).

```bash
switch-commit show work
switch-commit show work --json
```

## `doctor`

Local Git identity / managed-config checks only — no network host probes.

```bash
switch-commit doctor
switch-commit doctor --path ~/Dev/acme --json
```

## `use`

Switch the global active profile and apply managed Git/SSH config.

```bash
switch-commit use work
switch-commit use <profile-id>
```

## `folder list`

```bash
switch-commit folder list
switch-commit folder list --json
```

## `folder add`

Assign a profile to a folder. Path defaults to `.`; profile defaults to the active global profile; mode defaults to `single-repo` when `.git` exists, otherwise `folder-tree`.

```bash
switch-commit folder add
switch-commit folder add .
switch-commit folder add ~/Dev/acme --profile work
switch-commit folder add ~/Dev/acme --profile work --mode folder-tree
switch-commit folder add ~/Dev/solo-repo --profile personal --mode single-repo
```

`--yes` takes over an existing rule without prompting — only with clear user confirmation.

## `folder remove`

Remove by path or rule id.

```bash
switch-commit folder remove ~/Dev/acme
switch-commit folder remove <rule-id> --yes
```

Use `--yes` only after explicit user confirmation.

## Out of agent scope

Do **not** run: `add`, `edit`, `delete`, `update`, or bare interactive `switch-commit`.

For full CLI documentation (including those commands for humans), see the product README CLI section: https://github.com/kwiats/switch-commit#cli
