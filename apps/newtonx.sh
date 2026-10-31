# Newton-X: one working directory (one trajectory) per submission.
APP_INPUT=args
APP_TASKS=threads
APP_SYNOPSIS='program [arguments]  (nx_moldyn, moldyn.pl, initcond.pl, spectrum.pl, ...)'
cores=1 memory=4 time_limit=24
copy_back='%b-qjob-*'
NX_MODULE=Newton-X
NX_ROOT=''
NX_BACKEND=none
NX_ORCA_MODULE=ORCA
NX_TURBOMOLE_MODULE=TURBOMOLE
NX_OPENMOLCAS_MODULE=OpenMolcas
NX_BAGEL_MODULE=BAGEL
NX_EXTRA_MODULES=()
APP_LONG='backend:,modules:'
APP_VARS='NX_MODULE NX_ROOT NX_BACKEND NX_ORCA_MODULE NX_TURBOMOLE_MODULE NX_OPENMOLCAS_MODULE NX_BAGEL_MODULE NX_EXTRA_MODULES nx_program nx_args'
app_usage() {
    cat >&2 <<HELP
  Run from a prepared trajectory/initial-condition directory.
      --backend NAME        none|orca|turbomole|openmolcas|bagel [none]
      --modules "MOD ..."    additional electronic-structure modules
  Default: 1 process, --cores CPUs available to the electronic-structure backend.
  Match backend input (e.g. ORCA %pal nprocs) to --cores and memory to --memory.
  The complete directory is staged to local scratch; results and restart files
  return to <directory>-qjob-<jobid>/. Submission files remain available unchanged.
  Use --local for preparation utilities; global dispatch is unavailable.
HELP
}
app_option() {
    case $1 in
        --backend) NX_BACKEND=$2; APP_SHIFT=2 ;;
        --modules) read -r -a NX_EXTRA_MODULES <<< "$2"; APP_SHIFT=2 ;;
        *) return 1 ;;
    esac
}
app_setup() {
    (( nodes == 1 )) || die 'Newton-X supports one node per trajectory'
    case $NX_BACKEND in none|orca|turbomole|openmolcas|bagel) ;; *) die 'unknown --backend' ;; esac
}
app_prepare() {
    nx_program=${APP_ARGS[0]}
    nx_args=("${APP_ARGS[@]:1}")
    [[ $nx_program =~ ^[[:alnum:]_][[:alnum:]_.+-]*$ ]] || die 'use a Newton-X program name without a path'
    base=$(basename "$PWD")
    [[ $base =~ ^[[:alnum:]_][[:alnum:]_.+-]*$ ]] || die 'use a directory name with letters, digits, _, ., + or -'
    jobname="newtonx:${name:-$base-$nx_program}"
}
app_run() {
    local backend_module='' result_name result_dir status f orca_binary
    if [[ -n $NX_ROOT ]]; then
        export NX=$NX_ROOT/bin
    else
        module load "$NX_MODULE${version:+/$version}" || return 1
    fi
    [[ -d ${NX:-} ]] || { qjob_msg 'NX bin directory not found'; return 1; }
    export NXHOME=$NX CIOVERLAP=$NX/../CIOVERLAP/bin
    export PATH=$NX:$CIOVERLAP:$PATH
    case $NX_BACKEND in
        orca) backend_module=$NX_ORCA_MODULE ;;
        turbomole) backend_module=$NX_TURBOMOLE_MODULE ;;
        openmolcas) backend_module=$NX_OPENMOLCAS_MODULE ;;
        bagel) backend_module=$NX_BAGEL_MODULE ;;
    esac
    [[ -z $backend_module ]] || module load "$backend_module" || return 1
    if (( ${#NX_EXTRA_MODULES[@]} )); then module load "${NX_EXTRA_MODULES[@]}" || return 1; fi
    # NX propagates one trajectory; backend MPI is launched by the interface.
    export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
    export NX_NPROCS=$cores
    case $NX_BACKEND in
        orca)
            orca_binary=$(command -v orca) || return 1
            export ORCA=$(dirname "$orca_binary")
            ;;
        turbomole)
            export PARA_ARCH=SMP PARNODES=$cores OMP_NUM_THREADS=$cores
            [[ ! -r ${TURBODIR:-}/Config_turbo_env ]] || source "$TURBODIR/Config_turbo_env" || return 1
            ;;
        openmolcas)
            export MOLCAS_NPROCS=$cores MOLCAS_THREADS=1
            export MOLCAS_MEM=$((memory * 1024 * 80 / 100 / cores))
            ;;
    esac
    [[ -x $NX/$nx_program && ! -d $NX/$nx_program ]] || { qjob_msg "Newton-X program missing: $nx_program"; return 1; }
    ulimit -s unlimited 2>/dev/null
    if (( run_local )); then
        cd "$SLURM_SUBMIT_DIR" || return 1
        "$NX/$nx_program" "${nx_args[@]}"
        return
    fi
    result_name=$base-qjob-$QJOB_ID
    result_dir=$TMPDIR/$result_name
    [[ $TMPDIR != "$SLURM_SUBMIT_DIR" && $TMPDIR != "$SLURM_SUBMIT_DIR/"* ]] || {
        qjob_msg 'scratch must be outside the submission directory'; return 1;
    }
    mkdir -m 700 -- "$result_dir" || return 1
    # Dereference input links because relative links can point outside TRAJn.
    ( shopt -s dotglob nullglob
      for f in "$SLURM_SUBMIT_DIR"/*; do
          case $(basename "$f") in
              "$base"-qjob-*|slurm-*.out|*.sbatch) continue ;;
          esac
          cp -rL -- "$f" "$result_dir/" || exit 1
      done ) || return 1
    export TURBOTMPDIR=$TMPDIR MOLCAS_WORKDIR=$TMPDIR/molcas-work
    cd "$result_dir" || return 1
    qjob_msg "-- Newton-X $nx_program; backend=$NX_BACKEND; CPUs=$cores"
    qjob_msg "   results: $SLURM_SUBMIT_DIR/$result_name/"
    "$NX/$nx_program" "${nx_args[@]}" < /dev/null > stdout.log 2> stderr.log
    status=$?
    qjob_msg "-- Newton-X exit status $status"
    return "$status"
}
