# GROMACS przez qjob

`Gromacs` przyjmuje przygotowany plik `.tpr` i wstawia do kolejki jedno zadanie
na każdy plik. Uruchamia `gmx mdrun` na jednym węźle, z jednym procesem
thread-MPI i liczbą wątków OpenMP podaną przez `-c`. Przygotowanie modelu
i `grompp` pozostają osobnym etapem.

```bash
Gromacs -c 4 -m 8 -t 24 md.tpr
Gromacs --debug -c 4 md.tpr       # podgląd skryptu bez wysyłania
Gromacs --cpu -c 8 md.tpr
Gromacs --gpu -c 4 md.tpr
Gromacs --checkpoint md.cpt md.tpr
```

`-m` oznacza GB pamięci na węzeł, `-t` godziny. Parametry symulacji pochodzą
z TPR; opcjonalne `--nsteps N` jawnie nadpisuje liczbę kroków.
Restart z checkpointu używa `-noappend`: tworzy nową część wyników zamiast
wymagać poprzednich trajektorii i dopisywać do nich w scratchu.
Checkpoint może mieć ścieżkę bezwzględną lub ścieżkę względem katalogu TPR.

Na **bose i bohr** domyślny moduł to `GROMACS/2026.2-foss-2025b`, tryb CPU.
Na **ligol** używany jest `GROMACS/2026.2-foss-2025b-CUDA-12.9.1`, tryb GPU.
Ligol nie ma obecnie GPU GRES w Slurmie, więc zadanie GPU rezerwuje cały
węzeł przez `--exclusive`. `--cpu` nie wymusza tej rezerwacji.
Domyślne zasoby aplikacji to 4 rdzenie, 8 GB i 24 godziny.

Obliczenie działa w prywatnym lokalnym scratchu. Wyniki o prefiksie nazwy
TPR (`.log`, `.edr`, `.gro`, `.trr`, `.xtc`, `.cpt`, `.xvg`, `.dat`, `.mtx`)
wracają do katalogu wejściowego. Scratch pozostaje po błędzie; zachowanie po
sukcesie określa `clean_tmp`. Qjob wypisuje jego ścieżkę i ścieżkę bieżącego
logu symulacji. Komunikaty programu są również w `slurm-<jobid>.out`.
Nie uruchamiaj równocześnie dwóch zadań z tym samym TPR w tym samym katalogu:
oba zapisywałyby wyniki pod tym samym prefiksem.

## Instalacja i inne środowiska

Na trzech lokalnych serwerach, po aktualizacji `/opt/qjob`:

```bash
sudo /opt/qjob/site/install-gromacs.sh
```

Instalator tworzy `/etc/qjob/gromacs.conf` i dowiązanie
`/usr/local/bin/Gromacs -> /opt/qjob/bin/Gromacs`. Istniejący skrypt zachowuje
jako `.old`; istniejącej konfiguracji nie nadpisuje. Instalacja GROMACS
jest osobna od instalacji tego polecenia.

Konfiguracja kolejki i scratcha pozostaje w `/etc/qjob/qjob.conf`.
W WCSS ustaw właściwą partycję, moduł GROMACS i ewentualny GPU GRES w
konfiguracji miejsca lub użytkownika. Przykłady są w
`site/gromacs.conf.example` i `site/gromacs-gpu.conf.example`.
`-v` wybiera wersję modułu; `GROMACS_MODULE_TEMPLATE` może zawierać `%v`.

Na laptopie z zainstalowanym GROMACS można użyć:

```bash
QJOB_PROFILE=local Gromacs --cpu --background -c 2 md.tpr
```

W `~/.config/qjob/gromacs.conf` można ustawić `GROMACS_BINARY=/pełna/ścieżka/gmx`
albo skonfigurować moduł. Qjob nie instaluje GROMACS na laptopie.
