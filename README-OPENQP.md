# OpenQP

Polecenie `Openqp` korzysta z modułu `OpenQP/1.3.1-foss-2025b` na bohr,
bose i ligol. Domyślnie rezerwuje jedną maszynę, 4 rdzenie, 8 GB i 24 godziny.
Każdy plik `.inp` lub kanoniczny `.oqp` oznacza osobne zadanie.

```bash
Openqp -c 4 -m 8 -t 24 water.inp          # jeden proces, 4 wątki OpenMP
Openqp --mpi -c 4 -m 8 water.inp          # 4 procesy MPI, po jednym wątku
Openqp -C 'geometry.xyz restart.json' calculation.inp
Openqp --debug -c 2 water.inp            # pokaż skrypt bez zgłoszenia
Openqp -p global -c 4 -m 8 water.inp     # wejścia i pliki pomocnicze w /shared
```

Wejście jest kopiowane bez zmian do prywatnego scratch. Pliki `.xyz` i `.json`
o tej samej nazwie bazowej są kopiowane domyślnie; pozostałe pliki pomocnicze
wskaż przez `-C`. Wątki ogranicza przydział `-c` i `OMP_THREAD_LIMIT`;
w trybie MPI każdy proces używa jednego wątku OpenMP. Wielowątkowy BLAS jest
wyłączony, aby nie mnożyć liczby wątków ponad rezerwację.

Wyniki wracają do osobnego katalogu `<nazwa>-qjob-<jobid>/`: zawiera on kopię
wejścia, natywny `<nazwa>.log`, `stdout.log`, `stderr.log`, pliki JSON i inne
produkty obliczenia. Taki sam katalog jest kopiowany także po błędzie;
scratch pozostaje wtedy do diagnostyki. `-B` zastępuje domyślne kopiowanie
tego katalogu. Do uruchomienia na przydzielonych interaktywnie zasobach służy
`Openqp --local`; `--background` uruchamia obliczenie lokalne w tle.

Instalacja dodatku w istniejącym `/opt/qjob`: `sudo bash site/install-openqp.sh`.
Ustawienia aplikacji znajdują się w `/etc/qjob/openqp.conf`, a osobiste ustawienia
w `~/.config/qjob/openqp.conf`. Instalator zachowuje istniejącą konfigurację.
Testy bez OpenQP i Slurma: `bash tests/test_openqp.sh`.
