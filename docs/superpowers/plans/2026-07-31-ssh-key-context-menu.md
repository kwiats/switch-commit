# SSH Key Context Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Settings SSH key text field with a menu of discovered local keys plus Choose File / Enter Path escape hatches.

**Architecture:** Add pure `SSHKeyDiscovery` in `SwitchCommitCore` (injectable home directory). Expose discovered paths from `AppViewModel`. Replace the SSH key `TextField` in `SettingsView` with a SwiftUI `Menu`, `NSOpenPanel`, and an enter-path alert.

**Tech Stack:** Swift 6.2, SwiftUI/AppKit, Foundation, `SwitchCommitCoreTestRunner`

**Spec:** `docs/superpowers/specs/2026-07-31-ssh-key-context-menu-design.md`

---

## File Structure

- Create: `Sources/SwitchCommitCore/SSHKeyDiscovery.swift` — discover/dedup/sort private key paths
- Modify: `Sources/SwitchCommitCoreTestRunner/main.swift` — discovery tests
- Modify: `Sources/SwitchCommitAppLogic/AppViewModel.swift` — expose `availableSSHKeyPaths` + refresh
- Modify: `Sources/SwitchCommitApp/SettingsView.swift` — menu UI + open panel + enter-path alert

---

### Task 1: SSHKeyDiscovery (TDD)

**Files:**
- Create: `Sources/SwitchCommitCore/SSHKeyDiscovery.swift`
- Modify: `Sources/SwitchCommitCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing discovery tests**

Add these cases near other SSH/discovery tests in `main.swift`:

```swift
("ssh key discovery lists private keys and skips junk", {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sshDirectory = temporaryDirectory.appendingPathComponent(".ssh", isDirectory: true)
    try FileManager.default.createDirectory(at: sshDirectory, withIntermediateDirectories: true)
    try Data("private".utf8).write(to: sshDirectory.appendingPathComponent("id_ed25519"))
    try Data("private".utf8).write(to: sshDirectory.appendingPathComponent("id_rsa"))
    try Data("public".utf8).write(to: sshDirectory.appendingPathComponent("id_ed25519.pub"))
    try Data("config".utf8).write(to: sshDirectory.appendingPathComponent("config"))
    try Data("hosts".utf8).write(to: sshDirectory.appendingPathComponent("known_hosts"))
    try Data("auth".utf8).write(to: sshDirectory.appendingPathComponent("authorized_keys"))
    try FileManager.default.createDirectory(
        at: sshDirectory.appendingPathComponent("somedir", isDirectory: true),
        withIntermediateDirectories: true
    )

    let paths = SSHKeyDiscovery(homeDirectory: temporaryDirectory).discoverKeyPaths()
    try expect(paths == ["~/.ssh/id_ed25519", "~/.ssh/id_rsa"], "should list private keys sorted by basename")
}),
("ssh key discovery includes IdentityFile paths from config and managed include", {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sshDirectory = temporaryDirectory.appendingPathComponent(".ssh", isDirectory: true)
    try FileManager.default.createDirectory(at: sshDirectory, withIntermediateDirectories: true)
    try Data("private".utf8).write(to: sshDirectory.appendingPathComponent("id_ed25519"))
    try """
    Host github.com
        IdentityFile ~/.ssh/id_ed25519
        IdentityFile ~/.ssh/id_work
    """.write(to: sshDirectory.appendingPathComponent("config"), atomically: true, encoding: .utf8)
    try Data("private".utf8).write(to: sshDirectory.appendingPathComponent("id_work"))
    try """
    Host gitlab.com
        IdentityFile ~/.ssh/id_gitlab
    """.write(
        to: sshDirectory.appendingPathComponent("git-account-switcher.conf"),
        atomically: true,
        encoding: .utf8
    )
    try Data("private".utf8).write(to: sshDirectory.appendingPathComponent("id_gitlab"))

    let paths = SSHKeyDiscovery(homeDirectory: temporaryDirectory).discoverKeyPaths()
    try expect(
        paths == ["~/.ssh/id_ed25519", "~/.ssh/id_gitlab", "~/.ssh/id_work"],
        "should merge directory keys and IdentityFile entries with stable dedup/sort"
    )
}),
("ssh key discovery returns empty list when ssh directory is missing", {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let paths = SSHKeyDiscovery(homeDirectory: temporaryDirectory).discoverKeyPaths()
    try expect(paths.isEmpty, "missing .ssh should yield empty list")
}),
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift run SwitchCommitCoreTestRunner`
Expected: compile failure or FAIL because `SSHKeyDiscovery` does not exist.

- [ ] **Step 3: Implement `SSHKeyDiscovery`**

Create `Sources/SwitchCommitCore/SSHKeyDiscovery.swift`:

```swift
import Foundation

public struct SSHKeyDiscovery: Sendable {
    private let homeDirectory: URL

    private static let excludedExactNames: Set<String> = [
        "config",
        "known_hosts",
        "authorized_keys"
    ]

    private static let excludedPrefixes = [
        "config.",
        "known_hosts.",
        "authorized_keys."
    ]

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    public func discoverKeyPaths() -> [String] {
        var candidates = Set<String>()
        candidates.formUnion(directoryPrivateKeyPaths())
        candidates.formUnion(identityFilePaths(named: "config"))
        candidates.formUnion(identityFilePaths(named: "git-account-switcher.conf"))

        return candidates.sorted { lhs, rhs in
            let leftName = URL(fileURLWithPath: expandHome(lhs)).lastPathComponent
            let rightName = URL(fileURLWithPath: expandHome(rhs)).lastPathComponent
            if leftName != rightName {
                return leftName.localizedStandardCompare(rightName) == .orderedAscending
            }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    private func directoryPrivateKeyPaths() -> Set<String> {
        let sshDirectory = homeDirectory.appendingPathComponent(".ssh", isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: sshDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var paths = Set<String>()
        for url in contents {
            guard isIncludedPrivateKeyFile(url) else { continue }
            paths.insert(displayPath(for: url))
        }
        return paths
    }

    private func identityFilePaths(named fileName: String) -> Set<String> {
        let configURL = homeDirectory
            .appendingPathComponent(".ssh", isDirectory: true)
            .appendingPathComponent(fileName)
        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else {
            return []
        }

        var paths = Set<String>()
        for line in content.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let fields = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard fields.count == 2, fields[0].lowercased() == "identityfile" else { continue }
            let raw = String(fields[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard !raw.isEmpty else { continue }
            let expanded = expandHome(raw)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
                  !isDirectory.boolValue
            else {
                continue
            }
            paths.insert(displayPath(for: URL(fileURLWithPath: expanded)))
        }
        return paths
    }

    private func isIncludedPrivateKeyFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name.hasSuffix(".pub") { return false }
        if Self.excludedExactNames.contains(name) { return false }
        if Self.excludedPrefixes.contains(where: { name.hasPrefix($0) }) { return false }

        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
        guard values?.isDirectory != true, values?.isRegularFile == true else {
            return false
        }
        return true
    }

    private func displayPath(for url: URL) -> String {
        let standardized = url.standardizedFileURL.path
        let homePath = homeDirectory.standardizedFileURL.path
        if standardized == homePath || standardized.hasPrefix(homePath + "/") {
            let suffix = String(standardized.dropFirst(homePath.count))
            return "~" + suffix
        }
        return standardized
    }

    private func expandHome(_ path: String) -> String {
        if path == "~" {
            return homeDirectory.path
        }
        if path.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(path.dropFirst(2))).path
        }
        return (path as NSString).expandingTildeInPath
    }
}
```

Note: for `IdentityFile` entries that point at paths under the injectable `homeDirectory`, prefer `~/...` display paths. Do not require files outside the fixture to exist in tests; only include IdentityFile paths that exist as regular files.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift run SwitchCommitCoreTestRunner`
Expected: all tests PASS, including the new SSH key discovery cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwitchCommitCore/SSHKeyDiscovery.swift Sources/SwitchCommitCoreTestRunner/main.swift
git commit -m "feat: discover local SSH private keys for settings picker"
```

---

### Task 2: AppViewModel API

**Files:**
- Modify: `Sources/SwitchCommitAppLogic/AppViewModel.swift`

- [ ] **Step 1: Add published discovery state and refresh helper**

Near other `@Published` settings properties, add:

```swift
@Published public private(set) var availableSSHKeyPaths: [String] = []
```

Add private discovery dependency (or construct on demand):

```swift
private let sshKeyDiscovery: SSHKeyDiscovery
```

Wire default `SSHKeyDiscovery()` in initializers that construct the view model. Add:

```swift
public func refreshAvailableSSHKeyPaths() {
    availableSSHKeyPaths = sshKeyDiscovery.discoverKeyPaths()
}
```

Call `refreshAvailableSSHKeyPaths()` from `refreshAvailableSSHKeyPaths` consumers in Settings (on appear / before menu use). Keep `updateSelectedProfileSSHKeyPath` unchanged — it already maps validation failures to `settingsMessage`.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Sources/SwitchCommitAppLogic/AppViewModel.swift
git commit -m "feat: expose discovered SSH keys from AppViewModel"
```

---

### Task 3: Settings SSH key menu UI

**Files:**
- Modify: `Sources/SwitchCommitApp/SettingsView.swift`

- [ ] **Step 1: Replace SSH key TextField with Menu + alert state**

Add state:

```swift
@State private var isShowingSSHKeyPathAlert = false
@State private var sshKeyPathDraft = ""
```

Replace the SSH key `GridRow` body with a menu control:

```swift
if viewModel.selectedProfile?.accessMethod != .https {
    GridRow {
        Text("SSH key")
            .foregroundStyle(.secondary)
        Menu {
            ForEach(viewModel.availableSSHKeyPaths, id: \.self) { path in
                Button {
                    viewModel.updateSelectedProfileSSHKeyPath(path)
                } label: {
                    HStack {
                        Text(path)
                        if viewModel.selectedProfile?.sshKeyPath == path {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button("Choose File...") {
                chooseSSHKeyFile()
            }
            Button("Enter Path...") {
                sshKeyPathDraft = viewModel.selectedProfile?.sshKeyPath ?? ""
                isShowingSSHKeyPathAlert = true
            }
        } label: {
            HStack {
                Text(sshKeyMenuTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color(nsColor: .separatorColor))
            )
        }
        .menuStyle(.borderlessButton)
        .onAppear {
            viewModel.refreshAvailableSSHKeyPaths()
        }
    }
}
```

Helpers:

```swift
private var sshKeyMenuTitle: String {
    let path = viewModel.selectedProfile?.sshKeyPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return path.isEmpty ? "Choose SSH key" : path
}

private func chooseSSHKeyFile() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".ssh", isDirectory: true)
    if panel.runModal() == .OK, let url = panel.url {
        viewModel.updateSelectedProfileSSHKeyPath(url.path)
        viewModel.refreshAvailableSSHKeyPaths()
    }
}
```

Attach alert on the accounts tab / settings root:

```swift
.alert("Enter SSH Key Path", isPresented: $isShowingSSHKeyPathAlert) {
    TextField("SSH key path", text: $sshKeyPathDraft)
    Button("Cancel", role: .cancel) {}
    Button("OK") {
        viewModel.updateSelectedProfileSSHKeyPath(sshKeyPathDraft)
        viewModel.refreshAvailableSSHKeyPaths()
    }
} message: {
    Text("Enter a path to a private SSH key.")
}
```

Also refresh available keys after selecting a discovered menu item is optional; discovery list does not depend on selection.

- [ ] **Step 2: Build and run tests**

Run:

```bash
swift run SwitchCommitCoreTestRunner
swift build
```

Expected: all tests PASS; build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/SwitchCommitApp/SettingsView.swift
git commit -m "feat: pick SSH keys from settings context menu"
```

---

### Task 4: Docs touch-up (if needed)

**Files:**
- Modify: `README.md` only if Settings SSH key UX is documented there

- [ ] **Step 1: Grep README for SSH key field wording**
- [ ] **Step 2: Update one sentence if the text field is mentioned**
- [ ] **Step 3: Commit only if changed**

---

## Spec Coverage Check

| Spec requirement | Task |
| --- | --- |
| Discover `~/.ssh` private keys | Task 1 |
| Include IdentityFile from config + managed include | Task 1 |
| Dedup/sort/missing-dir empty list | Task 1 |
| AppViewModel exposure | Task 2 |
| Menu with checkmark + Choose File + Enter Path alert | Task 3 |
| Persist via existing updater / settings messages | Task 2–3 |
| No network / no secret payloads | Task 1 (paths only) |
