# qjob — zadania Slurm i lokalne obliczenia w tle

Wspólny kod uruchamiania aplikacji z konfiguracją zależną od miejsca pracy:
Slurm na WCSS i lokalnym klastrze, a na laptopie obliczenia bez kolejki,
również w tle. Obecna adaptacja i testy dotyczą przede wszystkim ORCA.

## Gałęzie i zgodność z WCSS

- `main` jest dotychczasową wersją używaną na WCSS. Zmiany opisane poniżej nie
  zostały do niej scalone; aktualizacja checkoutu `main` ich nie pobiera.
- `site/shared-orca` zawiera wspólną wersję dla WCSS, bohr, bose, ligol i macOS.
  Z tej samej gałęzi korzystają instalacje w `/opt/qjob` na trzech serwerach
  oraz prywatna instalacja na Macu. Różnice między maszynami są w konfiguracji.

Gałąź `site/shared-orca` zachowuje ustawienia WCSS, gdy nie ma konfiguracji site.
Są one również dostępne jawnie przez `QJOB_PROFILE=wcss`. To nie zmienia
istniejącej instalacji WCSS; migracja na tę gałąź jest osobnym, świadomym krokiem.

## Budowa pakietu

Małe, samodzielne środowisko w trzech warstwach:

```
qjob/
├── bin/Orca, Turbomole, QChem, Psi4oep  wrappery poleceń
├── lib/qjob.sh      opcje, nagłówek #SBATCH, sbatch            (wspólne)
├── lib/runtime.sh   kod wykonywany w zadaniu: prolog, copy/copy-back, epilog
├── apps/<app>.sh    domyślne zasoby, opcje specyficzne, ciało zadania app_run()
└── libexec/psi4-oepdev-run   uruchamianie Psi4+OEPDev (kopia ~/bin/psi4-oepdev-run)
```

Dotychczasowa instalacja indywidualna na WCSS (`main`):

```bash
git clone --branch main https://github.com/rgora/qjob.git ~/bin/qjob
export PATH=$HOME/bin/qjob/bin:$PATH        # w ~/.bashrc, przed ~/bin
# albo dowiązania: ln -s ~/bin/qjob/bin/Orca ~/bin/Orca  (itd.)
```

Aktualizacja tej instalacji: `git -C ~/bin/qjob pull --ff-only`.

## Użycie

```bash
Orca -c 32 -m 200 -t 72 neb1.inp neb2.inp     # jedno zadanie na plik, każde w katalogu pliku
Orca --debug opt.inp                           # pokaż pełny skrypt, nie wysyłaj
QChem -c 16 -m 32 --save tddft.in              # scratch -> tddft.chk/ (restart przy kolejnym --save)
Turbomole -c 32 jobex -ri -c 200               # opcje po nazwie programu idą do programu
Turbomole --init ricc2                         # dscf/ridft przed programem
Turbomole --local x2t mol.xyz > coord          # przygotowanie lokalnie, bez Slurma
Turbomole --local define
Psi4oep -c 16 -m 32 -t 24 c2h4_*.py h2co_*.py  # skany EOP-TI, jedno zadanie na skrypt
Psi4oep -v 1.11-dev -c 16 -m 64 --args "--methods cis,tda-hf,b3lyp --dimer" run_7ac.py
Psi4oep --args "7ac 2.6,3.6,4.6" ref_scan.py   # argumenty skryptu; %c = rdzenie, %M = pamięć psi4 w GB
```

Opcje wspólne: `-p -n -c -m -t -s/--storage -C/--copy -B/--copy-back
--clean-tmp --mail --name -w -A -q --reservation --exclusive --gres --slurmopt -v/--version
--local --background --debug -h`. W `-C/-B` `%b` oznacza nazwę wejścia bez rozszerzenia.

## Co robi każdy program

Poniższe wartości domyślne odnoszą się do profilu WCSS. Konfiguracja site,
profil lokalny i preferencje użytkownika mogą je zmienić.

| | ORCA | Turbomole | Q-Chem |
|---|---|---|---|
| domyślnie | 32 rdz., 200 GB, shm:400g, 72 h | 32 rdz., 128 GB, shm:200g, 72 h | 16 rdz., 32 GB, shm:100g, 72 h |
| gdzie liczy | TMPDIR (kopiuje inp, gbw, xyz, hess, oin, mp2nat, loc) | katalog bieżący, `TURBOTMPDIR=$TMPDIR` | wejście w katalogu, `QCSCRATCH=$TMPDIR` |
| zasoby w wejściu | `--pal sync`: `%pal nprocs` = rdzenie (w kopii w TMPDIR); ostrzeżenie, gdy `%maxcore`×rdzenie > 90% pamięci | `PARA_ARCH`, `PARNODES` | `MEM_TOTAL` = 90% `-m` wpisywane do każdego `$rem` (w kopii) |
| wynik | `<inp>-<jobid>.log`, `.err` | `<katalog>_<program>.log` | `<inp>.log` |
| Slurm | `--ntasks-per-node` | `--cpus-per-task` (smp) / `--ntasks-per-node` (mpi) | `--cpus-per-task` (`-nt`) / `--ntasks-per-node` (`-np`) |

**Psi4 + OEPDev** (`Psi4oep`): 8 rdz., 32 GB, 24 h, `--cpus-per-task`. Liczy w katalogu wejścia
(skany czytają i dopisują CSV, więc można je przerywać i wznawiać), `PSI_SCRATCH=$TMPDIR`.
Środowisko: `-v 1.11` → `~/PD/opt/psi4/psi4-oepdev-1.11.sh`, `-v 1.11-dev` → `…-1.11-dev.sh`
(gałąź dev/tdscf-tda), albo `--env PLIK`. Wątki i pamięć (90% `-m`) są narzucane przez
`libexec/psi4-oepdev-run` — `set_num_threads()`/`set_memory()` w skrypcie są ignorowane
(`PSI4OEP_HONOR_INPUT=1` to wyłącza). Wejście `*.py` (psiapi) albo Psithon (`*.in` → `*.out`);
stdout przebiegu trafia do `<wejście>-<jobid>.log`.

W zadaniach Slurm: 300 s przed limitem czasu zadanie dostaje USR1 i kopiuje pliki
z `--copy-back` (np. aktualny `.gbw`) do katalogu zadania; potem wykonuje się normalny epilog.

## Do sprawdzenia na klastrze

- Nazwy modułów: `ORCA` (działa), `turbomole` i `qchem` są ustawione w `apps/*.sh`
  (`TM_MODULE`, `QC_HOME_PATTERN`) — sprawdzić `module avail -i turbomole`.
- Q-Chem: domyślnie własna instalacja `/home/rgora/PD/opt/qchem/<wersja>/qcenv.sh`.

## Nowy program

Skopiować `apps/orca.sh` → `apps/<nazwa>.sh`, zmienić domyślne wartości i `app_run()`,
dodać wrapper w `bin/`. Funkcje pomocnicze używane w zadaniu wymienić w `APP_FUNCS`,
zmienne przekazywane do zadania w `APP_VARS`.

## Licencja

MIT, zob. `LICENSE`.

## Wspólna instalacja: bohr, bose i ligol

Kod jest wspólny dla użytkowników danej maszyny; każda maszyna ma własny checkout
w `/opt/qjob`, należący do roota, i własne ustawienia w `/etc/qjob`.
Na razie udostępniony jest tylko `Orca`:

```bash
sudo git clone --branch site/shared-orca https://github.com/rgora/qjob.git /opt/qjob
sudo /opt/qjob/site/install-orca.sh
Orca -h
Orca -c 4 -m 8 -t 2 calculation.inp
Orca --debug -c 4 -m 8 calculation.inp
```

Installer zachowuje istniejący `/usr/local/bin/Orca` jako `Orca.old`, a gdy ta kopia
już istnieje, jako `Orca.<data>-<pid>.old`. Tworzy dowiązanie do `/opt/qjob/bin/Orca`.
Powtórne uruchomienie zachowuje istniejące pliki konfiguracyjne i poprawne dowiązanie.

Kolejność ustawień: wartości w kodzie, `/etc/qjob/qjob.conf`, `/etc/qjob/orca.conf`,
wybrany profil z `profiles/`, `~/.config/qjob/qjob.conf`,
`~/.config/qjob/orca.conf`, opcje polecenia. Pliki `.conf` są zaufanym kodem
Bash. Pliki w `/etc/qjob` zapisuje administrator; konfigurację w swoim katalogu
użytkownik utrzymuje sam. `QJOB_CONFIG_DIR` pozwala wskazać inny katalog, np. przy testowaniu.
Pliki `site/*.conf.example` pokazują dostępne ustawienia. Domyślnie pozostaje
konfiguracja WCSS, jeśli nie zainstalowano konfiguracji lokalnej.

Lokalne partycje to `normal` na bohr, `bose` na bose i `ligol` na ligol.
Domyślne zasoby ORCA: jedna maszyna, 4 procesy, 8 GB łącznie, 24 godziny.
Wersja `6.1.1` jest mapowana na moduł `ORCA/6.1.1-gompi-2023b-avx2`.
Qjob inicjalizuje Lmod i ładuje ten moduł wraz z zależnościami MPI; uruchamia
pełną ścieżkę sterownika ORCA jeden raz. Liczbę procesów ustawia w `%pal`
w kopii wejścia w scratch. `%maxcore` pozostaje z wejścia; qjob ostrzega, gdy
jego wartość razy liczba procesów przekracza 90% żądanej pamięci.
Zadanie prosi o rdzenie fizyczne (`--hint=nomultithread`). Przed uruchomieniem
sterownika ORCA przywracana jest maska CPU przydzielona przez cgroup v2 zadania,
aby procesy MPI mogły korzystać z całej rezerwacji także wtedy, gdy powłoka batch
jest przypisana tylko do jednego rdzenia.

**Uwaga przy przejściu ze starego skryptu:** `-c` oznacza liczbę procesów,
`-n` liczbę maszyn, a `-m` łączną pamięć w GB. Stary skrypt używał `-n`
do liczby procesów i `-m` do `%maxcore` w MB. Nie należy przenosić dawnych
poleceń bez zmiany tych opcji. `--local` zastępuje dawny tryb `-s`.

Scratch powstaje przez `mktemp -d` pod `/scratch/qjob` (katalog nadrzędny 1777;
katalog zadania 0700, unikalny dla UID i job ID). Domyślnie jest usuwany po
poprawnym obliczeniu i skopiowaniu wyników; błąd zachowuje scratch, a jego ścieżka
jest w `slurm-<jobid>.out`. Można użyć `--clean-tmp false`, aby zachować go także
po sukcesie. Opcja `--storage local:<size>` na tych maszynach nie rezerwuje miejsca
ani nie narzuca limitu dyskowego; nie wysyła GRES do Slurma.

Wejście w katalogu użytkownika pozostaje bez zmian. Wyniki ORCA to
`<nazwa>-<jobid>.log`, opcjonalny `.err` i pliki wskazane przez `--copy-back`.
Domyślna lista obejmuje m.in. `.gbw`, `.hess`, `.cis`, geometrie i widma;
pełny zestaw plików roboczych wymaga `--copy-back '*'` i odpowiedniej ilości miejsca.
Nazwy wejść ORCA muszą składać się z liter, cyfr oraz znaków `_`, `.`, `+`, `-`;
nazwy ze spacjami są odrzucane, ponieważ wewnętrzne wywołania MPI w ORCA nie
obsługują ich poprawnie. Sukces wymaga kodu zero oraz komunikatu
`ORCA TERMINATED NORMALLY` bez komunikatu o błędnym zakończeniu.

Repozytorium w `/opt/qjob` i konfiguracja należą do roota. Zwykli użytkownicy
uruchamiają `Orca` bez sudo i bez zmieniania PATH. Aktualizacje wykonuje administrator
przez Git, po sprawdzeniu gałęzi i lokalnych zmian:

```bash
sudo git -C /opt/qjob status
sudo git -C /opt/qjob branch --show-current   # site/shared-orca
sudo git -C /opt/qjob pull --ff-only
```

Aktualizacja kodu nie nadpisuje `/etc/qjob/*.conf` ani konfiguracji użytkowników.
Nie należy wykonywać instalacji ani `git pull` jako root w katalogach domowych
użytkowników.


## Jedno repozytorium, różne środowiska

Profile i konfiguracja zmieniają zasoby, kolejkę, scratch oraz sposób odnalezienia
programu. Obsługa wejść i wyników ORCA jest wspólna. Nie są potrzebne osobne gałęzie
kodu dla WCSS, bohr/bose/ligol i laptopa.

| Środowisko | Wybór ustawień | Uruchamianie |
|---|---|---|
| WCSS | domyślnie bez konfiguracji site; jawnie `QJOB_PROFILE=wcss` | `sbatch` |
| bohr, bose, ligol | `/etc/qjob/*.conf` | `sbatch` |
| macOS | automatycznie profil `local`, jeśli nie ma konfiguracji site | lokalnie; `--background` w tle |
| laptop z Linuxem | `QJOB_PROFILE=local` | lokalnie; `--background` w tle |

Profil można wybrać zmienną `QJOB_PROFILE`, np. `QJOB_PROFILE=local Orca water.inp`.
W katalogu użytkownika respektowane są `XDG_CONFIG_HOME` i `QJOB_USER_CONFIG_DIR`.
Konfiguracja użytkownika nadpisuje ustawienia profilu, a opcje polecenia mają
najwyższy priorytet. Te ustawienia są wartościami domyślnymi; limity uprawnień i
zasobów na klastrze egzekwuje Slurm.

### Mac: natywna ORCA bez Slurma

Obsługa ORCA działa z systemowym Bash 3.2 i narzędziami macOS. Nie wymaga GNU
`getopt`, GNU `sed` ani GNU `readlink`. Obecnie ten zakres przenośności dotyczy
wrappera `Orca`; pozostałe aplikacje mają własne wymagania środowiskowe.

Instalacja dla pojedynczego użytkownika:

```bash
mkdir -p ~/.local/share ~/.local/bin ~/.config/qjob
git clone --branch site/shared-orca https://github.com/rgora/qjob.git ~/.local/share/qjob
ln -s ~/.local/share/qjob/bin/Orca ~/.local/bin/Orca
```

Jeśli `~/.local/bin/Orca` już istnieje, przed utworzeniem dowiązania należy zachować
je jako `Orca.old` (bez nadpisywania wcześniejszej kopii). Katalog `~/.local/bin`
musi być w `PATH`. Aktualizacja: `git -C ~/.local/share/qjob pull --ff-only`.

Można korzystać z istniejącego modułu. Przykład konfiguracji z tego Maca:

`~/.config/qjob/qjob.conf`:

```bash
QJOB_MODULE_INIT=/opt/homebrew/opt/modules/init/bash
QJOB_MODULEPATH=$HOME/.local/modulefiles
cores=2
memory=4
```

`~/.config/qjob/orca.conf`:

```bash
ORCA_MODULE=orca
ORCA_BINARY=''
ORCA_MODULE_TEMPLATE=''
ORCA_PURGE_MODULES=true
version=6.1.1
```

Qjob inicjalizuje Environment Modules także w procesie działającym w tle.
Moduł `orca/6.1.1` ustawia ORCA oraz zgodne MPI i biblioteki. Na tym Macu
wskazuje `/opt/orca/6.1.1` i `/opt/openmpi/4.1.6`.

Alternatywnie, dla gotowej instalacji bez modułów można ustawić
`ORCA_BINARY=/pełna/ścieżka/do/orca` w konfiguracji użytkownika; omija to ładowanie
modułów. ORCA oraz zgodne biblioteki i MPI muszą już działać w danym systemie.
Qjob nie instaluje programu przez wybór profilu.

```bash
Orca --background -c 2 -m 4 water.inp
# polecenie od razu wypisuje PID, log przebiegu i ścieżkę do pliku .exit-code
```

Proces jest uruchamiany przez `nohup`, z odłączonym wejściem i przekierowanymi
strumieniami. Log obsługi zadania ma nazwę `<wejście>-local.<identyfikator>.log`,
a log ORCA — `<wejście>-local-<pid>.log`. Po zakończeniu obok logu zadania powstaje
plik `.exit-code`: `0` oznacza prawidłowe zakończenie obliczenia i kopiowania
wyników. Brak pliku oznacza, że zakończenie nie zostało jeszcze zapisane (np.
proces nadal działa albo został przerwany). Bez `--background` profil lokalny
wykonuje zadanie na pierwszym planie. Lokalnie `-m` i `-t` nie ustanawiają limitów
systemowych; `-m` jest używane do kontroli zadeklarowanego `%maxcore`.


## Sprawdzenie instalacji

```bash
Orca -h
Orca --debug -c 4 -m 8 water.inp    # skrypt bez wysyłania zadania
bash /opt/qjob/tests/test_shared_orca.sh
# instalacja indywidualna:
# bash ~/.local/share/qjob/tests/test_shared_orca.sh
```

Test automatyczny korzysta z zastępczego programu ORCA. Sprawdza konfigurację,
generowanie skryptu, synchronizację `%pal`, prywatny scratch, zachowanie wejścia,
kopiowanie wyników, obsługę błędów i tryb pracy w tle. Nie zastępuje rzeczywistego
obliczenia w danym środowisku. Instalację ORCA/MPI należy sprawdzić krótkim zadaniem
równoległym i potwierdzić `ORCA TERMINATED NORMALLY` w logu.
