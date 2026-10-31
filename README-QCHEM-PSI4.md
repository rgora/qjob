# Q-Chem i Psi4+OEPDev


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
