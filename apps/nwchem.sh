source "$QJOB_ROOT/apps/suite-common.sh"
APP_TASKS=mpi
SUITE_MODULE=NWChem
SUITE_PROGRAM=nwchem
app_run() {
    local result_dir
    suite_stage || return 1
    suite_execute mpirun -np "$cores" nwchem "$input"
}
