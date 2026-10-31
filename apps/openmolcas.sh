# OpenMolcas uses pymolcas to launch its own MPI executables.
APP_SYNOPSIS='input.inp [input2.input ...]'
APP_TASKS=mpi
cores=4 memory=8 time_limit=24
copy_back='%b-qjob-*'
OPENMOLCAS_MODULE=OpenMolcas
OPENMOLCAS_BINARY=''
OPENMOLCAS_MODE=mpi
OPENMOLCAS_PURGE_MODULES=true
OPENMOLCAS_EXTRA_MODULES=()
APP_LONG='mpi,openmp'
APP_VARS='OPENMOLCAS_MODULE OPENMOLCAS_BINARY OPENMOLCAS_MODE OPENMOLCAS_PURGE_MODULES OPENMOLCAS_EXTRA_MODULES'
app_usage() {
cat >&2 <<EOF
OpenMolcas
      --mpi                 --cores MPI processes, one thread each (default)
      --openmp              one process with --cores threads
  One node. Input: .inp or .input. Use -C 'geometry.xyz restart.JobIph'
  for auxiliary files; reference these with relative paths in the input.
  Results: <input-base>-qjob-<host>-<jobid>/, including stdout.log/stderr.log.
  MOLCAS_MEM uses 80% of requested memory divided by the number of processes.
  WorkDir is local scratch. Native exports, restart files and HDF5 results are copied back; on failure
  the complete scratch directory is retained. User molcasrc files are ignored.
EOF
}
app_option() {
    case $1 in
        --mpi) OPENMOLCAS_MODE=mpi; APP_SHIFT=1 ;;
        --openmp) OPENMOLCAS_MODE=openmp; APP_SHIFT=1 ;;
        *) return 1 ;;
    esac
}
app_setup() {
    (( nodes == 1 )) || die 'OpenMolcas supports one node per job'
    case $OPENMOLCAS_MODE in
        mpi) APP_TASKS=mpi ;;
        openmp) APP_TASKS=threads ;;
        *) die 'OPENMOLCAS_MODE must be mpi or openmp' ;;
    esac
    local processes=1
    [[ $OPENMOLCAS_MODE != mpi ]] || processes=$cores
    (( memory * 1024 * 80 / 100 / processes >= 128 )) || die 'request at least 160 MiB per process'
}
app_prepare() {
    [[ $input =~ ^[[:alnum:]_][[:alnum:]_.+-]*\.(inp|input)$ ]] \
        || die 'use an .inp or .input filename with letters, digits, _, ., + and -'
}
app_run() {
    local driver mod result_name result_dir work_dir f processes=1 threads=1
    local copy_status=0
    local -a pipe_status=() command_line=()
    if [[ -n $OPENMOLCAS_BINARY ]]; then
        driver=$(command -v -- "$OPENMOLCAS_BINARY") || { qjob_msg 'pymolcas driver not found'; return 1; }
    else
        [[ $OPENMOLCAS_PURGE_MODULES != true ]] || module purge || return 1
        mod="$OPENMOLCAS_MODULE${version:+/$version}"
        module load "$mod" || return 1
        if (( ${#OPENMOLCAS_EXTRA_MODULES[@]} )); then
            module load "${OPENMOLCAS_EXTRA_MODULES[@]}" || return 1
        fi
        driver=${MOLCAS_DRIVER:-$(command -v pymolcas)} || { qjob_msg 'pymolcas not found after module load'; return 1; }
    fi
    if [[ -x $driver ]]; then
        command_line=("$driver")
    elif [[ -r $driver ]]; then
        command_line=(python3 "$driver")
    else
        qjob_msg "pymolcas is not readable: $driver"; return 1
    fi
    result_name=$base-qjob-$(hostname -s)-$QJOB_ID
    result_dir=$TMPDIR/$result_name
    work_dir=$TMPDIR/molcas-work
    mkdir -m 700 -- "$result_dir" || return 1
    ( shopt -s dotglob nullglob
      for f in "$TMPDIR"/*; do
          [[ $f == "$result_dir" ]] || cp -r -- "$f" "$result_dir/" || exit 1
      done ) || return 1
    mkdir -m 700 -- "$work_dir" || return 1
    cp -- "$SLURM_SUBMIT_DIR/$input" "$result_dir/$input" || return 1
    cd "$result_dir" || return 1
    if [[ $OPENMOLCAS_MODE == mpi ]]; then processes=$cores; else threads=$cores; fi
    export MOLCAS_NPROCS=$processes MOLCAS_THREADS=$threads
    export OMP_NUM_THREADS=$threads OMP_THREAD_LIMIT=$threads
    export OPENBLAS_NUM_THREADS=$threads MKL_NUM_THREADS=$threads BLIS_NUM_THREADS=$threads
    export MOLCAS_MEM=$((memory * 1024 * 80 / 100 / processes))
    export MOLCAS_MAXMEM=$MOLCAS_MEM
    export Project=$base WorkDir=$work_dir CurrDir=$result_dir MOLCAS_OUTPUT=$result_dir
    export MOLCAS_KEEP_WORKDIR=YES MOLCAS_COLOR=NO
    qjob_msg "-- OpenMolcas: $processes MPI process(es), $threads thread(s), MOLCAS_MEM=$MOLCAS_MEM MiB/process"
    qjob_msg "   live output: $result_dir/stdout.log"
    qjob_msg "   results: $SLURM_SUBMIT_DIR/$result_name/"
    "${command_line[@]}" -ign "$input" < /dev/null 2>stderr.log | tee stdout.log
    pipe_status=("${PIPESTATUS[@]}")
    # The native exports omit files required for later restart and RASSI runs.
    ( shopt -s nullglob
      for f in "$work_dir/$base".{JobIph,JobMix,RunFile,ChVec} "$work_dir/$base"*.h5; do
          [[ -f $f ]] || continue
          cp -p -- "$f" "$result_dir/" || exit 1
      done ) || copy_status=$?
    [[ ${pipe_status[0]} != 0 ]] && return "${pipe_status[0]}"
    (( copy_status == 0 )) || return 1
    return "${pipe_status[1]}"
}
