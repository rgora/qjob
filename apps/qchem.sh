# Q-Chem - one job per input file, input read from the submit dir (port of qtools/QChem)
#   QChem [options] input.in [input2.in ...]

APP_SYNOPSIS="input.in [input2.in ...]"
cores=16 memory=32 storage=shm:100g time_limit=72 version=7.0

QC_HOME_PATTERN=/home/rgora/PD/opt/qchem/%v   # %v = version; <dir>/qcenv.sh is sourced,
                                              # otherwise: module load qchem[/<version>]
qc_arch=smp qc_save=0 qc_memfrac=90

APP_LONG="arch:,save,mem-frac:"
APP_VARS="QC_HOME_PATTERN qc_arch qc_save qc_memfrac"

app_usage() {
cat >&2 <<EOF
Q-Chem                   (QCSCRATCH=TMPDIR)
      --arch smp|mpi       qchem -nt (OpenMP) or -np (MPI)            [$qc_arch]
      --mem-frac P         MEM_TOTAL = P% of --memory, written into every \$rem
                           of the job copy of the input               [$qc_memfrac]
      --save               qchem -save: scratch is kept in <input>.chk/;
                           an existing <input>.chk/ is used for restart (SCF_GUESS READ)
  Output: <input>.log in the input directory (old one -> .old)
EOF
}

app_option() {
    case $1 in
        --arch)     qc_arch=$2;    APP_SHIFT=2 ;;
        --save)     qc_save=1;     APP_SHIFT=1 ;;
        --mem-frac) qc_memfrac=$2; APP_SHIFT=2 ;;
        *) return 1 ;;
    esac
}

app_setup() {
    case $qc_arch in
        smp) APP_TASKS=threads ;;
        mpi) APP_TASKS=mpi ;;
        *)   die "--arch must be smp or mpi" ;;
    esac
    [[ $qc_memfrac =~ ^[0-9]+$ ]] && (( qc_memfrac <= 100 )) || die "--mem-frac must be 1-100"
}

app_prepare() {
    grep -qi '^[[:space:]]*\$rem' "$input" || warn "$input: no \$rem section"
    return 0
}

app_run() {
    local qchome=${QC_HOME_PATTERN//%v/$version} cur=$SLURM_SUBMIT_DIR rc
    if [ -f "$qchome/qcenv.sh" ]; then
        source "$qchome/qcenv.sh"
    else
        module load "qchem${version:+/$version}" || return 1
    fi
    local qc_bin=${QC:+$QC/bin/}qchem
    command -v "$qc_bin" > /dev/null || { qjob_msg "qchem not found"; return 1; }
    export QCSCRATCH=$TMPDIR

    local mb=$((memory * 1024 * qc_memfrac / 100)) np=$((nodes * cores)) par
    sed -e '/^[[:space:]]*mem_total/Id' \
        -e '/^[[:space:]]*\$rem/I a\   MEM_TOTAL '"$mb" \
        "$cur/$input" > "$TMPDIR/$input" || return 1
    if [ "$qc_arch" = mpi ]; then par=(-np "$np"); else par=(-nt "$np"); fi

    cd "$cur" || return 1
    local log=$base.log chk=$base.chk
    [ -f "$log" ] && mv -f "$log" "$base.old"
    qjob_msg "-- running $qc_bin ${par[*]} $input  (MEM_TOTAL $mb MB)"
    if (( qc_save )); then
        [ -d "$chk" ] && { qjob_msg "   restart from $chk/"; cp -r "$chk" "$QCSCRATCH/$base"; }
        "$qc_bin" -save "${par[@]}" "$TMPDIR/$input" "$log" "$base"
        rc=$?
        [ $rc -ne 0 ] && chk=$base.chk-$QJOB_ID      # keep the previous good one
        rm -rf "$chk"; cp -r "$QCSCRATCH/$base" "$chk" && qjob_msg "   scratch saved in $chk/"
    else
        "$qc_bin" "${par[@]}" "$TMPDIR/$input" "$log"
        rc=$?
    fi
    qjob_msg "-- qchem exit status $rc"
    return $rc
}
