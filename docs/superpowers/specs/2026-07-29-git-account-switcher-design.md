# Git Account Switcher - Design

## Cel

Tworzymy natywna aplikacje macOS dzialajaca z gornego paska menu, ktora pozwala przelaczac konta Git bez recznego edytowania konfiguracji, dopisywania suffixow hostow ani pamietania, ktory projekt uzywa ktorej tozsamosci.

Aplikacja obsluguje dwa tryby:

- globalny profil domyslny dla calego systemu,
- reguly folderow lub konkretnych repozytoriow, ktore zawsze wymuszaja wybrany profil.

Profil obejmuje pelna tozsamosc Git: `user.name`, `user.email`, klucz SSH, hosty Git oraz opcjonalne dane HTTPS/token zapisane w macOS Keychain.

## Zakres pierwszej wersji

Pierwsza wersja skupia sie na bezpiecznym zarzadzaniu konfiguracja Git i SSH:

- natywna aplikacja Swift/SwiftUI jako menu bar tool,
- lista profili Git,
- szybkie przelaczanie profilu globalnego,
- przypisywanie profili do folderow lub repozytoriow,
- generowanie zarzadzanych plikow konfiguracyjnych,
- test diagnostyczny pokazujacy, ktory profil zadziala dla wybranego folderu,
- integracja z macOS Keychain dla sekretow,
- backup plikow dotykanych przez aplikacje.

Aplikacja nie bedzie nadpisywac calego `~/.gitconfig` ani calego `~/.ssh/config`. Bedzie dodawac tylko wlasne include'y oraz zarzadzac wlasnymi plikami.

## Architektura

### Warstwa aplikacji

Aplikacja bedzie natywnym projektem macOS w Swift/SwiftUI.

Glowne elementy:

- `MenuBarController`: status bar item, lista profili, szybkie przelaczenie globalne.
- `SettingsWindow`: ekran zarzadzania profilami, folder rules i diagnostyka.
- `ProfileStore`: lokalny zapis metadanych profili bez sekretow.
- `KeychainStore`: zapis tokenow i ewentualnych danych HTTPS w macOS Keychain.
- `GitConfigManager`: zapis i walidacja zarzadzanych plikow Git config.
- `SSHConfigManager`: zapis i walidacja zarzadzanego pliku SSH config.
- `DiagnosticsService`: uruchamianie komend kontrolnych i prezentacja wyniku uzytkownikowi.

### Dane profilu

Profil zawiera:

- `id`: stabilny identyfikator,
- `displayName`: nazwa widoczna w menu, np. "Prywatne" albo "Firma",
- `gitUserName`: wartosc `user.name`,
- `gitUserEmail`: wartosc `user.email`,
- `sshKeyPath`: sciezka do klucza prywatnego,
- `hosts`: lista hostow, np. `github.com`, `gitlab.com`,
- `httpsCredentialRef`: opcjonalny identyfikator wpisu w Keychain,
- `isDefault`: czy profil jest globalnym domyslnym.

Sekrety nie sa trzymane w pliku profili. W pliku lokalnym zapisujemy tylko referencje do Keychain.

### Reguly folderow

Regula folderu zawiera:

- `path`: folder albo konkretne repozytorium,
- `profileId`: profil przypisany do tego miejsca,
- `matchMode`: `folderTree` albo `singleRepo`,
- `enabled`: czy regula jest aktywna.

Dla reguly folderu aplikacja generuje wpis `includeIf` w zarzadzanym pliku Git config. Przyklad:

```gitconfig
[includeIf "gitdir:/Users/pawel/Work/**"]
    path = /Users/pawel/.config/git-account-switcher/profiles/work.gitconfig
```

## Pliki zarzadzane przez aplikacje

### Git

Aplikacja utworzy katalog:

```text
~/.config/git-account-switcher/
```

W nim beda:

```text
global.gitconfig
rules.gitconfig
profiles/<profile-id>.gitconfig
backups/
```

`global.gitconfig` zawiera aktualny globalny profil. `rules.gitconfig` zawiera reguly `includeIf`. Kazdy profil ma osobny plik w `profiles/`.

W `~/.gitconfig` aplikacja doda tylko jedna sekcje include. Kolejnosc jest wazna: najpierw profil globalny, potem reguly folderow, aby bardziej szczegolowe reguly mogly nadpisac domyslne wartosci.

```gitconfig
[include]
    path = ~/.config/git-account-switcher/global.gitconfig
    path = ~/.config/git-account-switcher/rules.gitconfig
```

Jesli `~/.gitconfig` juz istnieje, aplikacja zrobi backup przed pierwsza zmiana.

### SSH

Aplikacja utworzy plik:

```text
~/.ssh/git-account-switcher.conf
```

W `~/.ssh/config` doda tylko:

```sshconfig
Include ~/.ssh/git-account-switcher.conf
```

Kazdy profil moze wygenerowac wpisy hostow z odpowiednim `IdentityFile`. Gdy kilka profili korzysta z tego samego hosta, np. `github.com`, aplikacja preferuje konfiguracje zgodna z Git `core.sshCommand` w pliku profilu. Dzieki temu folder przypisany do profilu uzywa wlasciwego klucza bez wymuszania na uzytkowniku recznego dopisywania aliasu hosta w URL remote.

Przyklad profilu:

```gitconfig
[user]
    name = Jan Kowalski
    email = jan@firma.com
[core]
    sshCommand = ssh -i ~/.ssh/id_ed25519_work -F ~/.ssh/config
```

## Glowne przeplywy

### Dodanie profilu

1. Uzytkownik wybiera "Add Profile".
2. Podaje nazwe profilu, `user.name`, `user.email`.
3. Wybiera istniejacy klucz SSH albo prosi aplikacje o wygenerowanie nowego.
4. Opcjonalnie dodaje token HTTPS, ktory trafia do Keychain.
5. Aplikacja wykonuje test konfiguracji i pokazuje wynik.
6. Profil zostaje zapisany.

### Przelaczenie profilu globalnego

1. Uzytkownik klika ikone w menu bar.
2. Wybiera profil.
3. Aplikacja aktualizuje `global.gitconfig`.
4. Menu pokazuje nowy aktywny profil.
5. Diagnostyka moze pokazac, ze niektore foldery maja wlasne reguly i nie beda korzystac z globalnego profilu.

### Przypisanie profilu do folderu

1. Uzytkownik wybiera folder albo repozytorium.
2. Wybiera profil.
3. Aplikacja tworzy lub aktualizuje regule `includeIf`.
4. Aplikacja uruchamia diagnostyke `git config --show-origin user.email` dla wskazanego folderu.
5. Uzytkownik widzi potwierdzenie, jaki profil bedzie aktywny w tym miejscu.

### Diagnostyka

Dla wskazanego folderu aplikacja pokazuje:

- wynik `git config --show-origin user.name`,
- wynik `git config --show-origin user.email`,
- aktywny `core.sshCommand`,
- host i remote URL,
- wynik testu SSH, jesli host jest wspierany,
- ostrzezenia, np. brak klucza albo konflikt reguly.

## Bezpieczenstwo i odzyskiwanie

Aplikacja stosuje zasady:

- nie nadpisuje calego `~/.gitconfig`,
- nie nadpisuje calego `~/.ssh/config`,
- zapisuje sekrety tylko w macOS Keychain,
- przed pierwsza zmiana tworzy backup dotknietych plikow,
- zapisuje tylko wlasne pliki zarzadzane,
- pokazuje podglad zmian przy pierwszym wlaczeniu integracji,
- pozwala wylaczyc integracje bez usuwania profili.

Backupi trafiaja do:

```text
~/.config/git-account-switcher/backups/
```

## Obsluga bledow

Aplikacja powinna pokazywac jasne komunikaty dla:

- braku dostepu do pliku config,
- nieistniejacego klucza SSH,
- niepoprawnej sciezki folderu,
- konfliktu wielu regul dla tego samego repo,
- nieudanego testu SSH,
- odmowy dostepu do Keychain,
- nieprawidlowego formatu istniejacego configu.

Bledy zapisu sa blokujace. Bledy diagnostyczne nie musza blokowac zapisu profilu, ale powinny byc widoczne jako ostrzezenia.

## Testowanie

Testy jednostkowe powinny objac:

- generowanie plikow `.gitconfig`,
- generowanie reguly `includeIf`,
- wybor profilu dla folderu,
- serializacje profili bez sekretow,
- walidacje sciezek kluczy SSH,
- zachowanie backupow.

Testy integracyjne powinny uzywac tymczasowego katalogu `HOME`, aby sprawdzic, ze aplikacja nie dotyka prawdziwej konfiguracji uzytkownika.

Manualna weryfikacja pierwszej wersji:

- dodanie profilu prywatnego,
- dodanie profilu firmowego,
- przelaczenie globalnego profilu,
- przypisanie profilu do folderu,
- potwierdzenie przez `git config --show-origin user.email`,
- potwierdzenie przez `GIT_SSH_COMMAND` lub `core.sshCommand`,
- sprawdzenie, ze backup zostal utworzony.

## Poza zakresem pierwszej wersji

Poza pierwsza wersja zostaja:

- synchronizacja profili przez iCloud,
- automatyczne wykrywanie wszystkich repozytoriow na dysku,
- integracje z GUI Git clients,
- import kont bezposrednio z GitHub/GitLab API,
- zarzadzanie organizacjami i uprawnieniami.

## Decyzje zatwierdzone

- Aplikacja bedzie natywna dla macOS.
- Aplikacja bedzie dzialac w gornym pasku menu.
- Profil obejmuje `user.name`, `user.email`, SSH i opcjonalne HTTPS/Keychain.
- Wspieramy zarowno profil globalny, jak i reguly folderow/repozytoriow.
- Konfiguracja opiera sie na Git `includeIf` oraz zarzadzanych plikach include.
