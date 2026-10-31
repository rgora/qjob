source "$QJOB_ROOT/apps/suite-common.sh"
APP_TASKS=threads
SUITE_MODULE=cfour
SUITE_PROGRAM=xcfour
app_run() {
    local result_dir
    suite_stage || return 1
    export OMP_NUM_THREADS=$cores OMP_THREAD_LIMIT=$cores MKL_NUM_THREADS=$cores CFOUR_NUM_CORES=1
    # xcfour is a serial driver; one process with threaded BLAS avoids MPI oversubscription.
    [[ $input == ZMAT ]] || cp -- "$input" ZMAT || return 1
    if [[ ! -f GENBAS && -f ${GENBAS:-/nonexistent} ]]; then cp -- "$GENBAS" GENBAS || return 1; fi
    if [[ ! -f GENBAS ]]; then
        local executable prefix
        executable=$(command -v xcfour)
        prefix=$(cd "$(dirname "$executable")/.." && pwd) || return 1
        [[ ! -f $prefix/basis/GENBAS ]] || cp "$prefix/basis/GENBAS" . || return 1
    fi
    [[ -f GENBAS ]] || { qjob_msg 'GENBAS missing: stage it with -C GENBAS'; return 1; }
    [[ -f ECPDATA || ! -f ${ECPDATA:-/nonexistent} ]] || cp -- "$ECPDATA" ECPDATA || return 1
    suite_execute xcfour
}
