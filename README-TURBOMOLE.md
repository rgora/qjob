# TURBOMOLE przez qjob

Na bose pakiet **TURBOMOLE 8.0.1** jest instalowany przez EasyBuild, jako
`TURBOMOLE/8.0.1`. Osobny moduł `TmoleX/8.0.1` udostępnia interfejs
**TmoleX26** z dystrybucji 8.0.1 i ładuje moduł obliczeniowy.

W katalogu z przygotowanymi plikami `control`, `coord`, `basis`, `mos` itd.:

```bash
Turbomole -c 4 -m 8 -t 24 ridft
Turbomole -c 4 -m 8 -t 24 jobex -ri -c 200
Turbomole --arch mpi -c 4 -m 8 ridft
```

Opcje po nazwie programu są przekazywane do programu. Domyślnie qjob stosuje
SMP, 4 rdzenie, 8 GB i 24 godziny. Przy jednym rdzeniu wybiera program
szeregowy. MPI stosuje jeden wątek OpenMP na proces; SMP przydziela tyle
wątków, ile rdzeni. Na tej instalacji zadania mieszczą się na jednej maszynie.

Wyniki i zmiany plików TURBOMOLE pozostają w katalogu roboczym.
`TURBOTMPDIR` wskazuje prywatny lokalny scratch qjob. Standardowy zapis
programu trafia do `<katalog>_<program>.log`; poprzedni zapis do `.old`.
Scratch jest usuwany po sukcesie zgodnie z ustawieniem `clean_tmp`.

Przygotowanie wejścia bez zgłoszenia do kolejki:

```bash
Turbomole --local -c 1 x2t water.xyz > coord
Turbomole --local -c 1 define
Turbomole --env -c 4 ridft
```

`--init` wykonuje dodatkowo `dscf`, a przy `$rij` w `control` — `ridft`.
Przed obliczeniami wymagany jest `control`. `-v` zmienia wersję modułu.

GUI uruchamia się w sesji z dostępnym ekranem X11:

```bash
module load TmoleX/8.0.1
tmolex
```

Konfiguracja bose jest w `/etc/qjob/turbomole.conf`, kod w
`/opt/qjob/apps/turbomole.sh`, a polecenie w `/usr/local/bin/Turbomole`.
`site/install-turbomole.sh` instaluje konfigurację, jeśli jej brak, i zachowuje
poprzednie polecenie jako `.old`. Domyślny moduł na innych profilach pozostaje
`turbomole`, zgodnie z dotychczasową konfiguracją WCSS.

Globalny dispatcher qjob obsługuje obecnie aplikacje przyjmujące pliki
wejściowe; `Turbomole` przyjmuje nazwę programu i pracuje na całym katalogu,
więc należy wskazać lokalną partycję.
