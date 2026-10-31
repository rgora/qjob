# WCSS chemistry wrappers

User commands are installed in `$HOME/bin`; the isolated implementation is in
`$HOME/bin/qjob-wcss-suite`. The WCSS profile selects `lem-cpu-short`, the user's
existing accounting project, and the WCSS module initialization script.

| Command | Default module | Input | Parallel execution |
| --- | --- | --- | --- |
| Crest | CREST/3.0.2-GCCcore-14.2.0 | geometry.xyz, then native options | OpenMP |
| Cfour | cfour/2.1-intel2023a | ZMAT or another input filename | One driver, threaded BLAS/OpenMP |
| Molpro | molpro/2026.1.0 | input.inp | Native Molpro MPI launcher |
| QuantumEspresso | QuantumESPRESSO/7.5-lfoss-2025b | input.in | MPI; pw.x by default |
| Nwchem | NWChem/7.2.2-intel-2023a | input.nw | MPI |
| Dalton | Dalton/2020.1-foss-2023b | name.dal and name.mol | Native Dalton MPI launcher |
| Cp2k | CP2K/2025.2 | input.inp | MPI, cp2k.psmp with one thread per rank |

Defaults: one node, four cores, 8 GB RAM, 24 hours and 40 GB of local disk scratch. Select resources with `-c`,
`-m`, `-t`, and `-p`. Multi-node execution is intentionally rejected because each
job uses private node-local scratch. Native memory settings still belong in the
input; `-m` is the Slurm reservation in GB, not a native application memory unit.

```sh
Crest -c 8 -m 16 molecule.xyz --gfn2 --quick
Cfour -c 8 -m 16 ZMAT
Molpro -c 8 -m 16 calculation.inp
QuantumEspresso -c 8 -m 16 -C 'H.UPF' calculation.in
Nwchem -c 8 -m 16 calculation.nw
Dalton -c 8 -m 16 hf.dal
Dalton -c 8 --molecule water hf.dal
Cp2k -c 8 -m 16 calculation.inp
QuantumEspresso -v 7.5-foss-2025a -c 8 calculation.in
QuantumEspresso --program ph.x -c 8 phonons.in
```

Dalton defaults to a `.mol` file with the same basename as `.dal`; the first
Dalton example therefore requires `hf.mol`. Stage auxiliary inputs and restart
files/directories with `-C 'file1 directory2'`. Paths in native input files must
refer to these staged locations. QE `outdir='./qe-tmp'` and `pseudo_dir='.'` keep
state inside the result directory. Absolute native paths remain absolute.

Results are copied to `<input-base>-qjob-<jobid>/` (CREST also includes hostname).
The directory contains stdout.log, stderr.log, native outputs and restart data,
including hidden files. Scratch is deleted after success and retained on failure
subject to WCSS allocation cleanup. `-B` overrides copy-back selection. Each
program loads its own module after `module purge`, retaining the MPI stack from
that installation. CFOUR stages the module's GENBAS and ECPDATA unless supplied
explicitly with `-C`; CFOUR_NUM_CORES=1 prevents the driver from spawning extra MPI
processes while `-c` controls threading.

## Validation, 2026-10-21

All module names and executables were checked on the WCSS Lem compute node.
Local integration tests cover allocation directives, staging, logs, hidden
restart files, failure status, scratch retention and the one-node restriction.
Actual H2 calculations were run through all seven wrappers with two allocated
CPUs inside a WCSS Slurm interactive allocation (job 6135785); all returned zero.
MPI process counts were checked in the native outputs where reported. The initial Molpro smoke input used bohr; the final check explicitly uses angstrom.
These checks exercise `--local` within the allocation; they are distinct from direct
batch submissions. Generated batch scripts are separately checked with
`sbatch --test-only`. Test inputs and detailed evidence are kept under
`$HOME/qjob-wcss-suite/`.

## Quantum ESPRESSO toolchains

`lfoss/2025b` is based on LLVM (WCSS loads LLVM 20.1.8 and Open MPI 5.0.8);
`foss/2025a` is based on GCC 14.2.0 and Open MPI 5.0.7. Both are builds of QE 7.5,
with different compilers and dependent library versions. Do not manually mix
MPI libraries across the two builds. Neither name implies a universal speed or
accuracy advantage; compare on the actual workload.

References:
- https://docs.easybuild.io/api/easybuild/toolchains/lfoss/
- https://docs.easybuild.io/common-toolchains/
- https://www.molpro.net/manual/doku.php?id=running_molpro
- https://www.quantum-espresso.org/Doc/user_guide/node19.html
