# Newton-X qjob integration

`Newtonx` runs one prepared directory per job. The installed package is the
upstream Newton-X 26a release, containing NX-CS and NX-NS executables and source.
The trajectory driver is serial; requested CPUs are available to its quantum
chemistry backend. Match the backend input parallelism and memory to the request.

From a prepared NX-NS trajectory directory:

```bash
Newtonx -c 4 -m 8 -t 24 --backend orca nx_moldyn
```

For an NX-CS trajectory:

```bash
Newtonx -c 4 -m 8 -t 24 --backend orca moldyn.pl
```

For input preparation and initial conditions:

```bash
Newtonx --local nx_geninp
Newtonx --local icinp
Newtonx -c 1 -m 4 initcond.pl
```

`--local` runs in the current directory and allows interactive input. Normal
batch submission stages the directory, including resolved symbolic links, into
local scratch and returns its files to `<directory>-qjob-<jobid>/`. Standard output
and errors are in `stdout.log` and `stderr.log` inside this result directory.
Previous result directories, Slurm logs and generated batch scripts are excluded
from staging. A failed run retains scratch as well as returning its results.
To restart, prepare the returned directory using the appropriate Newton-X restart
utility and submit from that directory.

Backends: `none` (default, e.g. analytical models), `orca`, `turbomole`,
`openmolcas`, `bagel`. Backend selection loads the configured module and sets
common interface environment variables; it does not modify input parameters.
`--modules 'Module/version ...'` loads additional modules. Paths and module names
belong in `/etc/qjob/newtonx.conf`, a profile, or `~/.config/qjob/newtonx.conf`.
The integration is limited to one node per trajectory. Submit separate jobs for
an ensemble; directory-based jobs do not support the `global` dispatcher.

## Installation layout

On bohr, bose and ligol:

- EasyBuild recipe: `Newton-X-26a.eb`; module: `Newton-X/26a`.
- Software: `/opt/easybuild/software/Newton-X/26a`.
- Command: `/usr/local/bin/Newtonx` -> `/opt/qjob/bin/Newtonx`.

On WCSS:

- Software: `$HOME/PD/opt/Newton-X/26a`.
- Command: `$HOME/bin/Newtonx`, private runtime `$HOME/bin/qjob-newtonx`.
- Environment: `source ~/PD/opt/Newton-X/26a/env.sh`.
- Compute-node module: `module use ~/PD/opt/modules; module load Newton-X/26a`.
- Default queue/account: `lem-cpu-short`, `hpc-rgora-1721393588`; override with
  `-p`, `-A`, or user configuration as appropriate for the requested wall time.

The WCSS default ORCA module is site-selected (`ORCA`); the cluster pins ORCA
6.1.1. Backend interfaces require their own electronic-structure inputs. Analytical
model validation does not establish that every backend/method combination works.
Optional Python applications MELTS, ULaMDyn and Skitten are included as upstream
source, with no separate Python environment installed by this deployment.

## Verification

`bash tests/test_newtonx.sh` tests directory staging, symbolic links, copy-back,
exit-code propagation, failed-scratch retention and resource validation.
Real NX-CS and NX-NS analytical Tully model trajectories were run through qjob
on all four installation targets. Batch-runtime scripts were also executed
directly to test local scratch and returned results. Scheduled submissions passed
`sbatch --test-only`; actual scheduling validation was unavailable while queues
were occupied, and the pending smoke jobs were cancelled.
