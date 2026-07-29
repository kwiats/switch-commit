# GitHub Local Discovery - Design

## Cel

Aplikacja ma lokalnie wykrywac, ze uzytkownik korzysta z GitHuba, i proponowac dodanie konta GitHub jako profilu w Git Account Switcher.

Wykrywanie jest w 100% lokalne:

- bez GitHub API,
- bez automatycznego logowania,
- bez automatycznych polaczen sieciowych,
- bez odczytu lub zapisu sekretow,
- bez skanowania calego dysku.

Jesli aplikacja znajdzie wiarygodna lokalna nazwe uzytkownika GitHub, nazwa proponowanego konta w aplikacji powinna byc ta nazwa, np. `pawelkwiatkowski`. Jesli aplikacja znajdzie tylko lokalna tozsamosc Git, pokazuje kandydata o nizszej pewnosci i wymaga potwierdzenia danych przez uzytkownika.

## Zakres

Pierwsza integracja obejmuje tylko GitHub. Architektura powinna jednak zostawic proste miejsce na kolejnych dostawcow w przyszlosci przez pole `provider`, bez implementowania GitLaba, Bitbucket ani innych serwisow teraz.

W zakresie sa:

- kaskadowe lokalne wykrywanie GitHuba,
- tymczasowy model wykrytego konta,
- laczenie sygnalow z kilku lokalnych zrodel,
- deduplikacja wzgledem istniejacych profili,
- prezentacja wykrytych kandydatow w ustawieniach,
- dodanie wykrytego kandydata jako normalnego `GitProfile` po akcji uzytkownika,
- reczny skan wskazanego folderu tylko po zgodzie uzytkownika.

Poza zakresem sa:

- zapytania do GitHub API,
- OAuth albo inne logowanie do GitHuba,
- pobieranie organizacji, avatarow, repozytoriow lub emaili z sieci,
- automatyczne skanowanie katalogu domowego lub calego dysku,
- automatyczna modyfikacja `~/.gitconfig`, `~/.ssh/config` albo Keychain podczas samego wykrywania.

## Podejscie: kaskada lokalnych zrodel

Wykrywanie sklada sie z trzech poziomow. Kazdy poziom moze zwrocic zero lub wiecej sygnalow. Wyniki sa laczone w kandydatow kont, a kandydaci dostaja poziom pewnosci.

### Poziom 1: szybki automatyczny odczyt plikow

Ten poziom moze uruchamiac sie przy starcie aplikacji albo przy otwarciu ustawien, poniewaz czyta tylko znane lokalne pliki i nie wykonuje szerokiego skanu.

Zrodla:

- `~/.config/gh/hosts.yml`,
- `~/.ssh/config`,
- `~/.ssh/git-account-switcher.conf`,
- wybrane lokalne pliki Git config, jesli sa znane i bezpieczne do odczytu.

Najwazniejsze zrodlo to `~/.config/gh/hosts.yml`. Jesli istnieje wpis dla `github.com` z polem uzytkownika, kandydat dostaje wysoka pewnosc, bo nazwa pochodzi z lokalnej konfiguracji GitHub CLI.

Aplikacja nie zapisuje tokenow ani nie pokazuje ich wartosci. Jesli plik `hosts.yml` zawiera token lub inne pole sekretu, detektor ignoruje wartosc i moze zapisac tylko neutralny sygnal typu `githubCliHostConfigured`.

### Poziom 2: lokalna diagnostyka komend

Ten poziom uruchamia lekkie komendy lokalne przez istniejaca abstrakcje `CommandRunning`.

Dozwolone komendy:

```bash
git config --global --get user.name
git config --global --get user.email
git config --global --get credential.https://github.com.username
git config --global --get credential.github.com.username
gh --version
ssh -G github.com
```

`gh --version` sluzy tylko do potwierdzenia, ze GitHub CLI jest lokalnie zainstalowany. Nazwa uzytkownika nadal pochodzi z lokalnego pliku `hosts.yml`, nie z komendy `gh`. `ssh -G github.com` sluzy do lokalnego rozwiazania konfiguracji SSH i nie powinno probowac polaczenia z hostem.

Implementacja nie moze uzywac komend, ktore wymagaja kontaktu z GitHub API, sprawdzaja zdalny status logowania albo pobieraja dane profilu. Jesli `gh` nie istnieje albo komenda lokalna zwroci blad, detektor pomija to zrodlo.

Sygnaly z `git config user.name` i `user.email` same w sobie nie dowodza, ze konto jest GitHubowe. Daja kandydata tylko wtedy, gdy istnieje dodatkowy sygnal GitHuba, np. `github.com` w SSH config, credential username dla GitHuba albo remote z recznego skanu.

### Poziom 3: reczny skan wskazanego folderu

Ten poziom nigdy nie uruchamia sie automatycznie. UI musi poprosic uzytkownika o wybor folderu i jasno pokazac, ze aplikacja przeskanuje ten folder w poszukiwaniu repozytoriow Git z remote `github.com`.

Zakres skanu:

- tylko folder wybrany przez uzytkownika,
- tylko katalogi `.git` i konfiguracje repozytoriow pod wskazanym folderem,
- brak odczytu plikow roboczych repozytorium poza minimalnymi plikami Git config potrzebnymi do znalezienia remote.

Z remote URL aplikacja moze wykryc, ze uzytkownik korzysta z GitHuba. Przyklady:

```text
git@github.com:pawelkwiatkowski/project.git
https://github.com/pawelkwiatkowski/project.git
ssh://git@github.com/pawelkwiatkowski/project.git
```

Pierwszy segment sciezki remote, np. `pawelkwiatkowski`, nie zawsze jest loginem uzytkownika. Moze to byc organizacja. Dlatego remote URL jest silnym sygnalem uzycia GitHuba, ale sam nie powinien automatycznie ustawiac `username` z wysoka pewnoscia.

## Model danych

Wykryte konto nie jest profilem. Jest tymczasowym kandydatem, ktory moze zostac zaakceptowany przez uzytkownika.

Proponowany model core:

```swift
public enum GitAccountProvider: String, Codable, Equatable, Sendable {
    case github
}

public enum DetectionConfidence: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low
}

public enum DetectionSource: String, Codable, Equatable, Sendable {
    case githubCliHostsFile
    case githubCliInstalled
    case globalGitConfig
    case gitCredentialUsername
    case sshConfig
    case sshResolvedConfig
    case repositoryRemote
}

public struct DetectedGitAccount: Equatable, Identifiable, Sendable {
    public var id: String
    public var provider: GitAccountProvider
    public var username: String?
    public var gitUserName: String?
    public var gitUserEmail: String?
    public var sshKeyPath: String?
    public var hosts: [String]
    public var confidence: DetectionConfidence
    public var sources: [DetectionSource]
    public var warnings: [String]
}
```

`DetectedGitAccount` nie jest zapisywany w `profiles.json` jako profil. Jesli aplikacja chce pamietac, ze uzytkownik odrzucil konkretnego kandydata, powinna w przyszlosci zapisac osobna liste ukrytych sugestii bez sekretow. To nie jest wymagane w pierwszej implementacji.

## Tworzenie profilu z kandydata

Akcja uzytkownika `Add detected account` zamienia kandydata na `GitProfile`.

Mapowanie:

- `id`: `github-<username>` dla pewnego username, inaczej bezpieczny wariant `github-account-<n>`,
- `displayName`: username GitHub, jesli znany; inaczej `GitHub Account`,
- `gitUserName`: wykryte `gitUserName` albo username,
- `gitUserEmail`: wykryty email albo wartosc wymagajaca edycji przed zapisem,
- `sshKeyPath`: wykryty klucz albo domyslne `~/.ssh/id_ed25519`,
- `hosts`: zawsze zawiera `github.com`,
- `httpsCredentialRef`: `nil`,
- `isDefault`: `true` tylko jesli nie istnieje zaden inny profil.

Jesli kandydat nie ma wymaganych pol `GitProfile`, UI powinien otworzyc formularz dodawania profilu z uzupelnionymi polami zamiast zapisywac niekompletny profil.

## Deduplikacja

Aplikacja nie powinna proponowac duplikatu, jesli istnieje juz profil, ktory wyglada na to samo konto.

Reguly dopasowania:

- ten sam host `github.com` i ten sam `gitUserEmail`: duplikat,
- ten sam host `github.com` i `displayName` rowne username: duplikat,
- ten sam host `github.com` i ten sam `httpsCredentialRef`: duplikat, jesli w przyszlosci takie referencje beda uzywane dla GitHuba.

Jesli dopasowanie jest niepewne, UI pokazuje ostrzezenie i pozwala uzytkownikowi recznie zdecydowac, czy zaktualizowac istniejacy profil czy dodac nowy.

## UI i przeplywy

### Automatyczne wykrycie

1. Uzytkownik uruchamia aplikacje albo otwiera ustawienia.
2. Aplikacja uruchamia poziom 1 i poziom 2.
3. Jesli wykryto kandydata, w ustawieniach pojawia sie sekcja `Detected Accounts`.
4. Uzytkownik moze dodac kandydata jako profil albo go zignorowac.
5. Dopiero po akcji uzytkownika aplikacja zapisuje profil.

### Reczny skan folderu

1. Uzytkownik klika `Scan selected folder for GitHub remotes`.
2. Aplikacja pokazuje picker folderu.
3. Aplikacja skanuje tylko wybrany folder.
4. Wyniki remote `github.com` laczy z istniejacymi sygnalami.
5. UI pokazuje kandydatow i ostrzezenia o niepewnych nazwach, np. gdy nazwa pochodzi tylko z ownera remote.

### Brak wynikow

Jesli nie znaleziono konta, aplikacja pokazuje neutralny komunikat:

```text
No local GitHub account was detected.
```

Obok pozostaja akcje:

- dodanie profilu recznie,
- reczny skan wskazanego folderu.

## Bezpieczenstwo

Detektor dziala read-only. Nie moze:

- zapisac profilu bez akcji uzytkownika,
- modyfikowac Git config,
- modyfikowac SSH config,
- zapisywac do Keychain,
- odczytywac tokenow jako danych aplikacji,
- uruchamiac komend sieciowych,
- skanowac katalogu domowego bez wyboru folderu przez uzytkownika.

Wyniki wykrywania moga zawierac tylko metadane potrzebne do utworzenia profilu: nazwy, emaile, hosty, sciezki kluczy i neutralne nazwy zrodel.

## Architektura

Nowe elementy w core:

- `GitAccountProvider`, `DetectionConfidence`, `DetectionSource`, `DetectedGitAccount` w modelach albo osobnym pliku modeli wykrywania,
- `GitHubLocalDiscoveryService` jako orkiestrator kaskady,
- `GitHubCLIHostsParser` do parsowania lokalnego `hosts.yml`,
- `GitRemoteParser` do parsowania GitHub remote URL,
- `DetectedAccountMerger` do laczenia sygnalow i wyliczania pewnosci,
- metody w `ProfileSettingsManager` do importu zaakceptowanego kandydata.

Warstwa aplikacji:

- `AppViewModel` trzyma liste `detectedAccounts`,
- ustawienia pokazuja sekcje wykrytych kont,
- akcja dodania kandydata przechodzi przez `ProfileSettingsManager`, aby zachowac walidacje `GitProfile` i zapis przez `ProfileStore`.

## Obsluga bledow

Bledy wykrywania nie blokuja aplikacji.

Przyklady:

- brak pliku `gh hosts.yml`: brak wyniku, bez bledu dla uzytkownika,
- niepoprawny YAML: ostrzezenie diagnostyczne,
- brak komendy `gh`: brak wyniku, bez bledu dla uzytkownika,
- brak dostepu do wybranego folderu: komunikat w UI po recznym skanie,
- remote URL w nieznanym formacie: pomijamy konkretny remote i dodajemy ostrzezenie diagnostyczne.

## Testowanie

Testy core powinny objac:

- parsowanie `gh hosts.yml` i ignorowanie wartosci tokenow,
- wykrycie username z `hosts.yml` jako `high` confidence,
- wykrycie globalnego `user.name` i `user.email`,
- brak kandydata GitHub, gdy istnieje tylko globalna tozsamosc Git bez sygnalu `github.com`,
- wykrycie credential username dla `github.com`,
- parsowanie remote URL dla SSH, HTTPS i `ssh://`,
- traktowanie ownera remote jako sygnalu sredniej lub niskiej pewnosci, nie jako pewnego username,
- laczenie kilku sygnalow w jednego kandydata,
- deduplikacje wzgledem istniejacego `GitProfile`,
- import kandydata do `GitProfile` bez `httpsCredentialRef`,
- brak zapisu sekretow do `profiles.json`,
- brak uruchamiania komend innych niz dozwolone lokalne komendy.
- brak wywolywania `gh auth status`, `gh api` i innych komend, ktore moga sprawdzac stan w GitHubie.

Manualna weryfikacja:

- uzytkownik z `gh` zalogowanym lokalnie widzi konto GitHub jako sugestie,
- uzytkownik bez `gh`, ale z globalnym Git config i SSH config dla `github.com`, widzi kandydata sredniej pewnosci,
- uzytkownik bez lokalnych sygnalow widzi brak wynikow i opcje recznego skanu,
- po wybraniu folderu z repo GitHub aplikacja wykrywa remote,
- dodanie kandydata tworzy normalny profil, ktory mozna edytowac i przelaczac.

## Decyzje zatwierdzone

- Integracja jest na razie tylko z GitHubem.
- Wykrywanie jest w 100% lokalne.
- Aplikacja nie wykonuje GitHub API requestow.
- Aplikacja laczy trzy podejscia: szybki odczyt plikow, lokalne komendy diagnostyczne i reczny skan folderu.
- Reczny skan folderu wymaga zgody uzytkownika i wyboru zakresu.
- Wykryte konto jest sugestia, nie automatycznie zapisanym profilem.
