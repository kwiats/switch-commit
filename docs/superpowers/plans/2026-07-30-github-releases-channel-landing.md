# GitHub Releases Channel Landing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish Switch Commit DMG assets via GitHub Releases on `switch-commit-release-channel`, keep Pages lean (`appcast.xml`, `version.txt`, templated `index.html`), and stop storing artifacts in `release/` / `releases/`.

**Architecture:** Source repo owns the landing template and publish script. Tag CD builds the DMG, creates a channel GitHub Release, generates a latest-only Sparkle appcast with Releases download URLs, writes `version.txt`, renders `index.html`, deletes folder leftovers, then commits Pages.

**Tech Stack:** bash, `gh`, Sparkle `generate_appcast`, GitHub Actions, `SwitchCommitCoreTestRunner` contract tests.

---

### Task 1: Update contract tests

**Files:**
- Modify: `Sources/SwitchCommitCoreTestRunner/main.swift`

- [ ] Change build-release artifact URL expectation to GitHub Releases download URL
- [ ] Change publish expectations: `gh release`, staging appcast, `version.txt`, template render, no Pages `release/` copy
- [ ] Extend README/workflow expectations for Releases + `GH_TOKEN` / `RELEASE_CHANNEL_TOKEN`
- [ ] Run tests and confirm they fail before implementation

### Task 2: Landing template

**Files:**
- Create: `docs/release-channel/index.html`

- [ ] Copy current channel landing and replace version/download bits with `__VERSION__`, `__VERSION_TAG__`, `__DMG_URL__`, `__SHA256_URL__`
- [ ] Update install copy from ZIP to DMG

### Task 3: Scripts + workflow + README

**Files:**
- Modify: `Scripts/build-release.sh`
- Modify: `Scripts/publish-release-channel.sh`
- Modify: `.github/workflows/release.yml`
- Modify: `README.md`

- [ ] Point `sparkle_artifact_url` at Releases download URL
- [ ] Rewrite publish: create/upload release, stage DMG for appcast, write `version.txt`, render template, `rm -rf release releases`
- [ ] Pass `GH_TOKEN: ${{ secrets.RELEASE_CHANNEL_TOKEN }}` into publish step
- [ ] Document new model in README

### Task 4: Verify and ship

- [ ] `swift run SwitchCommitCoreTestRunner`
- [ ] `swift build`
- [ ] Commit, push branch, open draft PR
