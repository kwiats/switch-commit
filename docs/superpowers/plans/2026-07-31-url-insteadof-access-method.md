# URL insteadOf by Access Method Implementation Plan

> **For agentic workers:** Implement task-by-task with TDD. Do not commit `docs/superpowers/**`.

**Goal:** Make SSH/HTTPS profile access method control effective Git transport via `url.insteadOf` in generated profile config.

**Architecture:** Extend `GitConfigGenerator.profileConfig` to emit host-scoped `insteadOf` rules from `profile.hosts` and `accessMethod`. Reuse existing installer/`includeIf`. Add a `doctor` warning when folder vs global access methods conflict.

**Tech Stack:** Swift 6.2, SwitchCommitCore, SwitchCommitCoreTestRunner

---

### Task 1: Generator emits insteadOf for SSH profiles

**Files:**
- Modify: `Sources/SwitchCommitCore/GitConfigGenerator.swift`
- Test: `Sources/SwitchCommitCoreTestRunner/main.swift`

- [ ] Write failing tests for SSH profile insteadOf blocks
- [ ] Implement insteadOf generation for `.ssh`
- [ ] Verify tests pass

### Task 2: Generator emits insteadOf for HTTPS profiles

**Files:**
- Modify: `Sources/SwitchCommitCore/GitConfigGenerator.swift`
- Test: `Sources/SwitchCommitCoreTestRunner/main.swift`

- [ ] Write failing tests for HTTPS profile insteadOf blocks (and no sshCommand)
- [ ] Implement insteadOf generation for `.https`
- [ ] Verify tests pass

### Task 3: Doctor warns on access-method conflict

**Files:**
- Modify: `Sources/SwitchCommitCore/DiagnosticsService.swift` and/or `SwitchCommitSession.swift`
- Test: `Sources/SwitchCommitCoreTestRunner/main.swift`

- [ ] Write failing test for conflict warning
- [ ] Implement warning when resolved folder profile accessMethod differs from active global
- [ ] Verify tests pass

### Task 4: Docs + verify

**Files:**
- Modify: `README.md`
- Optionally: `docs/release-notes/` only if releasing

- [ ] Document insteadOf behavior under folder assignments / access method
- [ ] `swift run SwitchCommitCoreTestRunner && swift build`
