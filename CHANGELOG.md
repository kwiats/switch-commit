# Changelog

All notable changes to Switch Commit are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.8] - 2026-08-02

### Highlights

- Settings → Check for Updates also syncs/repairs `/usr/local/bin/switch-commit` to the CLI inside the current app bundle (including when the app is already up to date).
- `switch-commit update` still installs the app and repairs the CLI, and now restarts a running Switch Commit menu bar app when possible.

### Fixes

- Settings uses a custom HStack sidebar instead of `NavigationSplitView`, so switching to Updates no longer blanks the detail pane.
- Managed-file backups no longer collide when the CLI or app reapplies config concurrently (unique backup names).
- Rewriting a managed file with identical content skips the backup and write, so read-heavy CLI commands stop growing the backups folder unnecessarily.

## [0.3.7] - 2026-08-01

### Highlights

- Selecting Updates in Settings no longer blanks the whole window (sidebar and content stay usable).
- Closing and reopening Settings recovers without quitting the app — each open installs a fresh Settings view.
- The Settings window is freely resizable, with a wider default size so Accounts labels and actions fit better.

## [0.3.6] - 2026-08-01

### Highlights

- Switching profiles surgically removes unmanaged `url.*.insteadOf` keys in `~/.gitconfig` that reverse the active profile rewrite (after backup); `doctor` still warns about remaining conflicts outside that file.
- SSH profiles no longer force `ssh -F ~/.ssh/config`, so a missing SSH config file no longer breaks Git push.
- `switch-commit update` checks the public appcast live, downloads the DMG (SHA-256 verified when available), installs the app, and repairs the CLI; other CLI commands can print a 12-hour cached update notice.
- Settings uses a sidebar (`NavigationSplitView`) so section tabs are no longer clipped by the title bar.
- Settings and the menu bar app reload folder rules from disk when opening Settings or becoming active, and before each Settings write, so `switch-commit folder add` / `folder remove` stay in sync and are not overwritten.

## [0.3.5] - 2026-08-01

### Highlights

- Starting the app or any `switch-commit` CLI command rewrites managed Git config from the current profiles and folder rules, so generator updates such as `url.insteadOf` apply without a manual profile switch.
- `switch-commit folder add` can omit path, profile, and mode: it uses the current directory, the active global profile, and `single-repo` when `.git` is present (otherwise `folder-tree`).

## [0.3.4] - 2026-07-31

### Highlights

- SSH and HTTPS profile access methods now drive Git transport through managed `url.insteadOf` rules, so folder assignments rewrite `https://` ↔ `git@` automatically without changing remotes in `.git/config`.
- SSH profiles continue to set `core.sshCommand` with the profile key, so HTTPS remotes in an assigned folder authenticate with that key instead of global HTTPS credentials.
- `switch-commit doctor` warns when a folder profile’s access method differs from the global profile, where accumulated `insteadOf` rules may conflict.

## [0.3.3] - 2026-07-31

### Highlights

- Folder rules from relative paths such as `.` now resolve to absolute paths, so Git `includeIf gitdir:` matches the real repository and per-folder identity switching works again.
- SSH connection tests use the selected profile’s key (`-i` with `IdentitiesOnly`), so a newly added key is not ignored in favor of the default agent identity.

## [0.3.2] - 2026-07-31

### Highlights

- Requires committed release notes at `docs/release-notes/vX.Y.Z.md` before a tagged release can publish. Missing notes fail the release channel instead of shipping an empty GitHub Release body.
- Always uploads the release-notes markdown asset and sets Sparkle `releaseNotesLink`, so Check for Updates can show the changelog.
- Syncs the GitHub Pages landing changelog and download CTA inside the Release Channel site metadata PR. This avoids the GitHub Actions limitation where `GITHUB_TOKEN`-created releases do not trigger a separate `release: published` workflow.
- Documents the v0.3.1 channel and docs changes that shipped without release notes because the notes file was missing.

## [0.3.1] - 2026-07-31

### Highlights

- Uploads Sparkle release notes as a GitHub Release markdown asset so appcast `releaseNotesLink` can point at a downloadable notes file.
- Expands CLI command reference in the README and surfaces the CLI on the public landing page.
- Aligns agent guides with worktree and Conventional Commit branch standards.
- Tightens `.gitignore` and removes legacy product-doc references and obsolete release scripts.
- Improves release site publish flow under main branch protection.

## [0.3.0] - 2026-07-31

### Highlights

- Moves the public Sparkle feed, GitHub Releases, and download landing page into `kwiats/switch-commit` (`https://kwiats.github.io/switch-commit/appcast.xml`). This build is the bridge for 0.2.x installs still checking the legacy channel.
- Adds the `switch-commit` CLI for listing, switching, creating, editing, and deleting Git profiles, managing folder rules, and running local diagnostics without opening the menu bar UI.
- Ships interactive profile selection when `switch-commit` runs with no arguments on a TTY; non-TTY invocations print usage instead of waiting for input.
- Supports machine-readable `--json` output and `--no-color` (respects `NO_COLOR`) for scripting and automation.
- Bundles the CLI inside `Switch Commit.app` and installs it to `/usr/local/bin/switch-commit` via `Install Switch Commit.pkg` in the release DMG.
- Adds Settings → General → Install CLI / Reinstall CLI to create or repair the `/usr/local/bin/switch-commit` symlink after drag-only app installs.
- Keeps the CLI on the same safety contract as the app: no telemetry, no background network calls, no secret payloads in JSON or stdout, and local-only `doctor` checks.

## [0.2.6] - 2026-07-31

### Highlights

- Adds folder account assignments in Settings → Accounts with folder tree and single-repo match modes.
- Generates Git `includeIf` rules for automatic per-folder identity without switching the global profile.
- Shows live folder context in the menu bar title and menu header for Finder, Terminal, iTerm2, Cursor, and VS Code.
- Falls back to the global active profile preview when Automation permission is missing or the frontmost path cannot be read.

## [0.2.5] - 2026-07-31

### Highlights

- Renames the shipping app and package surface to Switch Commit while keeping existing profile, Keychain, and Sparkle continuity identifiers.
- Publishes installer DMG artifacts (`SwitchCommit-vX.Y.Z-macOS.dmg`) with an Applications shortcut instead of ZIP archives.

## [0.2.0]

### Planned

- Introduces Switch Commit as the customer-facing product name.
- Adds a manual update path backed by a public release channel.
- Adds tag-triggered release CD that builds the app, publishes ZIP assets under `release/`, regenerates the Sparkle appcast, and publishes the public GitHub Pages release channel.
- Keeps source code private while publishing only signed distribution artifacts.
- Keeps update checks manual-only by contacting the public release channel only after a user click.
- Persists per-profile host connection status without secrets, and refreshes the active SSH profile after user-triggered profile switches.

## [0.1.1]

Stable release packaging the macOS app as a downloadable artifact.

### Co zawiera

- Release ZIP z natywna aplikacja `Git Account Switcher.app`.
- Powtarzalny skrypt `Scripts/build-release.sh`, ktory buduje release binary, sklada podpisany ad-hoc `.app` i generuje checksum SHA-256.
- Zachowany lokalny model bezpieczenstwa: brak telemetrii, brak automatycznych requestow sieciowych i brak sekretow w plikach profili.
- Jawne metody dostepu SSH/HTTPS dla profili, dzieki czemu uzytkownicy HTTPS i GitHub CLI credentials nie musza konfigurowac klucza SSH.

### Instalacja

1. Pobierz `GitAccountSwitcher-v0.1.1-macOS.zip` z GitHub Release.
2. Rozpakuj ZIP.
3. Przenies `Git Account Switcher.app` do katalogu `Applications`.
4. Uruchom aplikacje z `Applications`.

Jesli macOS zablokuje uruchomienie aplikacji pobranej z internetu, otworz `System Settings > Privacy & Security` i potwierdz uruchomienie aplikacji.

Wydanie nie jest jeszcze notarized przez Apple Developer ID, wiec na niektorych Macach pierwsze uruchomienie moze wymagac uzycia `Open` z menu kontekstowego Findera.

### Weryfikacja

```bash
swift run GitAccountSwitcherCoreTestRunner
swift build
Scripts/build-release.sh 0.1.1
```

Oczekiwany wynik:

- test runner konczy sie komunikatem `All 61 tests passed.`;
- `swift build` konczy sie statusem powodzenia;
- skrypt generuje `dist/v0.1.1/GitAccountSwitcher-v0.1.1-macOS.zip` i plik `.sha256`.

## [0.1.0]

Pierwsze wydanie MVP aplikacji macOS do lokalnego przełączania kont Git.

### Co zawiera

- Natywna aplikacja macOS uruchamiana jako menu bar tool.
- Swift Package z testowalnym rdzeniem `GitAccountSwitcherCore`.
- Modele profili Git i reguł folderów/repozytoriów.
- Secret-free `ProfileStore`, który zapisuje metadane profili bez sekretów.
- Generatory zarządzanych plików Git config i SSH config.
- Przełączanie globalnego profilu z menu zapisuje zarządzany `global.gitconfig` i dopina include'y w `~/.gitconfig`.
- `SafeFileWriter` ograniczający zapis do dozwolonych ścieżek i robiący backup przed nadpisaniem.
- Lokalna diagnostyka oparta o `git config --includes --show-origin`.
- Added local-only GitHub account discovery suggestions from Git, SSH, GitHub CLI config, and user-approved folder scans.
- Manualny status połączenia z hostem: czerwony dla nietestowanego lub niepołączonego profilu, pomarańczowy dla błędu testu lub konfiguracji, zielony dla udanego testu.
- Lista kont pokazuje ikonę providera, w tym GitHub dla profili z `github.com`.
- Opcjonalny autostart aplikacji po zalogowaniu, sterowany przełącznikiem `Launch at Login` w Settings.
- Granica Keychain z namespacowanymi identyfikatorami sekretów.

### Bezpieczeństwo

- Brak telemetrii, analytics i automatycznych requestów sieciowych.
- Autostart jest jawnie włączany przez użytkownika i używa macOS Login Items.
- Test połączenia z hostem uruchamia się tylko po kliknięciu `Test Connection`.
- Sekrety nie są zapisywane w JSON ani w generowanych configach.
- Testy używają tymczasowych katalogów i fake Keychain.
- Aplikacja nie nadpisuje całego `~/.gitconfig` ani całego `~/.ssh/config`; do `~/.gitconfig` dodaje tylko jawne include'y po backupie istniejącego pliku.

### Weryfikacja

```bash
swift run GitAccountSwitcherCoreTestRunner
swift build
```

Oczekiwany wynik:

- `All 47 tests passed.`
- `Build complete!`

### Następne kroki

- Pełny ekran zarządzania profilami.
- Diagnostyka wybranego folderu z UI.
- Folderowa diagnostyka wybranego repozytorium z UI.
