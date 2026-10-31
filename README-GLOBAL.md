# Kolejka global (dispatcher)

Na bohr/bose/ligol można kierować nowe zadania do wspólnego dispatchera:

```bash
cd /shared/rgora/obliczenia
Orca -p global -c 8 -m 20 -t 72 calculation.inp
Orca -p global -c 16 -m 80 -t 72 *.inp
Orca -p global --debug -c 4 -m 8 calculation.inp
qglobal status
qglobal cancel global-IDENTYFIKATOR
```

`global` jest wirtualną kolejką qjob. Trzy lokalne kontrolery Slurma pozostają
niezależne; `squeue` pokazuje tylko zadania już przekazane do danego kontrolera.
Oczekujące zadania globalne sprawdza się przez `qglobal status`. Polecenie to
można wywołać na każdej z trzech maszyn; odczytuje ono stan na koordynatorze bose.
Identyfikator lokalny zawsze należy rozpatrywać razem z nazwą hosta.

Dispatcher co 20 sekund generuje skrypt z konfiguracją maszyny docelowej
i sprawdza przewidywany start poleceniem `sbatch --test-only`. Zgłasza zadanie
na jedną maszynę, która według Slurma może rozpocząć je teraz. Gdy wszystkie
pasujące maszyny są zajęte lub niedostępne, zadanie pozostaje w kolejce globalnej.
Szacunek Slurma nie jest rezerwacją: inny użytkownik może w międzyczasie zająć
zasoby i przekazane zadanie będzie wtedy oczekiwać lokalnie. Dispatcher nie
przenosi już przekazanych ani uruchomionych zadań między kontrolerami.

Katalog roboczy, pliki wejściowe i potrzebne pliki pomocnicze muszą znajdować
się w `/shared` i być dostępne na docelowym hoście. Dispatcher nie kopiuje
automatycznie danych z lokalnego `/home` i nie zamraża treści wejść w chwili
zgłoszenia. Obliczenia używają lokalnego scratch według ustawień docelowej
maszyny. Wyniki wracają do tego samego katalogu w `/shared`.

Zasoby przekazywane są bez zmniejszania żądania użytkownika. Obecne limity
dispatchera: bohr/bose 32 rdzenie i 488 GB, ligol 8 rdzeni i 175 GB.
Na ligol Slurm aktualnie udostępnia 16 logicznych CPU jako 8 rdzeni z SMT;
przy `--hint=nomultithread` próba żądania 16 procesów jest odrzucana przez Slurma.
Nie zmieniamy tu topologii ligol ani lokalnych limitów qjob. Po świadomej zmianie
topologii należy zaktualizować `/etc/qjob/global.json` i wykonać rzeczywisty test.

Pierwsza wersja obsługuje zadania plikowe na jednej maszynie, przede wszystkim
ORCA. Odrzuca zależności w `--slurmopt`, ręczne wskazanie węzła, konto, QoS,
rezerwację, GRES, `--exclusive`, pocztę i wykonanie lokalne. Te opcje mogą mieć
inne znaczenie w każdym niezależnym kontrolerze. Zwykłe zgłoszenia bez
`-p global` zachowują dotychczasowe działanie. Nie ustawiaj `partition=global`
jako domyślnej partycji maszyn docelowych.

### Instalacja i działanie usługi

Na każdej maszynie, z przygotowanej kopii tego repozytorium:

```bash
sudo bash site/install-global.sh
```

Instalator zachowuje wcześniejsze pliki w `/var/backups/qjob-global-*`, dodaje
`QJOB_DISPATCH_HOST=bose` do konfiguracji i instaluje `/etc/qjob/global.json`.
Nie zmienia konfiguracji Slurma ani istniejących zgłoszeń. Na bose instaluje
szablon usługi systemowej działającej jako konkretny użytkownik:

```bash
sudo systemctl enable --now qjob-global@rgora
systemctl status qjob-global@rgora
journalctl -u qjob-global@rgora
```

Dla kolejnych użytkowników trzeba zapewnić ich własny dostęp SSH i uruchomić
osobne instancje usługi. Dispatcher nie działa jako root i nie zmienia właściciela
zadań. Każdy użytkownik ma osobną trwałą kolejkę w
`~/.local/state/qjob-global` na bose (katalog prywatny, tryb 0700).
Usługa systemowa działa również po wylogowaniu; nie wymaga sesji Maca ani linger.

Koordynator potrzebuje sprawdzonych kluczy hostów i uwierzytelniania SSH do
wszystkich trzech maszyn, także do siebie. Jeśli istnieje klucz
`~/.ssh/qjob-global_ed25519`, dispatcher używa go z `IdentitiesOnly=yes`.
Prywatny klucz pozostaje na bose. Dodanie jego klucza publicznego do kont na
maszynach docelowych jest odrębną zmianą dostępu; zalecane ograniczenie wpisu
`authorized_keys` to `restrict,from="156.17.2.232"` dla obecnego adresu bose.

### Odporność na przerwane zgłoszenie

Przed kontaktem z `sbatch` dispatcher zapisuje stan `SUBMITTING` na dysku.
Każda próba ma unikalną nazwę `global-<UUID>` w Slurmie. Po utracie odpowiedzi
sprawdza `squeue` oraz `sacct`, zamiast wysyłać obliczenie ponownie. Przy braku
jednoznacznego potwierdzenia pozostawia `SUBMITTING` do sprawdzenia przez
administratora. Dotyczy to również jednoznacznie odrzuconej próby, jeśli nie
uzyskano numeru zadania; automatyczne ponawianie jest celowo wyłączone.
Nie zmieniaj takiego rekordu na `PENDING` bez wykluczenia zgłoszenia na hoście
zapisanym w rekordzie. Historia zakończonych zadań pozostaje w kolejce.

`qglobal cancel` usuwa z dalszego dispatchu zadanie jeszcze oczekujące globalnie.
Dla zadania już przekazanego wysyła `scancel` na właściwym hoście. Stan
potwierdza kolejne wywołanie `qglobal status`; przy nieustalonym numerze lokalnym
polecenie odmówi anulowania i poprosi o sprawdzenie hosta.

Testy bez klastra: `python3 tests/test_global.py`. Obejmują kolejkę wielu wejść,
dobór zasobów, odrzucenie lokalnych ścieżek i zależności, oczekiwanie na wolne
zasoby oraz utratę odpowiedzi `sbatch` bez podwójnego zgłoszenia.

Wdrożenie sprawdzone 2026-10-20 dla konta `rgora`: usługa na bose aktywna
i włączona po restarcie. Test ORCA/H2 zgłoszony z bohr przez `-p global`
(32 rdzenie, 4 GB) został przekazany na bohr jako zadanie 29; kolejne zgłoszenie
z ligol (2 rdzenie, 2 GB) trafiło na ligol jako zadanie 16, gdy bohr był zajęty.
Oba zadania mają `COMPLETED`, `ExitCode=0:0` i komunikat
`ORCA TERMINATED NORMALLY`. Wejścia i logi pozostawiono w
`/shared/rgora/qjob-global-validation-20261020`. Potwierdzono też pozostawienie
zadania w globalnej kolejce oczekującej i jego anulowanie przed przekazaniem.
Pozostałe konta wymagają własnej instancji usługi i dostępu SSH.
