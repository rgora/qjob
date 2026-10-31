# GROMACS mdrun: one prepared TPR per job, on one node with thread-MPI/OpenMP.
APP_SYNOPSIS="run.tpr [run2.tpr ...]"
APP_TASKS=threads
cores=4 memory=8 time_limit=24
copy_back="%b*.log %b*.edr %b*.gro %b*.trr %b*.xtc %b*.cpt %b*.xvg %b*.dat %b*.mtx"
GROMACS_MODULE=GROMACS
GROMACS_MODULE_TEMPLATE=''
GROMACS_BINARY=''
GROMACS_PURGE_MODULES=true
GROMACS_MODE=cpu
GROMACS_GPU_GRES=gpu:1
GROMACS_GPU_EXCLUSIVE=false
gromacs_checkpoint=''
gromacs_nsteps=''
APP_LONG="gpu,cpu,checkpoint:,nsteps:"
APP_VARS="GROMACS_MODULE GROMACS_MODULE_TEMPLATE GROMACS_BINARY GROMACS_PURGE_MODULES GROMACS_MODE GROMACS_GPU_GRES GROMACS_GPU_EXCLUSIVE gromacs_checkpoint gromacs_nsteps"

app_usage() {
cat >&2 <<EOF
GROMACS
      --gpu                 run short-range interactions on GPU
      --cpu                 force CPU computation (default mode: $GROMACS_MODE)
      --checkpoint FILE     continue from a checkpoint; start new output parts
                            (FILE is relative to the TPR directory, or absolute)
      --nsteps N            explicitly override the TPR step count (N >= 0)
  Input: a prepared .tpr; this command runs mdrun, not grompp.
  One node, one thread-MPI rank and --cores OpenMP threads.
  Results: <TPR-name>.* in the input directory; failed jobs retain scratch.
EOF
}

app_option() {
    case $1 in
        --gpu) GROMACS_MODE=gpu; APP_SHIFT=1 ;;
        --cpu) GROMACS_MODE=cpu; APP_SHIFT=1 ;;
        --checkpoint) gromacs_checkpoint=$2; APP_SHIFT=2 ;;
        --nsteps) gromacs_nsteps=$2; APP_SHIFT=2 ;;
        *) return 1 ;;
    esac
}

app_setup() {
    [[ $GROMACS_MODE == cpu || $GROMACS_MODE == gpu ]] || die "GROMACS_MODE must be cpu or gpu"
    (( nodes == 1 )) || die "Gromacs currently supports one node per job"
    [[ -z $gromacs_nsteps || $gromacs_nsteps =~ ^[0-9]+$ ]] || die "--nsteps must be a non-negative integer"
    if [[ $GROMACS_MODE == gpu ]] && (( ! run_local )); then
        if [[ $GROMACS_GPU_EXCLUSIVE == true ]]; then
            exclusive=1
        elif [[ -z $gres ]]; then
            [[ -n $GROMACS_GPU_GRES ]] || die "GPU jobs require a GPU GRES or GROMACS_GPU_EXCLUSIVE=true"
            gres=$GROMACS_GPU_GRES
        fi
    fi
}

app_prepare() {
    [[ $input =~ ^[[:alnum:]_][[:alnum:]_.+-]*\.tpr$ ]] \
        || die "use a .tpr filename with letters, digits, _, ., + and - (no spaces): $input"
    if [[ -n $gromacs_checkpoint ]]; then
        [[ -r $gromacs_checkpoint && -f $gromacs_checkpoint ]] || die "checkpoint is not readable: $gromacs_checkpoint"
        # Snapshot the resolved path for each input directory, including --local.
        gromacs_checkpoint=$(cd -- "$(dirname -- "$gromacs_checkpoint")" && printf '%s/%s' "$PWD" "$(basename -- "$gromacs_checkpoint")") || return 1
    fi
}

app_run() {
    local gmx_bin gmx_module
    if [[ -n $GROMACS_BINARY ]]; then
        gmx_bin=$(command -v -- "$GROMACS_BINARY") || { qjob_msg "GROMACS binary not found: $GROMACS_BINARY"; return 1; }
    else
        [[ $GROMACS_PURGE_MODULES != true ]] || module purge || return 1
        gmx_module="$GROMACS_MODULE${version:+/$version}"
        [[ -z $GROMACS_MODULE_TEMPLATE ]] || gmx_module=${GROMACS_MODULE_TEMPLATE//%v/$version}
        module load "$gmx_module" || return 1
        gmx_bin=$(command -v gmx) || { qjob_msg 'gmx not found after module load'; return 1; }
    fi
    cp -- "$SLURM_SUBMIT_DIR/$input" "$TMPDIR/$input" || return 1
    local -a args=(mdrun -s "$input" -deffnm "$base" -ntmpi 1 -ntomp "$cores" -pin off)
    if [[ $GROMACS_MODE == gpu ]]; then
        args+=(-nb gpu -pme auto -bonded auto -update auto)
    else
        args+=(-nb cpu -pme cpu -bonded cpu -update cpu)
    fi
    if [[ -n $gromacs_checkpoint ]]; then
        cp -- "$gromacs_checkpoint" "$TMPDIR/$base.cpt" || return 1
        args+=(-cpi "$base.cpt" -noappend)
    fi
    [[ -z $gromacs_nsteps ]] || args+=(-nsteps "$gromacs_nsteps")
    cd "$TMPDIR" || return 1
    export OMP_NUM_THREADS=$cores
    qjob_msg "-- GROMACS $GROMACS_MODE: one thread-MPI rank, $cores OpenMP threads"
    qjob_msg "   live simulation log: $TMPDIR/$base.log"
    "$gmx_bin" "${args[@]}" < /dev/null
}
