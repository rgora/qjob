# ORCA: klaster i macOS

## Klaster

Kod jest wspólny dla użytkowników danej maszyny; każda maszyna ma własny checkout
w `/opt/qjob`, należący do roota, i własne ustawienia w `/etc/qjob`.
Polecenia `Orca`, `Gromacs` i `Openqp` są dostępne przez `/usr/local/bin`.
Podstawową konfigurację site instaluje się następująco:

```bash
sudo git clone --branch main https://github.com/rgora/qjob.git /opt/qjob
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
sudo git -C /opt/qjob branch --show-current   # main after consolidation
sudo git -C /opt/qjob pull --ff-only
```

Aktualizacja kodu nie nadpisuje `/etc/qjob/*.conf` ani konfiguracji użytkowników.
Nie należy wykonywać instalacji ani `git pull` jako root w katalogach domowych
użytkowników.



## macOS

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


