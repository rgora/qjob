# qjob — minimalne środowisko do wstawiania zadań Slurm (WCSS)

Małe, samodzielne środowisko w trzech warstwach:

```
qjob/
├── bin/Orca, Turbomole, QChem, Psi4oep  wrappery (1 linia)
├── lib/qjob.sh      opcje, nagłówek #SBATCH, sbatch            (wspólne)
├── lib/runtime.sh   kod wykonywany w zadaniu: prolog, copy/copy-back, epilog
├── apps/<app>.sh    domyślne zasoby, opcje specyficzne, ciało zadania app_run()
└── libexec/psi4-oepdev-run   uruchamianie Psi4+OEPDev (kopia ~/bin/psi4-oepdev-run)
```

Instalacja na klastrze:

```bash
git clone https://github.com/rgora/qjob.git ~/bin/qjob
export PATH=$HOME/bin/qjob/bin:$PATH        # w ~/.bashrc, przed ~/bin
# albo dowiązania: ln -s ~/bin/qjob/bin/Orca ~/bin/Orca  (itd.)
```

Aktualizacja: `git -C ~/bin/qjob pull`.

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
--local --debug -h`. W `-C/-B` `%b` oznacza nazwę wejścia bez rozszerzenia.

## Co robi każdy program

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

Wspólne dla wszystkich: 300 s przed limitem czasu zadanie dostaje USR1 i kopiuje pliki
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
