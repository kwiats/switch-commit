# Access Method Profiles - Design

## Goal

Git Account Switcher must support users who use GitHub through SSH and users who use HTTPS credentials. A profile should have an explicit access method so the app does not assume an SSH key for every account.

This keeps the existing SSH flow intact while making HTTPS profiles first-class:

- no fake default SSH key for HTTPS imports,
- no SSH connection warning for HTTPS-only users,
- no `core.sshCommand` generated for HTTPS profiles,
- no automatic network checks.

## Scope

In scope:

- add an explicit profile access method with `ssh` and `https`,
- preserve existing profiles by decoding missing access method as `ssh`,
- include access method in local GitHub discovery candidates,
- infer access method from local-only signals where possible,
- allow the user to choose the access method in settings,
- generate profile Git config according to the selected access method,
- make connection status and `Test Connection` SSH-only.

Out of scope:

- GitHub OAuth,
- calling `gh auth status`, `gh api`, or GitHub APIs,
- storing HTTPS secret payloads in profile JSON,
- implementing a full credential helper,
- per-remote or per-host mixed access methods inside one profile.

## Model

Add:

```swift
public enum GitAccessMethod: String, Codable, Equatable, Sendable {
    case ssh
    case https
}
```

`GitProfile` gains `accessMethod: GitAccessMethod`.

Existing `profiles.json` files without `accessMethod` decode as `.ssh` to preserve the current behavior. For `.ssh`, `sshKeyPath` remains required. For `.https`, `sshKeyPath` may be empty because Git does not need an SSH identity.

`DetectedGitAccount` and `DetectionSignal` gain `accessMethods: [GitAccessMethod]`. This keeps detection honest when signals disagree.

## Detection Rules

Local-only signals infer access like this:

- `gh hosts.yml` with `git_protocol: ssh` suggests `ssh`,
- `gh hosts.yml` with `git_protocol: https` suggests `https`,
- SSH config or resolved SSH identity suggests `ssh`,
- `credential.https://github.com.username` and `credential.github.com.username` suggest `https`,
- `git@github.com:owner/repo.git` and `ssh://git@github.com/owner/repo.git` remotes suggest `ssh`,
- `https://github.com/owner/repo.git` remotes suggest `https`,
- generic GitHub CLI installed and global Git identity do not pick an access method by themselves.

When merged candidates contain both `ssh` and `https`, the candidate should carry both methods and include a warning that local data points to more than one access method. The imported profile defaults to `ssh` only when an SSH key path is known; otherwise it defaults to `https`.

## Git Config Generation

Every profile still writes:

```gitconfig
[user]
    name = ...
    email = ...
```

SSH profiles also write:

```gitconfig
[core]
    sshCommand = ssh -i '<key>' -F ~/.ssh/config
```

HTTPS profiles do not write `core.sshCommand`.

## UI

The account form adds an access method picker with `SSH` and `HTTPS`.

For `SSH`:

- show the SSH key field,
- allow `Test Connection`,
- derive connection status from manual SSH test results as today.

For `HTTPS`:

- hide or disable the SSH key field,
- do not run SSH connection tests,
- show a neutral status such as `Uses HTTPS credentials.`,
- keep access reset available for `httpsCredentialRef`.

Detected account rows show the inferred access method. If both methods were detected, they show `SSH, HTTPS` and the warning text.

## Safety

The change preserves all existing safety invariants:

- profile JSON may store metadata and credential references only,
- HTTPS secrets are never stored in JSON,
- detection remains read-only,
- no automatic network checks are introduced,
- generated config remains under managed files,
- user-owned Git and SSH config files are not replaced.

## Testing

Core tests cover:

- `GitProfile` defaults missing `accessMethod` to `ssh`,
- HTTPS profiles may have an empty SSH key,
- SSH profiles still reject an empty SSH key,
- Git config generation includes `core.sshCommand` only for SSH,
- `gh hosts.yml` parses `git_protocol`,
- remote parsing distinguishes SSH and HTTPS access,
- detected account merging preserves and warns about conflicting access methods,
- importing an HTTPS detected account does not synthesize an SSH key.

App logic tests cover:

- HTTPS profiles report a neutral HTTPS status without SSH test results,
- testing connection for an HTTPS selected profile does not run SSH,
- updating the selected access method persists through the profile manager.
