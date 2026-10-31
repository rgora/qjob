# qjob — Slurm i lokalne obliczenia chemiczne

Jeden pakiet wrapperów dla WCSS, bohr/bose/ligol i obliczeń lokalnych.
Kod aplikacji jest wspólny; kolejkę, zasoby, scratch, moduły i ścieżki programów
wybiera konfiguracja. qjob nie instaluje programów chemicznych ani ich licencji.

## Instalacja i wybór środowiska

| Środowisko | Wybór konfiguracji | Wykonanie |
|---|---|---|
| bohr, bose, ligol | automatycznie `/etc/qjob/*.conf` | Slurm |
| WCSS | `QJOB_PROFILE=wcss` | Slurm |
| macOS | automatycznie `local`, jeśli brak konfiguracji site | lokalnie |
| Linux bez kolejki | `QJOB_PROFILE=local` | lokalnie |

`QJOB_PROFILE` **wybiera ustawienia**, ale sam nie instaluje qjob, modułów ani
aplikacji. Na klastrze nie trzeba go ustawiać, gdy administrator przygotował
`/etc/qjob/`. `local` oznacza wykonanie bez Slurma, także na laptopie z Linuxem;
nie oznacza lokalnego klastra bohr/bose/ligol.

### WCSS — instalacja prywatna

Po scaleniu tej konsolidacji do `main` wystarczy jeden checkout:

```bash
git clone https://github.com/rgora/qjob.git "$HOME/.local/share/qjob"
bash "$HOME/.local/share/qjob/site/install-commands.sh" --profile wcss
export PATH="$HOME/.local/bin:$PATH"
```

Do czasu scalenia należy wybrać gałąź proponowaną w PR. `export PATH` dodaj do
konfiguracji powłoki, jeśli ten katalog nie jest już w PATH. Instalator tworzy
krótkie wrappery wskazujące jeden checkout i domyślnie ustawia `QJOB_PROFILE=wcss`.
Zamiast niego można dodać `qjob/bin` do PATH i samodzielnie ustawić
`export QJOB_PROFILE=wcss`. Nie są potrzebne osobne kopie qjob dla każdego programu.

Konto rozliczeniowe ustaw we własnej konfiguracji, np.:

```bash
mkdir -p "$HOME/.config/qjob"
# W ~/.config/qjob/qjob.conf, z rzeczywistą nazwą swojego projektu:
# account='TWOJ_PROJEKT_WCSS'
```

Można również podawać `-A NAZWA_PROJEKTU` przy zgłaszaniu. Wersje modułów są
w `profiles/wcss/<app>.conf`; swoje zmiany zapisuj w `~/.config/qjob/<app>.conf`.
Nowe wrappery chemiczne używają profilu z `lem-cpu-short` i lokalnym scratchem;
ORCA zachowuje starsze domyślne zasoby WCSS. Sprawdź `Polecenie --help` przed
pierwszym zgłoszeniem i dostosuj zasoby opcjami `-c`, `-m`, `-t`, `-p`.

### bohr, bose i ligol — instalacja współdzielona

Administrator utrzymuje kod w `/opt/qjob`, a konfigurację poza checkoutem:

```bash
sudo git clone https://github.com/rgora/qjob.git /opt/qjob
sudo bash /opt/qjob/site/install-orca.sh
sudo bash /opt/qjob/site/install-commands.sh --bin-dir /usr/local/bin
```

`install-orca.sh` tworzy początkowy `/etc/qjob/qjob.conf` dla rozpoznanego hosta,
konfigurację ORCA i `/scratch/qjob`. Istniejące pliki konfiguracyjne zachowuje.
`install-commands.sh` udostępnia polecenia; nie zmienia konfiguracji site i nie
instaluje aplikacji. Opcjonalne nazwy na końcu ograniczają wybór, np. `Gaussian Xtb`.
Przykłady ustawień pozostałych aplikacji są w `site/*.conf.example`; odpowiednie
pliki umieszcza się w `/etc/qjob/<app>.conf`. Dotychczasowe instalatory dodatków
`site/install-*.sh` pozostają dostępne.

Nie ustawiaj tu `QJOB_PROFILE=local`: zadania mają trafić do Slurma.
Użytkownicy uruchamiają programy bez sudo. Nazwy partycji to `normal` na bohr,
`bose` na bose i `ligol` na ligol. Moduł Gaussiana na ligol wymaga np.:

```bash
# /etc/qjob/gaussian.conf
GAUSSIAN_MODULE=Gaussian
GAUSSIAN_MODULE_VERSION=16.C.01-NVHPC-21.3
```

Na bose/bohr Gaussian domyślnie korzysta z `/opt/gaussian`.
Kolejka wirtualna `-p global` wymaga osobnej konfiguracji i usługi użytkownika;
nie uruchamia jej wybór profilu. Szczegóły: [README-GLOBAL.md](README-GLOBAL.md).

### Wykonanie lokalne

```bash
bash site/install-commands.sh --profile local
# lub tylko dla jednego wywołania:
QJOB_PROFILE=local Orca -c 4 -m 8 --background water.inp
```

Trzeba wskazać natywną instalację programu we własnym pliku konfiguracyjnym.
Przenośność na systemowy Bash 3.2 macOS jest sprawdzana dla ORCA i instalatora
poleceń; pozostałe programy mogą wymagać Linuksa. Instrukcja ORCA/MPI dla macOS
jest w [README-ORCA.md](README-ORCA.md).

## Użycie

```bash
Orca -c 8 -m 16 -t 24 calculation.inp
Gaussian -c 8 -m 16 -t 24 molecule.com
Crest -c 4 -m 8 geometry.xyz --gfn2 --quick
OpenMolcas -c 4 -m 8 calculation.inp
QuantumEspresso -c 4 -m 8 -C 'H.UPF' calculation.in
Orca --debug calculation.inp           # pokaż skrypt, bez zgłoszenia
```

`-c` ustala rdzenie na węzeł (procesy MPI albo wątki, zależnie od programu),
`-n` liczbę węzłów, `-m` łączną pamięć na węzeł w GB, a `-t` czas w godzinach
lub formacie Slurma. Są to opcje qjob; starsze skrypty PBS mogą mieć inne znaczenie
tych samych liter. Pamięć natywnego programu jest synchronizowana tylko tam,
gdzie opisuje to wrapper; np. Gaussian dostaje 80% rezerwacji, a ORCA zachowuje
`%maxcore` z wejścia i sprawdza jego stosunek do rezerwacji.

`-C 'pliki katalogi'` kopiuje wejścia pomocnicze do scratch; `-B` wybiera pliki
kopiowane z powrotem. `--local` wykonuje obliczenie na bieżącej maszynie;
`--background` uruchamia je w tle. Na WCSS używaj tych opcji w przydzielonej
alokacji obliczeniowej. `--debug` generuje skrypt bez uruchamiania aplikacji.

## Dostępne polecenia

| Polecenia | Instrukcja |
|---|---|
| `Orca` | [ORCA, klaster i macOS](README-ORCA.md) |
| `Gaussian` (G16, lokalnie także G09/G03) | [Gaussian](README-GAUSSIAN.md) |
| `Gromacs` | [GROMACS](README-GROMACS.md) |
| `Turbomole` | [TURBOMOLE](README-TURBOMOLE.md) |
| `Bagel` | [BAGEL](README-BAGEL.md) |
| `Crest`, `Xtb` | [CREST/xTB](README-CREST-XTB.md) |
| `Newtonx` | [Newton-X](README-NEWTONX.md) |
| `OpenMolcas` | [OpenMolcas](README-OPENMOLCAS.md) |
| `Openqp` | [OpenQP](README-OPENQP.md) |
| `Cfour`, `Molpro`, `QuantumEspresso`, `Nwchem`, `Dalton`, `Cp2k` | [Zestaw WCSS](README-WCSS-SUITE.md) |
| `QChem`, `Psi4oep` | [Q-Chem i Psi4+OEPDev](README-QCHEM-PSI4.md) |
| `sq`, `qglobal` | przegląd Slurma; [dispatcher](README-GLOBAL.md) |

## Kolejność konfiguracji

Od najniższego do najwyższego priorytetu:

1. Domyślne wartości `apps/<app>.sh`.
2. `/etc/qjob/qjob.conf`, następnie `/etc/qjob/<app>.conf`.
3. Wybrany `profiles/<profil>/qjob.conf`, następnie `<app>.conf`.
4. `~/.config/qjob/qjob.conf`, następnie `<app>.conf`.
5. Opcje polecenia.

Można zmienić katalogi przez `QJOB_CONFIG_DIR`, `QJOB_USER_CONFIG_DIR` lub
`XDG_CONFIG_HOME`. Pliki `.conf` są zaufanym kodem Bash. Aktualizacja repozytorium
nie nadpisuje konfiguracji w `/etc/qjob/` ani `~/.config/qjob/`.

## Gałęzie, aktualizacja i migracja

`main` zawierał starszy kod WCSS, a `site/shared-orca` wspólną adaptację klastra
oraz macOS. Rozdzielenie chroniło dotychczasową instalację WCSS podczas rozwoju.
Nie jest wymagane przez program: wspólny kod obsługuje wszystkie środowiska.
Konsolidacja zachowuje historię obu gałęzi, w tym identyczny plik `sq`, który
wcześniej trafił do nich osobnymi commitami. Po jej scaleniu `main` może być
jedyną gałęzią instalacyjną; stara gałąź pozostaje punktem odniesienia.

Przed aktualizacją sprawdź `git status` i bieżącą gałąź. Zachowaj lokalne zmiany
zanim wykonasz `git pull --ff-only`. Nie kopiuj całego repozytorium na działający
checkout z niezapisanymi zmianami. Przy przejściu ze starszej instalacji najpierw
uruchom testy i porównaj wynik `Polecenie --debug` z dotychczasową konfiguracją.

Wcześniejsze wdrożenia WCSS używały kilku kopii (`qjob-*`) i osobnych wrapperów
w `~/bin`. Nowy instalator może zastąpić wybrane wrappery, zachowując ich kopie.
Migracja wymaga przeniesienia własnego konta i innych osobistych ustawień do
`~/.config/qjob/`; samo opublikowanie konsolidacji nie migruje istniejących hostów.

## Testy i struktura

```bash
bash tests/run.sh
```

Testy używają atrap aplikacji i Slurma: sprawdzają staging, wyniki, błędy,
zasoby, profile i odporność dispatchera na utratę odpowiedzi. Nie zastępują
rzeczywistych obliczeń ani sprawdzenia modułów danego klastra. Historyczne testy
obliczeniowe są opisane w instrukcjach aplikacji.

`bin/` zawiera polecenia, `apps/` adaptery programów, `lib/qjob.sh` opcje i
nagłówki Slurma, `lib/runtime.sh` wykonanie i kopiowanie wyników, a `profiles/`
i `site/` ustawienia oraz instalatory. Dodając adapter, umieść funkcje pomocnicze
w `APP_FUNCS`, a zmienne przekazywane do zadania w `APP_VARS`.

MIT, zob. [LICENSE](LICENSE).
