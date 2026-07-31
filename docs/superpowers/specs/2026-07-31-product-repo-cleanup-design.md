# Product repo cleanup design

Date: 2026-07-31  
Status: approved  
Approach: cleanup-only (no Sources / SPM restructure)

## Goal

Make this repository read as a product repo for Switch Commit: source, release tooling, landing site, and CI — without agent-process artifacts or local build clutter.

## In scope

1. Delete local ignored directories from this workspace:
   - `.worktrees/`
   - `.build/`
   - `dist/`
   - `.superpowers/`
2. Remove from version control:
   - entire `docs/superpowers/` (plans and specs, including this design doc once implementation lands)
   - `docs/future-features.md`
   - `docs/pull-request-description.md`
3. Remove legacy release scripts and README references:
   - `Scripts/migrate-legacy-releases.sh`
   - `Scripts/publish-legacy-bridge-appcast.sh`
4. Strengthen `.gitignore`:
   - keep existing entries for `.worktrees/`, `.superpowers/`, `.build/`, `dist/`
   - add `.DS_Store`
   - add `.vscode/` (do not commit the outdated local `launch.json`)
5. Update agent layout docs so they no longer point at `docs/superpowers/`:
   - `AGENTS.md`
   - `CLAUDE.md`

## Out of scope

- Moving or renaming `Sources/` targets
- Merging `AGENTS.md` and `CLAUDE.md` (both stay)
- Reworking GitHub Actions beyond path fixes if any break from deleted scripts
- Reorganizing `Scripts/` into subpackages beyond the two legacy deletions
- Changing app behavior or product features

## Target tree

```
/
├── Package.swift
├── Package.resolved
├── README.md
├── AGENTS.md
├── CLAUDE.md
├── .gitignore
├── Sources/
│   ├── SwitchCommitApp/
│   ├── SwitchCommitAppLogic/
│   ├── SwitchCommitCore/
│   ├── SwitchCommitCLI/
│   └── SwitchCommitCoreTestRunner/
├── Scripts/
│   ├── build-release.sh
│   ├── pr-checks.sh
│   ├── publish-release-channel.sh
│   ├── macos/cli-launch.sh
│   └── site-landing/
├── site/
├── docs/
│   └── release-notes/
└── .github/
```

## Execution

1. Branch: `codex/product-repo-cleanup`
2. Apply deletions and doc/gitignore updates
3. Verify no remaining references to removed paths in tracked files
4. Run `swift run SwitchCommitCoreTestRunner` and `swift build`
5. Commit, push, open draft PR

## Risks

- Low: no Swift source changes expected.
- Deleting `.worktrees/` removes local agent worktree copies (already gitignored).
- This design file lives under `docs/superpowers/` and will be deleted with that folder during implementation; the approved decisions are captured in the PR description.

## Success criteria

- Repo root and `docs/` contain only product-facing material listed in the target tree.
- Local ignored clutter directories are gone from this workspace.
- Legacy bridge/migrate scripts and README bridge note are gone.
- Tests and build still pass.
