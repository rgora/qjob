# One isolated scratch directory per calculation; native options follow geometry.
APP_INPUT=args
APP_TASKS=threads
APP_SYNOPSIS='geometry.xyz [native program options]'
cores=4 memory=8 time_limit=24
copy_back='%b-qjob-*'
CHEM_PROGRAM='xtb'
CHEM_MODULE='xtb'
CHEM_PURGE_MODULES=true
chem_args=()
APP_VARS='CHEM_PROGRAM CHEM_MODULE CHEM_PURGE_MODULES chem_args'
app_usage() {
    echo '  Native options go after the geometry; qjob -c controls threads.' >&2
    echo '  Results: <geometry-base>-qjob-<host>-<jobid>/, with stdout.log and stderr.log.' >&2
    echo "  Example: $QJOB_CMD -c 4 molecule.xyz --gfn 2 --opt" >&2
    echo '  Use -C "constraints.inp restart-file" for auxiliary inputs.' >&2
}
app_setup() {
    (( nodes == 1 )) || die 'one node per calculation is supported'
}
app_prepare() {
    input=${APP_ARGS[0]}
    [[ $input =~ ^[[:alnum:]_][[:alnum:]_.+-]*$ && -f $input ]] || die 'use a geometry filename in the current directory'
    base=${input%.*}
    chem_args=("${APP_ARGS[@]:1}")
    local arg
    for arg in "${chem_args[@]}"; do
        case $arg in
            -T|--T|--T=*|-P|--parallel|--parallel=*|-T[0-9]*|-P[0-9]*) die 'set threads with qjob -c before the geometry' ;;
        esac
    done
    jobname="$QJOB_APP:${name:-$base}"
}
app_run() {
    local result_name=$base-qjob-$(hostname -s)-$QJOB_ID
    local result_dir=$TMPDIR/$result_name f
    local -a statuses=() thread_args=()
    [[ $CHEM_PURGE_MODULES != true ]] || module purge || return 1
    module load "$CHEM_MODULE${version:+/$version}" || return 1
    command -v "$CHEM_PROGRAM" >/dev/null || return 1
    mkdir -m 700 -- "$result_dir" || return 1
    ( shopt -s dotglob nullglob
      for f in "$TMPDIR"/*; do
          [[ $f == "$result_dir" ]] || cp -r -- "$f" "$result_dir/" || exit 1
      done ) || return 1
    cp -- "$SLURM_SUBMIT_DIR/$input" "$result_dir/$input" || return 1
    cd "$result_dir" || return 1
    export OMP_NUM_THREADS=$cores OMP_THREAD_LIMIT=$cores OMP_MAX_ACTIVE_LEVELS=1
    export MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 BLIS_NUM_THREADS=1
    export OMP_STACKSIZE=1G
    ulimit -s unlimited 2>/dev/null
    if [[ $CHEM_PROGRAM == crest ]]; then thread_args=(-T "$cores"); else thread_args=(--parallel "$cores"); fi
    qjob_msg "-- $CHEM_PROGRAM: $cores threads; results: $SLURM_SUBMIT_DIR/$result_name/"
    "$CHEM_PROGRAM" "$input" "${chem_args[@]}" "${thread_args[@]}" < /dev/null 2>stderr.log | tee stdout.log
    statuses=("${PIPESTATUS[@]}")
    (( statuses[0] == 0 )) || return "${statuses[0]}"
    return "${statuses[1]}"
}
