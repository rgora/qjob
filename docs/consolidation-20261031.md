# Konsolidacja qjob — 31 października 2026

## Historia gałęzi

Punktem wspólnym był `85a393d`. Gałąź `main` miała dodatkowy commit `d48a65d`
z poleceniem `sq`; `site/shared-orca` miała 11 dodatkowych commitów, kończących
się na `7661eb3`. Jej commit `83a263a` dodawał identyczny plik `sq`.
Scalenie obu gałęzi nie wymagało rozstrzygania konfliktów treści i zachowuje
obie historie. Podział powstał dla ochrony dotychczasowego WCSS podczas
adaptacji wspólnego kodu do klastra i macOS, nie z wymagania architektury qjob.

## Zebrane źródła

Porównano GitHub, lokalną roboczą kopię projektu Cluster, `/opt/qjob` na bose,
bohr i ligol oraz wszystkie wdrożenia `~/bin/qjob*` na WCSS. Oryginalne kopie
pozostawiono bez zmian; migawki i integrację wykonano w oddzielnym katalogu.

- Lokalna robocza kopia zawierała pełny dispatcher, testy i instalator usługi,
  BAGEL, CREST/xTB, Newton-X, OpenMolcas, OpenQP i sześć nowych wrapperów WCSS.
- Gaussian i jego testy pochodziły z aktualnego wdrożenia na bose; ten sam
  adapter był zainstalowany na bohr, ligol i WCSS.
- Wersja OpenQP z lokalnej kopii i WCSS zawierała dodatkową kontrolę dostępności
  MPI. Zachowano ją zamiast starszego adaptera na trzech serwerach.
- TURBOMOLE na bose i w lokalnej kopii odpowiadał wersji w gałęzi wspólnej.
  bohr i ligol miały starszy adapter. Konsolidacja zachowuje nowszy wariant.
- WCSS nadal miał starszą podstawową instalację ORCA oraz osobne nowsze kopie
  dla dodatków. Wspólny kod bibliotek dodatków odpowiadał wersji klastra.

## Konfiguracja i instalacja

Wersje modułów i sposób wykonania pozostają w profilach aplikacji.
Usunięto osobisty identyfikator konta rozliczeniowego z dystrybuowanych profili;
ustawia się go w konfiguracji użytkownika albo opcją `-A`.
Profile zestawu chemicznego WCSS zachowują partycję i scratch używane we
wcześniejszym prywatnym wdrożeniu. Istniejące zasoby profilu ORCA WCSS pozostają.

Nowy `site/install-commands.sh` udostępnia polecenia z jednego checkoutu,
obsługuje wybrany profil i zachowuje zastępowane polecenia. Nie instaluje
programów obliczeniowych, nie modyfikuje plików konfiguracyjnych i nie uruchamia
usługi global. `qglobal` znajduje teraz implementację względem własnego
checkoutu zamiast lokalnej, bezwzględnej ścieżki; zdalne hosty dispatchera
nadal wymagają wdrożenia w `/opt/qjob`.

## Weryfikacja

Pełny `tests/run.sh` przeszedł w izolowanej kopii na bose: 10 zestawów testów
Bash i dwa zestawy Python, w tym pięć testów odporności dispatchera.
Testy instalatora sprawdzają wybór i nadpisanie profilu, kopie zapasowe,
idempotencję, dowiązania, odrzucenie nieznanej nazwy oraz `qglobal` poza `/opt`.
Testy ORCA i instalatora obejmują również systemowy Bash macOS.

Są to testy integracyjne z atrapami aplikacji i Slurma. Historyczne rzeczywiste
obliczenia opisano w instrukcjach adapterów. Konsolidacja nie uruchamia nowych
obliczeń produkcyjnych, nie migruje aktywnych checkoutów ani nie usuwa gałęzi.
