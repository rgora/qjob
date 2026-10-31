# BAGEL through qjob

`Bagel` runs one BAGEL JSON input per job on one node. The default mode uses
`-c` MPI processes with one BAGEL/BLAS thread per process. `--openmp` uses one
process with `-c` BAGEL/BLAS threads. Both modes start through `mpirun`,
including MPI-enabled binaries in threaded mode. The command sets
`BAGEL_NUM_THREADS` explicitly.

## Local cluster

After installing `BAGEL/1.2.2-foss-2025b` with EasyBuild, install the command:

```bash
sudo /opt/qjob/site/install-bagel.sh
Bagel -c 8 -m 16 -t 24 molecule.json
Bagel --openmp -c 8 -m 16 -t 24 molecule.json
```

Module selection is in `/etc/qjob/bagel.conf`; partition and local scratch
remain in `/etc/qjob/qjob.conf`. The command is `/usr/local/bin/Bagel`.

## WCSS

The `wcss` profile selects `BAGEL/1.2.2-foss-2021a` and `lem-cpu-short`.
The profile initializes modules on the compute node. The WCSS login node does
not provide the module command. On Lem, the profile selects Open MPI 4 shared
memory transport (`ob1` with `self,vader`) for single-node jobs, avoiding the
older UCX/InfiniBand stack. A user installation is sufficient.

```bash
QJOB_PROFILE=wcss /path/to/qjob/bin/Bagel -c 8 -m 16 -t 24 -s shm:20g molecule.json
```

The installed `~/bin/Bagel` wrapper selects this profile automatically:

```bash
Bagel -c 8 -m 16 -t 24 -s shm:20g molecule.json
Bagel -p lem-cpu-normal -c 8 -m 16 -t 96 -s local:40g molecule.json
```

WCSS adds the requested SHM storage to the memory reservation. Adjust storage,
account (`-A`) and QoS (`-q`) to the input and allocation. `--debug` prints the
batch script without submitting it.

## Files and restart

Results are copied to `<input-stem>-qjob-<host>-<jobid>/`, including the original JSON,
`stdout.log`, `stderr.log`, and all files written by BAGEL. Each run has its own
directory; the hostname distinguishes equal job IDs on independent clusters. A failed process returns a failure status, results are copied back,
and scratch is retained under the default cluster cleanup policy.

Stage files referenced by relative paths in the JSON explicitly:

```bash
Bagel -C 'geometry.xyz previous.archive' molecule.json
```

The JSON is copied unchanged. A restart must be requested in the BAGEL input;
qjob does not edit geometry, memory settings or archive paths in the JSON.
`-m` reserves memory in Slurm and does not rewrite BAGEL's input parameters.

For an interactive allocation, use `--local` with a matching MPI task count,
or `--local --openmp` with a matching CPUs-per-task allocation. MPI mode uses
Open MPI's Slurm integration; `--local` does not create an allocation.

References: [BAGEL execution and thread variables](https://nubakery.org/quickstart/how_to_run_bagel.html),
[official releases](https://github.com/qsimulate-open/bagel/releases).

## Validation on 2026-10-21

| Environment | Module | HF, 2 MPI processes | CASSCF/CASPT2, 2 threads |
| --- | --- | --- | --- |
| bohr | `BAGEL/1.2.2-foss-2025b` | PASS | PASS |
| bose | `BAGEL/1.2.2-foss-2025b` | PASS | PASS |
| ligol | `BAGEL/1.2.2-foss-2025b` | PASS | PASS |
| WCSS Lem | `BAGEL/1.2.2-foss-2021a` | PASS | PASS |

Local calculations used the installed `Bagel --local` command. Generated MPI
and threaded batch scripts passed `sbatch --test-only`. WCSS calculations ran
inside an existing two-CPU interactive Slurm allocation; the MPI test used an
isolated local launcher because that allocation contained one Slurm task with
two CPUs. Production batch scripts request one Slurm task per MPI process.

The HF test energy was -99.84772354 Eh and the CASPT2 test energy was
-100.0623174419 Eh in all environments (agreement within the printed precision;
verification tolerance: 1e-6 Eh). These are small installation smoke tests.
Both the static and shared libxc builds passed all 20556 upstream tests on
each local host.

Shared commands are installed under `/usr/local/bin/Bagel`; WCSS uses
`~/bin/Bagel` and its separate `~/bin/qjob-bagel` directory. Previous shared
commands and configuration are preserved under `/var/backups/qjob-bagel/`.
