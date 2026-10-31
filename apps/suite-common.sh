# Shared runtime for file-based chemistry applications. Functions are embedded
# into submitted jobs, so the checkout need not be mounted on compute nodes.
APP_SYNOPSIS='input [input2 ...]'
cores=4 memory=8 time_limit=24
copy_back='%b-qjob-*'
SUITE_MODULE='' SUITE_PROGRAM=''
APP_VARS='SUITE_MODULE SUITE_PROGRAM'
APP_FUNCS='suite_stage suite_execute'
app_setup() { (( nodes == 1 )) || die 'one node is supported (private node-local scratch)'; }
app_prepare() {
    [[ $input =~ ^[[:alnum:]_][[:alnum:]_.+-]*$ ]] || die 'use a simple input filename'
}
suite_usage() {
    echo '  Results: <input-base>-qjob-<jobid>/ (stdout.log, stderr.log and native files).' >&2
    echo '  Stage auxiliary files with -C; paths inside input must refer to staged files.' >&2
    echo '  -m reserves Slurm RAM; set native program memory in the input where required.' >&2
    echo '  One node; -c sets MPI ranks (Cfour: OpenMP threads).' >&2
}
app_usage() { suite_usage; }
suite_stage() {
    module purge || return 1
    module load "$SUITE_MODULE${version:+/$version}" || return 1
    command -v "$SUITE_PROGRAM" >/dev/null || { qjob_msg "executable not found: $SUITE_PROGRAM"; return 1; }
    result_dir=$TMPDIR/$base-qjob-$QJOB_ID
    mkdir -m 700 -- "$result_dir" || return 1
    ( shopt -s dotglob nullglob
      for f in "$TMPDIR"/*; do
          [[ $f == "$result_dir" ]] || cp -r -- "$f" "$result_dir/" || exit 1
      done ) || return 1
    cp -- "$SLURM_SUBMIT_DIR/$input" "$result_dir/$input" || return 1
    cd "$result_dir" || return 1
    export OMP_NUM_THREADS=1 OMP_THREAD_LIMIT=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
    export OMP_STACKSIZE=256M
    ulimit -s unlimited 2>/dev/null
    qjob_msg "-- $SUITE_MODULE${version:+/$version}; results: $SLURM_SUBMIT_DIR/${result_dir##*/}/"
}
suite_execute() {
    local -a pipe_status=()
    "$@" < /dev/null 2>stderr.log | tee stdout.log
    pipe_status=("${PIPESTATUS[@]}")
    (( pipe_status[0] == 0 )) || return "${pipe_status[0]}"
    return "${pipe_status[1]}"
}
