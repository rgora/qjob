# Turbomole - one job per call, run in the current directory (port of qtools/Turbomole)
#   Turbomole [options] program [program args]
#   Turbomole -c 32 jobex -ri -c 200          options after the program name go to the program
#   Turbomole --local x2t mol.xyz > coord     preparation steps run here, without Slurm
#   Turbomole --local define

APP_SYNOPSIS="program [program arguments]   (ridft, ricc2, escf, aoforce, jobex -ri ...)"
APP_INPUT=args
cores=32 memory=128 storage=shm:200g time_limit=72

TM_MODULE=turbomole               # module load turbomole[/<version>]
tm_arch=smp tm_init=0 tm_env=0

APP_LONG="arch:,init,env"
APP_VARS="TM_MODULE tm_arch tm_init tm_prog tm_args"

app_usage() {
cat >&2 <<EOF
Turbomole                (runs in the current directory, TURBOTMPDIR=TMPDIR)
      --arch smp|mpi       parallelisation, PARA_ARCH                    [$tm_arch]
      --init               run dscf (ridft if \$rij in control) before the program
      --env                print the commands that set up the Turbomole environment
  Output: <dir>_<program>.log in the current directory (old one -> .old)
  Name of the directory + program is the job name.
EOF
}

app_option() {
    case $1 in
        --arch) tm_arch=$2; APP_SHIFT=2 ;;
        --init) tm_init=1;  APP_SHIFT=1 ;;
        --env)  tm_env=1;   APP_SHIFT=1 ;;
        *) return 1 ;;
    esac
}

app_setup() {
    case $tm_arch in
        smp) APP_TASKS=threads ;;
        mpi) APP_TASKS=mpi ;;
        *)   die "--arch must be smp or mpi" ;;
    esac
    if (( tm_env )); then
        echo "module load $TM_MODULE${version:+/$version}"
        echo "export PARA_ARCH=${tm_arch^^} PARNODES=$((nodes*cores))"
        echo 'source $TURBODIR/Config_turbo_env'
        exit 0
    fi
}

app_prepare() {
    tm_prog=${APP_ARGS[0]}
    tm_args=("${APP_ARGS[@]:1}")
    base="$(basename "$PWD")_$tm_prog"
    jobname="$QJOB_APP:${name:-$base}"
    case $tm_prog in
        x2t|t2x|define|cpc) ;;
        *) [ -f control ] || warn "no 'control' file in $PWD" ;;
    esac
    return 0
}

app_run() {
    module load "$TM_MODULE${version:+/$version}" || return 1
    [ -n "${TURBODIR:-}" ] || { qjob_msg "TURBODIR not set by module $TM_MODULE"; return 1; }
    local np=$((nodes*cores)) log=$base.log scf rc
    if (( np > 1 )); then
        export PARA_ARCH=${tm_arch^^} PARNODES=$np OMP_NUM_THREADS=$cores
        if [ "$tm_arch" = mpi ] && [ -n "${SLURM_JOB_NODELIST:-}" ]; then
            export HOSTS_FILE=$TMPDIR/hosts
            scontrol show hostnames "$SLURM_JOB_NODELIST" \
                | awk -v n="$cores" '{for(i=0;i<n;i++) print}' > "$HOSTS_FILE"
        fi
    fi
    [ -f "$TURBODIR/Config_turbo_env" ] && source "$TURBODIR/Config_turbo_env"
    export TURBOTMPDIR=$TMPDIR
    ulimit -s unlimited 2>/dev/null
    cd "$SLURM_SUBMIT_DIR" || return 1

    if (( run_local )); then                 # interactive: define, x2t > coord, ...
        "$tm_prog" "${tm_args[@]}"; return
    fi

    [ -f "$log" ] && mv -f "$log" "$base.old"
    if (( tm_init )); then
        scf=dscf; grep -q '^\$rij' control 2>/dev/null && scf=ridft
        qjob_msg "-- initial $scf"
        "$scf" > "${base}_$scf.log" 2>&1 || { qjob_msg "$scf failed"; return 1; }
    fi
    qjob_msg "-- running $tm_prog ${tm_args[*]}  (PARA_ARCH=${PARA_ARCH:-serial} PARNODES=${PARNODES:-1})"
    "$tm_prog" "${tm_args[@]}" > "$log" 2>&1
    rc=$?
    [ $rc -eq 0 ] && rm -f CC*            # ricc2 scratch left in the working dir
    qjob_msg "-- $tm_prog exit status $rc"
    return $rc
}
