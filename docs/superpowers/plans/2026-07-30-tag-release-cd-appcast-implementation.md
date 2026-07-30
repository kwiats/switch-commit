# Tag Release CD Appcast Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add tag-triggered CD that builds Switch Commit releases, updates the public GitHub Pages appcast channel, stores assets under `release/`, and keeps release URLs consistent.

**Architecture:** Keep app bundle construction in `Scripts/build-release.sh`, add `Scripts/publish-release-channel.sh` for public channel mutation, and add `.github/workflows/release.yml` as orchestration. Existing local tests read these release files as text to enforce the publishing contract without making network calls.

**Tech Stack:** Swift 6.2 package, Bash, GitHub Actions on `macos-latest`, Sparkle 2 `generate_appcast`, GitHub Pages release channel repository.

---

### Task 1: Guard Release CD Contract

**Files:**
- Modify: `Sources/GitAccountSwitcherCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing contract tests**

Add tests that expect a tag workflow, release channel publish script, shared public URL base, and README release documentation.

- [ ] **Step 2: Verify tests fail**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: FAIL because `.github/workflows/release.yml` and `Scripts/publish-release-channel.sh` do not exist yet.

### Task 2: Add Release Channel Publisher

**Files:**
- Modify: `Scripts/build-release.sh`
- Create: `Scripts/publish-release-channel.sh`

- [ ] **Step 1: Update release build URL constants**

Derive `sparkle_feed_url` and `sparkle_artifact_url` from `https://kwiats.github.io/switch-commit-release-channel`, include `/release/` in the artifact URL, and write the artifact URL to `dist/vX.Y.Z/release-url.txt`.

- [ ] **Step 2: Add publisher script**

Create a script that validates inputs, copies ZIP/checksum/release notes into `release/` inside a checked-out release channel directory, finds Sparkle `generate_appcast`, and invokes it with `--ed-key-file -`, `--download-url-prefix .../release`, and `-o <release-channel-dir>/appcast.xml`.

- [ ] **Step 3: Verify tests pass for scripts**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: tests now pass for script contract pieces except the missing workflow/docs.

### Task 3: Add Tag Workflow And Docs

**Files:**
- Create: `.github/workflows/release.yml`
- Modify: `README.md`
- Modify: `docs/release-notes/v0.2.0.md`

- [ ] **Step 1: Add tag-triggered workflow**

Create a `Release Channel` workflow for `v*` tags. It runs PR checks, builds release artifacts, checks out `kwiats/switch-commit-release-channel`, publishes appcast contents, commits changes, and pushes.

- [ ] **Step 2: Document usage**

Update README release instructions with required secrets and `git tag vX.Y.Z && git push origin vX.Y.Z`.

- [ ] **Step 3: Verify all tests and build**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
swift build
```

Expected: both commands pass.
