# Switch Commit — przyszłe funkcje

Luźny backlog pomysłów do rozważenia później. To nie jest plan implementacji ani design — tylko lista kierunków produktu. Po doprecyzowaniu danego punktu warto zrobić osobny spec w `docs/superpowers/specs/`.

Ostatnia aktualizacja: 2026-07-30

---

## 1. Powiadomienia o innym koncie

**Cel:** Aplikacja informuje użytkownika, gdy wykryje, że w danym kontekście działa inne konto Git niż oczekiwane / aktywne w Switch Commit.

**Możliwe scenariusze:**
- w otwartym repozytorium `user.name` / `user.email` nie zgadza się z aktywnym profilem;
- lokalne sygnały (np. GitHub CLI, SSH) wskazują na inne konto niż to wybrane w aplikacji;
- folder ma przypisaną regułę, ale rzeczywista tożsamość Git jest inna.

**Otwarte pytania:**
- kiedy sprawdzać (tylko na żądanie vs. przy wejściu do folderu / przy zmianie profilu);
- forma powiadomienia (banner w menu, systemowe Notification Center, tylko wpis w Settings);
- jak nie naruszyć kontraktu „bez automatycznych wywołań sieciowych”.

**Status:** pomysł

---

## 2. Powiadomienia o nowej wersji

**Cel:** Użytkownik dostaje jasny sygnał, że jest dostępna nowsza wersja Switch Commit.

**Kontekst w repo:**
- jest już ścieżka **ręcznego** sprawdzania aktualizacji (`Check for Updates` + Sparkle / publiczny release channel);
- automatyczne sprawdzanie w tle jest dziś poza zakresem ze względu na privacy (brak tła sieciowego bez zgody użytkownika).

**Możliwe warianty (do decyzji później):**
- opcjonalne, wyraźnie włączone przez użytkownika okresowe sprawdzanie;
- powiadomienie tylko po ręcznym checku, gdy znaleziono update;
- badge / wpis w menu bar bez auto-pobierania.

**Status:** pomysł (częściowo pokryte przez ręczne aktualizacje)

---

## 3. CLI

**Cel:** Narzędzie wiersza poleceń do przełączania profili i odczytu stanu bez otwierania UI.

**Przykładowe komendy (roboczo):**
- lista profili;
- przełączenie aktywnego profilu;
- pokazanie aktywnej tożsamości;
- przypisanie / odczyt reguły folderu;
- diagnostyka lokalna (bez sieci, chyba że użytkownik jawnie o to poprosi).

**Otwarte pytania:**
- osobny binary w package vs. subcommand aplikacji;
- jak dzielić logikę z `SwitchCommitCore` (preferowane: ten sam core);
- instalacja / PATH na macOS.

**Status:** pomysł

---

## 4. Konto per folder + automatyczne rozpoznawanie

**Cel:** Przypisanie konta do folderu (lub drzewa folderów) oraz automatyczne stosowanie właściwej tożsamości Git w tym kontekście.

**Kontekst w repo:**
- w core istnieją już `FolderRule` oraz generowanie / instalacja managed Git config pod reguły folderów;
- brakuje dopracowanego UX: łatwe przypisywanie z UI, jasne rozpoznawanie „jesteś w folderze X → profil Y”, ewentualnie powiadomienia przy mismatch (punkt 1).

**Możliwe rozszerzenia:**
- picker folderu → wybór profilu;
- podgląd aktywnej reguły dla bieżącego katalogu;
- automatyczne rozpoznawanie na podstawie ścieżki (includeIf / managed rules);
- opcjonalnie: sugestia profilu na podstawie lokalnych sygnałów w danym repo.

**Status:** pomysł / częściowo wspierane w core

---

## Jak dodawać kolejne pomysły

Dopisz nową sekcję w tym samym formacie:

1. krótki **cel**;
2. kilka zdań „jak to ma działać” lub scenariuszy;
3. **otwarte pytania** / ryzyka (privacy, bezpieczeństwo, UX);
4. **status:** `pomysł` | `do designu` | `w planie` | `zrobione`.
