# qjob — Slurm and local computational chemistry jobs

[English](README.md) | [Polski](README.pl.md)

A common set of wrappers for WCSS, bohr/bose/ligol, and local calculations.
The application code is shared; configuration selects the queue, resources,
scratch space, modules, and program paths. qjob does not install chemistry
software or provide its licences.

## Installation and environment selection

| Environment | Configuration selection | Execution |
|---|---|---|
| bohr, bose, ligol | Automatically from `/etc/qjob/*.conf` | Slurm |
| WCSS | `QJOB_PROFILE=wcss` | Slurm |
| macOS | Automatically selects `local` if no site configuration is present | Local |
| Linux without a scheduler | `QJOB_PROFILE=local` | Local |

`QJOB_PROFILE` **selects settings**; it does not install qjob, modules, or
applications. On a cluster, it need not be set if the administrator has configured
`/etc/qjob/`. The `local` profile means execution without Slurm, including on a
Linux laptop; it does not refer to the bohr/bose/ligol cluster.

### WCSS — installation in your user account

The consolidated `main` branch uses a single checkout:

```bash
git clone https://github.com/rgora/qjob.git "$HOME/.local/share/qjob"
bash "$HOME/.local/share/qjob/site/install-commands.sh" --profile wcss
export PATH="$HOME/.local/bin:$PATH"
```

Add the `export PATH` line to your shell configuration if this directory is not
already in PATH. The installer creates short wrappers pointing to one checkout
and sets `QJOB_PROFILE=wcss` by default. Alternatively, add `qjob/bin` to PATH
and set `export QJOB_PROFILE=wcss` yourself. Separate copies of qjob are not
needed for each program.

Set your allocation account in your own configuration, for example:

```bash
mkdir -p "$HOME/.config/qjob"
# In ~/.config/qjob/qjob.conf, using your actual project name:
# account='YOUR_WCSS_PROJECT'
```

You can also pass `-A PROJECT_NAME` when submitting a job. Module versions are
specified in `profiles/wcss/<app>.conf`; put your overrides in
`~/.config/qjob/<app>.conf`. The additional chemistry wrappers use a profile with
`lem-cpu-short` and local scratch space; ORCA retains its earlier WCSS resource
defaults. Run `COMMAND --help` before your first submission and adjust resources
with `-c`, `-m`, `-t`, and `-p`.

### bohr, bose, and ligol — shared installation

The administrator maintains the code in `/opt/qjob` and configuration outside
the checkout:

```bash
sudo git clone https://github.com/rgora/qjob.git /opt/qjob
sudo bash /opt/qjob/site/install-orca.sh
sudo bash /opt/qjob/site/install-commands.sh --bin-dir /usr/local/bin
```

`install-orca.sh` creates the initial `/etc/qjob/qjob.conf` for a recognised
host, the ORCA configuration, and `/scratch/qjob`. It preserves existing
configuration files. `install-commands.sh` makes the commands available; it does
not change site configuration or install applications. Optional command names
at the end restrict the selection, for example `Gaussian Xtb`. Example settings
for the other applications are in `site/*.conf.example`; place the corresponding
files in `/etc/qjob/<app>.conf`. The existing application installers in
`site/install-*.sh` remain available.

Do not set `QJOB_PROFILE=local` here: jobs should be submitted to Slurm.
Users run the programs without sudo. The partition names are `normal` on bohr,
`bose` on bose, and `ligol` on ligol. For example, the Gaussian module on ligol
requires:

```bash
# /etc/qjob/gaussian.conf
GAUSSIAN_MODULE=Gaussian
GAUSSIAN_MODULE_VERSION=16.C.01-NVHPC-21.3
```

On bose/bohr, Gaussian uses `/opt/gaussian` by default.
The virtual queue `-p global` requires separate configuration and a user service;
selecting a profile does not start it. See [README-GLOBAL.md](README-GLOBAL.md).

### Local execution

```bash
bash site/install-commands.sh --profile local
# Or for a single invocation:
QJOB_PROFILE=local Orca -c 4 -m 8 --background water.inp
```

Specify a native installation of the program in your user configuration.
Compatibility with the system Bash 3.2 on macOS is checked for ORCA and the
command installer; other programs may require Linux. ORCA/MPI setup for macOS
is described in [README-ORCA.md](README-ORCA.md).

## Usage

```bash
Orca -c 8 -m 16 -t 24 calculation.inp
Gaussian -c 8 -m 16 -t 24 molecule.com
Crest -c 4 -m 8 geometry.xyz --gfn2 --quick
OpenMolcas -c 4 -m 8 calculation.inp
QuantumEspresso -c 4 -m 8 -C 'H.UPF' calculation.in
Orca --debug calculation.inp           # Show the script without submitting it
```

`-c` sets the number of cores per node (MPI processes or threads, depending on
the program), `-n` the number of nodes, `-m` the total memory per node in GB, and
`-t` the time limit in hours or Slurm format. These are qjob options; older PBS
scripts may use the same letters with different meanings. Program memory
settings are synchronised only where documented by the wrapper. For example,
Gaussian receives 80% of the requested memory, whereas ORCA retains `%maxcore`
from the input and checks it against the allocated memory.

`-C 'files directories'` copies auxiliary input files to scratch space; `-B`
selects files to copy back. `--local` runs the calculation on the current
machine; `--background` runs it in the background. On WCSS, use these options
within an allocated compute session. `--debug` generates the job script without
running the application.

## Available commands

The program-specific guides linked below are currently in Polish.

| Commands | Guide |
|---|---|
| `Orca` | [ORCA on clusters and macOS](README-ORCA.md) |
| `Gaussian` (G16; also G09/G03 locally) | [Gaussian](README-GAUSSIAN.md) |
| `Gromacs` | [GROMACS](README-GROMACS.md) |
| `Turbomole` | [TURBOMOLE](README-TURBOMOLE.md) |
| `Bagel` | [BAGEL](README-BAGEL.md) |
| `Crest`, `Xtb` | [CREST/xTB](README-CREST-XTB.md) |
| `Newtonx` | [Newton-X](README-NEWTONX.md) |
| `OpenMolcas` | [OpenMolcas](README-OPENMOLCAS.md) |
| `Openqp` | [OpenQP](README-OPENQP.md) |
| `Cfour`, `Molpro`, `QuantumEspresso`, `Nwchem`, `Dalton`, `Cp2k` | [WCSS suite](README-WCSS-SUITE.md) |
| `QChem`, `Psi4oep` | [Q-Chem and Psi4+OEPDev](README-QCHEM-PSI4.md) |
| `sq`, `qglobal` | Slurm monitoring; [dispatcher](README-GLOBAL.md) |

## Configuration precedence

From lowest to highest priority:

1. Defaults in `apps/<app>.sh`.
2. `/etc/qjob/qjob.conf`, followed by `/etc/qjob/<app>.conf`.
3. The selected `profiles/<profile>/qjob.conf`, followed by `<app>.conf`.
4. `~/.config/qjob/qjob.conf`, followed by `<app>.conf`.
5. Command-line options.

The directories can be changed with `QJOB_CONFIG_DIR`, `QJOB_USER_CONFIG_DIR`,
or `XDG_CONFIG_HOME`. The `.conf` files are trusted Bash code. Updating the
repository does not overwrite configuration in `/etc/qjob/` or
`~/.config/qjob/`.

## Branches, updates, and migration

`main` originally contained the older WCSS code, whereas `site/shared-orca`
contained the shared cluster and macOS implementation. Keeping separate
branches protected the existing WCSS installation during development. The
program does not require this separation: the shared code supports all
environments. The consolidated `main` branch preserves the history of both
branches, including the identical `sq` file that had been added to them in
separate commits. New installations can use `main`; the older branch remains
available as a reference.

Before updating, check `git status` and your current branch. Save local changes
before running `git pull --ff-only`. Do not copy a whole repository over a
working checkout with uncommitted changes. When migrating an older installation,
first run the tests and compare the output of `COMMAND --debug` with your
existing configuration.

Earlier WCSS deployments used several copies (`qjob-*`) and separate wrappers
in `~/bin`. The new installer can replace selected wrappers while keeping
backup copies. Migration requires moving your allocation account and other
personal settings to `~/.config/qjob/`; publishing the consolidated code does
not migrate existing installations.

## Tests and repository structure

```bash
bash tests/run.sh
```

The tests use mock applications and Slurm commands to check input staging,
results, errors, resources, profiles, and the dispatcher's response to lost
replies. They do not replace real calculations or checks of a cluster's modules.
Earlier calculation tests are described in the program-specific guides.

`bin/` contains the commands, `apps/` the application adapters, `lib/qjob.sh`
the options and Slurm headers, and `lib/runtime.sh` the execution and file
copying logic. `profiles/` and `site/` contain settings and installers. When
adding an adapter, put helper functions in `APP_FUNCS` and variables passed to
the job in `APP_VARS`.

MIT; see [LICENSE](LICENSE).
