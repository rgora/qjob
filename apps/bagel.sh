# BAGEL: one node, isolated results, MPI or shared-memory threads.
APP_SYNOPSIS='input.json [input2.json ...]'
APP_TASKS=mpi
cores=4 memory=8 time_limit=24
copy_back='%b-qjob-*'
BAGEL_MODULE=BAGEL
BAGEL_MODULE_TEMPLATE=''
BAGEL_BINARY=''
BAGEL_PURGE_MODULES=true
BAGEL_MODE=mpi
BAGEL_MPI_ARGS=()
APP_LONG='mpi,openmp'
APP_VARS='BAGEL_MODULE BAGEL_MODULE_TEMPLATE BAGEL_BINARY BAGEL_PURGE_MODULES BAGEL_MODE BAGEL_MPI_ARGS'

app_usage() {
cat >&2 <<EOF
BAGEL
      --mpi                 --cores MPI processes, one thread each (default)
      --openmp              one process, --cores BAGEL/BLAS threads
  One node; input is a BAGEL .json file, copied unchanged.
  Results: <input-name>-qjob-<host>-<jobid>/, including stdout.log and stderr.log.
  Use -C 'geometry.xyz restart.archive' to stage auxiliary input files.
  Relative paths in JSON must refer to files staged with -C.
EOF
}
app_option() {
    case $1 in
        --mpi) BAGEL_MODE=mpi; APP_SHIFT=1 ;;
        --openmp) BAGEL_MODE=openmp; APP_SHIFT=1 ;;
        *) return 1 ;;
    esac
}
app_setup() {
    (( nodes == 1 )) || die 'Bagel supports one node per job'
    case $BAGEL_MODE in
        mpi) APP_TASKS=mpi ;;
        openmp) APP_TASKS=threads ;;
        *) die 'BAGEL_MODE must be mpi or openmp' ;;
    esac
}
app_prepare() {
    [[ $input =~ ^[[:alnum:]_][[:alnum:]_.+-]*\.json$ ]] \
        || die 'use a .json filename with letters, digits, _, ., + and -'
}
app_run() {
    local bagel_bin bagel_module threads result_name result_dir f
    local -a command_line=() pipe_status=()
    if [[ -n $BAGEL_BINARY ]]; then
        bagel_bin=$(command -v -- "$BAGEL_BINARY") || { qjob_msg "BAGEL binary not found: $BAGEL_BINARY"; return 1; }
    else
        [[ $BAGEL_PURGE_MODULES != true ]] || module purge || return 1
        bagel_module="$BAGEL_MODULE${version:+/$version}"
        [[ -z $BAGEL_MODULE_TEMPLATE ]] || bagel_module=${BAGEL_MODULE_TEMPLATE//%v/$version}
        module load "$bagel_module" || return 1
        bagel_bin=$(command -v BAGEL) || { qjob_msg 'BAGEL not found after module load'; return 1; }
    fi
    result_name=$base-qjob-$(hostname -s)-$QJOB_ID
    result_dir=$TMPDIR/$result_name
    mkdir -m 700 -- "$result_dir" || return 1
    ( shopt -s dotglob nullglob
      for f in "$TMPDIR"/*; do
          [[ $f == "$result_dir" ]] || cp -r -- "$f" "$result_dir/" || exit 1
      done ) || return 1
    cp -- "$SLURM_SUBMIT_DIR/$input" "$result_dir/$input" || return 1
    cd "$result_dir" || return 1
    command -v mpirun >/dev/null || { qjob_msg 'mpirun not found'; return 1; }
    threads=$cores
    if [[ $BAGEL_MODE == mpi ]]; then
        threads=1
        command_line=(mpirun "${BAGEL_MPI_ARGS[@]}" --bind-to core -np "$cores" "$bagel_bin" "$input")
    else
        command_line=(mpirun "${BAGEL_MPI_ARGS[@]}" --bind-to none -np 1 "$bagel_bin" "$input")
    fi
    export BAGEL_NUM_THREADS=$threads OMP_NUM_THREADS=$threads OMP_THREAD_LIMIT=$threads
    export OPENBLAS_NUM_THREADS=$threads MKL_NUM_THREADS=$threads BLIS_NUM_THREADS=$threads
    qjob_msg "-- BAGEL $BAGEL_MODE: $cores allocated cores, $threads thread(s) per process"
    qjob_msg "   live output: $result_dir/stdout.log"
    qjob_msg "   results: $SLURM_SUBMIT_DIR/$result_name/"
    "${command_line[@]}" < /dev/null 2>stderr.log | tee stdout.log
    pipe_status=("${PIPESTATUS[@]}")
    [[ ${pipe_status[0]} != 0 ]] && return "${pipe_status[0]}"
    return "${pipe_status[1]}"
}
