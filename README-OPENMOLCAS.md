# OpenMolcas with qjob

Submit a single-node calculation:

```sh
OpenMolcas -c 4 -m 8 -t 24 calculation.inp
OpenMolcas --openmp -c 4 -m 8 calculation.input
OpenMolcas -C 'geometry.xyz restart.JobIph' calculation.inp
OpenMolcas --debug calculation.inp
```

`-c` is the MPI process count by default, or the thread count with `--openmp`.
`-m` is total node memory in GiB. The wrapper assigns 80% of that memory to
Molcas, divided by the MPI process count, leaving space for libraries and other
allocations. It calls `pymolcas` once; the driver launches MPI executables.

The command accepts `.inp` and `.input` files. It stages the input and files
selected by `-C` in local scratch. Use relative paths to staged auxiliary files.
OpenMolcas' native exports, `JobIph`, `JobMix`, `RunFile`, `ChVec`, HDF5 files
and stdout/stderr logs return in a separate directory
`<input-base>-qjob-<hostname>-<jobid>/`. Large intermediate integral files stay in
scratch. Scratch is removed after a successful run and copy-back, and retained
on failure. Other auxiliary files needed later must be exported by the input or by the
native Molcas file mapping. For example, use an EMIL `COPY` from `$WorkDir` to
`$CurrDir` for a file outside the standard result and restart set.

User and installation `molcasrc` files are ignored using `pymolcas -ign`, so
resource settings come from qjob. Input EMIL commands can still change settings;
keep their requests within the Slurm allocation.

Local cluster defaults are `/etc/qjob/openmolcas.conf`, selecting
`OpenMolcas/25.06-gompi-2025b`. The EasyBuild recipe enables MPI, OpenMP, HDF5,
Libxc 7 and ILP64 OpenBLAS; it uses Global Arrays 5.8.2 with MPI two-sided transport. Optional DMRG, NECI and external wavefunction-analysis interfaces
are not enabled. Each host builds its own installation.

The WCSS profile selects `OpenMolcas/25.06-openmpi-kdm` on `lem-cpu-short`,
account `hpc-rgora-1721393588`. BEM2 does not provide this module. The private
bundle is `~/bin/qjob-openmolcas`, with entry point `~/bin/OpenMolcas`.
The profile also loads Python-bundle-PyPI/2024.06-GCCcore-13.3.0 for pyparsing
and OpenBLAS/0.3.27-GCC-13.3.0-seq-iface64 for the missing ILP64 library.
The readable, non-executable site pymolcas script is invoked through Python.
On WCSS, scratch lifetime after an allocation ends is controlled by the site;
qjob retaining a failed scratch directory does not override Slurm cleanup.

Install the local command with `sudo /opt/qjob/site/install-openmolcas.sh` after
copying this application's files into `/opt/qjob`. Existing command paths are
backed up before the symlink is created; existing site configuration is kept.

Validation details and evidence are recorded in `openmolcas-install` in the
Cluster workspace; do not infer runtime success from script-generation tests.
