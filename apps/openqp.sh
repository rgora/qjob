# OpenQP: one input per job, private scratch, separate results per run.
APP_SYNOPSIS="input.inp|input.oqp [input2 ...]"
APP_TASKS=threads
cores=4 memory=8 time_limit=24
copy='%b.xyz %b.json'
copy_back='%b-qjob-*'
OPENQP_MODULE=OpenQP
OPENQP_MODULE_TEMPLATE=''
OPENQP_BINARY=''
OPENQP_PURGE_MODULES=true
OPENQP_BIND_ALLOCATION=false
OPENQP_MODE=openmp
OPENQP_MPI_AVAILABLE=true
APP_LONG='mpi,openmp'
APP_VARS='OPENQP_MODULE OPENQP_MODULE_TEMPLATE OPENQP_BINARY OPENQP_PURGE_MODULES OPENQP_BIND_ALLOCATION OPENQP_MODE OPENQP_MPI_AVAILABLE'

app_usage() {
cat >&2 <<EOF
OpenQP
      --openmp              one process, --cores OpenMP threads (default)
      --mpi                 --cores MPI ranks, one OpenMP thread per rank
  One node; .inp and canonical .oqp inputs are supported.
  Input is copied unchanged. --cores sets --omp and the OpenMP thread limit.
  Results: <input-name>-qjob-<jobid>/, including the native log and stdout.log.
  Same-name .xyz/.json files are staged by default; use -C for other inputs.
  -B overrides the default results-directory copy-back pattern.
EOF
    [[ $OPENQP_MPI_AVAILABLE == true ]] || printf '%s\n' '  This installed build supports OpenMP only; --mpi is unavailable.' >&2
}

app_option() {
    case $1 in
        --mpi) OPENQP_MODE=mpi; APP_SHIFT=1 ;;
        --openmp) OPENQP_MODE=openmp; APP_SHIFT=1 ;;
        *) return 1 ;;
    esac
}

app_setup() {
    (( nodes == 1 )) || die 'Openqp supports one node per job'
    case $OPENQP_MODE in
        openmp) APP_TASKS=threads ;;
        mpi)
            [[ $OPENQP_MPI_AVAILABLE == true ]] || die 'this OpenQP installation does not support MPI; use --openmp'
            APP_TASKS=mpi ;;
        *) die 'OPENQP_MODE must be openmp or mpi' ;;
    esac
}

app_prepare() {
    [[ $input =~ ^[[:alnum:]_][[:alnum:]_.+-]*\.(inp|oqp)$ ]] \
        || die 'use an .inp or .oqp filename with letters, digits, _, ., + and -'
}

app_run() {
    local oqp_bin oqp_module threads result_name result_dir f cgroup cpus
    local -a launcher=() command_line=() pipe_status=()
    if [[ -n $OPENQP_BINARY ]]; then
        oqp_bin=$(command -v -- "$OPENQP_BINARY") || { qjob_msg "OpenQP binary not found: $OPENQP_BINARY"; return 1; }
    else
        [[ $OPENQP_PURGE_MODULES != true ]] || module purge || return 1
        oqp_module="$OPENQP_MODULE${version:+/$version}"
        [[ -z $OPENQP_MODULE_TEMPLATE ]] || oqp_module=${OPENQP_MODULE_TEMPLATE//%v/$version}
        module load "$oqp_module" || return 1
        oqp_bin=$(command -v openqp) || { qjob_msg 'openqp not found after module load'; return 1; }
    fi
    if [[ $OPENQP_BIND_ALLOCATION == true ]] && (( ! run_local )); then
        cgroup=$(awk -F: '$1 == "0" {print $3}' /proc/self/cgroup)
        [[ -n $cgroup && -r /sys/fs/cgroup$cgroup/cpuset.cpus.effective ]] \
            || { qjob_msg 'cannot read the job cgroup v2 CPU allocation'; return 1; }
        cpus=$(cat "/sys/fs/cgroup$cgroup/cpuset.cpus.effective")
        [[ $cpus =~ ^[0-9,-]+$ ]] || return 1
        launcher=(taskset -c "$cpus")
        qjob_msg "   OpenQP allocation CPUs: $cpus"
    fi
    result_name=$base-qjob-$QJOB_ID
    result_dir=$TMPDIR/$result_name
    mkdir -m 700 -- "$result_dir" || return 1
    # Auxiliary -C inputs are staged by qjob in TMPDIR before app_run.
    ( shopt -s dotglob nullglob
      for f in "$TMPDIR"/*; do
          [[ $f == "$result_dir" ]] || cp -r -- "$f" "$result_dir/" || exit 1
      done ) || return 1
    cp -- "$SLURM_SUBMIT_DIR/$input" "$result_dir/$input" || return 1
    cd "$result_dir" || return 1
    threads=$cores
    if [[ $OPENQP_MODE == mpi ]]; then
        threads=1
        command -v mpirun >/dev/null || { qjob_msg 'mpirun not found'; return 1; }
        command_line=(mpirun --bind-to none -np "$cores" "$oqp_bin" --omp "$threads" "$input")
    else
        command_line=("$oqp_bin" --nompi --omp "$threads" "$input")
    fi
    # The thread limit also caps explicit omp_threads settings inside inputs.
    export OMP_NUM_THREADS=$threads OMP_THREAD_LIMIT=$threads
    export OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
    qjob_msg "-- OpenQP $OPENQP_MODE: $cores allocated cores, $threads thread(s) per process"
    qjob_msg "   live output: $result_dir/stdout.log"
    qjob_msg "   results: $SLURM_SUBMIT_DIR/$result_name/"
    "${launcher[@]}" "${command_line[@]}" < /dev/null 2>stderr.log | tee stdout.log
    pipe_status=("${PIPESTATUS[@]}")
    [[ ${pipe_status[0]} != 0 ]] && return "${pipe_status[0]}"
    return "${pipe_status[1]}"
}
