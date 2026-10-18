# Psi4 1.11 + OEPDev (EOP-TI) - one job per input, run in the input directory
#   Psi4oep [options] script.py [script2.py ...]        psiapi scripts (may 'import oepdev')
#   Psi4oep [options] input.in                          Psithon input -> input.out
#   Psi4oep -v 1.11-dev -c 16 -m 64 run_7ac.py --args "--methods cis,tda-hf --dimer"
#   Psi4oep --args "7ac 2.6,3.6,4.6" ref_scan.py
#   Psi4oep --local c2h4_ss_rigid.py                    inside an interactive allocation
#
# Threads and memory are locked to the allocation by libexec/psi4-oepdev-run
# (set_num_threads()/set_memory() in the input are ignored; PSI4OEP_HONOR_INPUT=1 to honour them).

APP_SYNOPSIS="input.py|input.in [input2 ...]"
APP_TASKS=threads
cores=8 memory=32 time_limit=24 storage=shm:40g version=1.11

PSI4_ENV_PATTERN='$HOME/PD/opt/psi4/psi4-oepdev-%v.sh'     # %v = version (1.11, 1.11-dev)
PSI4_ENV_SHARED=/home/rgora/PD/opt/psi4/psi4-oepdev-%v.sh  # fallback: shared installation
psi4_env="" psi4_args="" psi4_memfrac=90

APP_LONG="env:,args:,mem-frac:"
APP_VARS="QJOB_ROOT psi4_env psi4_args psi4_memfrac"

app_usage() {
cat >&2 <<EOF
Psi4 + OEPDev            (runs in the input directory, PSI_SCRATCH=TMPDIR)
  -v, --version VER        environment ${PSI4_ENV_PATTERN//%v/<VER>}
                           e.g. 1.11 (stable), 1.11-dev (dev/tdscf-tda)   [$version]
      --env FILE           environment file to source instead of -v
      --args "ARGS"        arguments for a *.py script; %c = cores,
                           %M = psi4 memory in GB, e.g. --args "--threads %c --memory %Mgb"
      --mem-frac P         psi4 memory = P% of --memory                    [$psi4_memfrac]
  Threads = cores (OpenMP + threaded BLAS), memory locked to the allocation.
  Output: <input>-<jobid>.log (stdout of the run); Psithon also writes <input>.out
EOF
}

app_option() {
    case $1 in
        --env)      psi4_env=$2;     APP_SHIFT=2 ;;
        --args)     psi4_args=$2;    APP_SHIFT=2 ;;
        --mem-frac) psi4_memfrac=$2; APP_SHIFT=2 ;;
        *) return 1 ;;
    esac
}

app_setup() {
    [[ $psi4_memfrac =~ ^[0-9]+$ ]] && (( psi4_memfrac <= 100 )) || die "--mem-frac must be 1-100"
    if [ -z "$psi4_env" ]; then
        psi4_env=$(eval echo "${PSI4_ENV_PATTERN//%v/$version}")
        [ -f "$psi4_env" ] || psi4_env=${PSI4_ENV_SHARED//%v/$version}
    fi
    [ -f "$psi4_env" ] || [ -n "${QJOB_NO_ENV_CHECK:-}" ] || die "environment file not found: $psi4_env"
    psi4_args=${psi4_args//%c/$cores}
    psi4_args=${psi4_args//%M/$((memory * psi4_memfrac / 100))}
}

app_prepare() {
    [ -f ~/.psi4rc ] && warn "found ~/.psi4rc - it may affect the calculations"
    if [ -n "$psi4_args" ] && [[ $input != *.py ]]; then
        warn "$input: --args is used only for *.py scripts"
    fi
    return 0
}

app_run() {
    export PSI4_OEPDEV_ENV=$psi4_env
    local mem=$((memory * 1024 * 1024 * 1024 / 100 * psi4_memfrac))
    local log=$SLURM_SUBMIT_DIR/$base-$QJOB_ID.log rc
    cd "$SLURM_SUBMIT_DIR" || return 1
    qjob_msg "-- environment $psi4_env"
    qjob_msg "-- running $input $psi4_args   (threads $cores, memory $((mem / 1048576)) MiB)"
    PSI4OEP_SCRIPT_ARGS=$psi4_args "$QJOB_ROOT/libexec/psi4-oepdev-run" "$input" "$cores" "$mem" > "$log"
    rc=$?
    qjob_msg "-- exit status $rc (stdout in $(basename "$log"))"
    return $rc
}
