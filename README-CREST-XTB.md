# CREST and xTB

`Crest` and `Xtb` submit one calculation to the local Slurm controller.
The lower-case `crest` and `xtb` executables are provided by modules.

```bash
Crest -c 4 -m 8 -t 24 molecule.xyz --gfn2 --quick
Xtb -c 4 -m 8 -t 2 molecule.xyz --gfn 2 --opt
Xtb -c 4 molecule.xyz --chrg -1 --uhf 1 --alpb water --opt
Crest -c 4 -C constraints.inp molecule.xyz --cinp constraints.inp
```

Run in the geometry directory. qjob options precede the geometry; native
program options follow it. Thread counts come from `-c`; native `-T`, `-P`
and `--parallel` overrides are rejected. Use one node per calculation.
The `global` dispatcher does not support these argument-based wrappers.

Defaults: four threads, 8 GB, 24 hours. Each run stages the geometry and
`-C` auxiliary files into a new local scratch directory. All calculation
files, including hidden restart files, are returned to
`<geometry-base>-qjob-<host>-<jobid>/`. Program output is in `stdout.log` and
`stderr.log`; qjob progress is in the Slurm log. Successful scratch is
removed according to site configuration; failed scratch is retained.
Old result directories are preserved. Use `-C` to stage restart files
and supply their native program options as needed.

The total Slurm memory request is a resource limit, not an xTB workspace
parameter. OpenMP uses the requested cores; BLAS threads are restricted to
one to avoid nested parallelism. `OMP_STACKSIZE=1G` is a per-thread stack
limit, not a preallocated memory reservation.

## Modules and installation

Both programs are compiled from release sources with EasyBuild:

```bash
module load CREST/3.0.2-gfbf-2025b
# Or only xTB:
module load xtb/6.7.1-gfbf-2025b
```

`/etc/qjob/crest.conf` and `/etc/qjob/xtb.conf` select module versions.
The wrappers purge inherited modules before loading their configured module.
Install into an existing `/opt/qjob` tree with:

```bash
sudo /opt/qjob/site/install-crest-xtb.sh
```

The installer preserves existing configuration and command links. Recipe
sources, checksums, upstream patches and build logs are recorded by EasyBuild
under each software installation's `easybuild/` directory. No binary release
archive is used to install the programs.
