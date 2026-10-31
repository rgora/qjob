source "$QJOB_ROOT/apps/suite-common.sh"
APP_TASKS=mpi
SUITE_MODULE=QuantumESPRESSO
SUITE_PROGRAM=pw.x
APP_LONG='program:'
app_option() {
    case $1 in
        --program)
            [[ $2 =~ ^[a-zA-Z0-9_]+\.x$ ]] || die 'use a Quantum ESPRESSO executable name ending in .x'
            SUITE_PROGRAM=$2; APP_SHIFT=2 ;;
        *) return 1 ;;
    esac
}
app_run() {
    local result_dir
    suite_stage || return 1
    suite_execute mpirun -np "$cores" "$SUITE_PROGRAM" -in "$input"
}

app_usage() {
    suite_usage
    echo '  --program NAME.x    executable to launch (default: pw.x; e.g. ph.x).' >&2
    echo '  Use relative outdir/pseudo_dir in the input and -C to stage .UPF/restart data.' >&2
    echo '  Alternative build: -v 7.5-foss-2025a' >&2
}
