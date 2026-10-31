source "$QJOB_ROOT/apps/suite-common.sh"
APP_TASKS=mpi
SUITE_MODULE=CP2K
SUITE_PROGRAM=cp2k.psmp
app_run() {
    local result_dir
    suite_stage || return 1
    suite_execute mpirun -np "$cores" "$SUITE_PROGRAM" -i "$input" -o "$base.out"
}
