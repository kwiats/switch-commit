# Dodaj pierwszą wersję macOS Git Account Switcher

## Cel

Ten PR dodaje pierwszą działającą bazę aplikacji macOS do przełączania kont Git. Aplikacja jest projektowana jako lokalne narzędzie z menu bar, z testowalnym rdzeniem odpowiedzialnym za profile, konfigurację Git/SSH, diagnostykę i bezpieczny zapis plików.

## Co zawiera

- Swift Package z biblioteką `GitAccountSwitcherCore` i aplikacją `GitAccountSwitcherApp`.
- Minimalny macOS menu bar app oparty o `MenuBarExtra`.
- Modele profili Git i reguł folderów/repozytoriów.
- Secret-free `ProfileStore`, który zapisuje tylko metadane i referencje do Keychain.
- Generatory zarządzanych plików Git config i SSH config.
- Globalne przełączanie profilu z menu zapisujące zarządzany `global.gitconfig` i include'y w `~/.gitconfig`.
- `SafeFileWriter`, który ogranicza zapis do dozwolonych katalogów i robi backup przed nadpisaniem.
- Lokalna diagnostyka przez `git config --show-origin`, bez automatycznych wyjść do sieci.
- Granica Keychain: namespacowane identyfikatory sekretów i fake store do testów.
- Dokumentacja modelu bezpieczeństwa i plan implementacji.

## Bezpieczeństwo

- Brak telemetrii, analytics, crash uploadów i automatycznych requestów sieciowych.
- Sekrety nie trafiają do JSON ani generowanych configów.
- Automatyczna diagnostyka wykonuje tylko lokalne komendy `git config --show-origin`.
- Testy używają tymczasowych katalogów i fake Keychain.
- Zapis zarządzanych plików jest ograniczony do jawnie dozwolonych managed roots.
- `~/.gitconfig` dostaje tylko jawne include'y do zarządzanych plików, z backupem przed zmianą istniejącego pliku.

## Jak przetestować lokalnie

1. Przejdź do worktree:

```bash
cd "/Users/pawelkwiatkowski/Documents/New project/.worktrees/build-macos-git-account-switcher"
```

2. Uruchom testy rdzenia:

```bash
swift run GitAccountSwitcherCoreTestRunner
```

Oczekiwany wynik: `All 42 tests passed.`

3. Zbuduj aplikację:

```bash
swift build
```

Oczekiwany wynik: `Build complete!`

4. Uruchom aplikację menu bar:

```bash
swift run GitAccountSwitcherApp
```

Oczekiwany wynik: ikona aplikacji pojawia się w górnym pasku macOS. Po kliknięciu widać aktywny profil, pozycję diagnostyki lokalnej, ustawienia i quit.

5. Przełącz konto z listy profili w menu bar.

Oczekiwany wynik: `~/.config/git-account-switcher/global.gitconfig` zawiera `user.name` i `user.email` wybranego profilu, a `~/.gitconfig` zawiera include'y do `global.gitconfig` i `rules.gitconfig`.

## Weryfikacja wykonana

- `swift run GitAccountSwitcherCoreTestRunner` -> 42/42 testy pass.
- `swift build` -> build zakończony sukcesem.

## Następne kroki po merge

- Dodać pełny ekran zarządzania profilami.
- Dodać diagnostykę wybranego folderu z UI.
- Dodać manualny test SSH uruchamiany tylko na żądanie użytkownika.
