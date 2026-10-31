# Gaussian with qjob

Default: Gaussian 16, one node, shared memory. Local installations on bose/bohr
use `/opt/gaussian/g16`; WCSS loads `gaussian/16.C.02`.
The ligol source-build profile uses EasyBuild module `Gaussian/16.C.01-NVHPC-21.3`.

```
Gaussian -c 8 -m 16 -t 24 molecule.com
Gaussian -c 8 -m 16 -C 'previous.chk geometry.xyz' restart.gjf
Gaussian --debug -c 2 -m 2 molecule.inp
Gaussian -v g09 -c 4 -m 8 molecule.com  # existing local legacy installation
```

`-m` is total Slurm memory in GiB. Gaussian receives 80% of this reservation,
leaving room for process overhead. `-c` sets shared-memory cores. Working copies
replace CPU/memory/Linda directives in every Link1 section and omit `%RWF` so
qjob controls scratch. The input file in the submission directory is unchanged.
Original and working inputs, checkpoint and log files are returned under
`<base>-qjob-<host>-<id>/`. A missing `%chk` gets a default `<base>.chk` in the
first section. Existing relative checkpoint names are preserved. Use `-C` for
restart and auxiliary files; use relative paths. Absolute checkpoint/integral
paths and parent-directory traversal are rejected. Native large scratch files
are not copied back; scratch is retained on failure. Gaussian must return zero
and its final nonblank output line must report normal termination.

This interface uses qjob's options: `-n` means nodes, `-c` cores, and `-m` total
memory. It differs from the former PBS `Gaussian` script. A dated backup of that
script is retained on bose/bohr.

The source build on ligol uses NVIDIA Fortran 21.3, AVX2 CPU instructions,
and tcsh. Recipes and the compiler sanity check are kept under
`/opt/easybuild/easyconfigs/Gaussian/`. The compiler sanity check validates
fixed-form Fortran, OpenMP and 64-bit integer options; it does not certify
the 2021 C++ compiler with the current system C++ headers.
Gaussian C code is compiled with system GCC. GPU and Linda builds are excluded.
Validation on 2026-10-31: all 85 Gaussian executables built. Seven comparisons
against the existing C.01 on bose passed (12 quantities: HF, DFT, MP2, CCSD(T),
optimization/frequencies, TD-DFT, and an open-shell calculation). Maximum
reported energy difference: approximately 1e-10 Eh. Printed frequencies and
excitation energies matched. Old-checkpoint restart, actual Link1 calculation
and formchk also passed. This covers the selected calculations, not the full
Gaussian regression suite.

Real Slurm H2 runs passed on bose (149) and WCSS (6204275). On bohr and ligol,
real local calculations and sbatch --test-only passed; busy queues prevented
an immediate scheduler run. No validation job remains pending.

Validation files: `/shared/rgora/qjob-gaussian-validation-20261031/` and
WCSS `~/PD/tests/qjob-gaussian-20261031/`.

To rebuild ligol from source, activate the existing EasyBuild environment,
source Lmod, and use the full recipe
`/opt/easybuild/easyconfigs/Gaussian/Gaussian-16.C.01-NVHPC-21.3.eb` with
`--prefix=/opt/easybuild --sourcepath=/opt/easybuild/sources --umask=007 --parallel=1`.
The `resume-Gaussian-*.eb` file records recovery from the parallel attempt;
it is not the full fresh-install recipe. Compiler installation additionally
uses `--include-easyblocks=/opt/easybuild/easyconfigs/Gaussian/nvidiagaussian.py`
and `--accept-eula-for=NVHPC`. The compiler archive has been verified against
NVIDIA's MD5 checksum and is pinned by SHA256 in the recipe.
