# ORCA - one job per input file, run in TMPDIR
#   Orca [options] input.inp [input2.inp ...]

APP_SYNOPSIS="input.inp [input2.inp ...]"
APP_TASKS=mpi
cores=32 memory=200 storage=shm:400g time_limit=72
copy_back="%b.gbw *.hess %b.cis %b.*.nto %b.densities %b.densitiesinfo *.txt *spectrum* *.xyz"

ORCA_MODULE=ORCA                  # module load ORCA[/<version>]
ORCA_COPY_EXT="gbw xyz hess oin mp2nat loc"   # copied from the input dir to TMPDIR
orca_pal=sync

APP_LONG="pal:"
APP_VARS="ORCA_MODULE ORCA_COPY_EXT orca_pal"
APP_FUNCS="orca_set_pal"

app_usage() {
cat >&2 <<EOF
ORCA
      --pal sync|keep      sync: in the job copy of the input set %pal nprocs to
                           nodes*cores (added if missing, PALn keywords removed) [$orca_pal]
  Files *.{${ORCA_COPY_EXT// /,}} from the input directory are copied to TMPDIR.
  Output: <input>-<jobid>.log in the input directory (stderr: <input>-<jobid>.err).
EOF
}

app_option() {
    case $1 in
        --pal) orca_pal=$2; APP_SHIFT=2 ;;
        *) return 1 ;;
    esac
}

app_setup() {
    [[ $orca_pal =~ ^(sync|keep)$ ]] || die "--pal must be sync or keep"
}

app_prepare() {
    local np=$((nodes*cores)) mc n
    mc=$(grep -iE '^[[:space:]]*%maxcore[[:space:]]+[0-9]+' "$input" | grep -oE '[0-9]+' | tail -1)
    if [ -z "$mc" ]; then
        warn "$input: no %maxcore (ORCA default per process will be used)"
    elif (( mc * cores > memory * 1024 * 9 / 10 )); then
        warn "$input: %maxcore $mc x $cores procs = $((mc*cores)) MB > 90% of --memory ${memory} GB"
    fi
    if [ "$orca_pal" = keep ]; then
        n=$(grep -ioE '^[[:space:]]*(%pal[[:space:]]+)?nprocs[[:space:]]+[0-9]+' "$input" | grep -oE '[0-9]+$' | head -1)
        [ -n "$n" ] && [ "$n" != "$np" ] && warn "$input: nprocs $n in input, but $np cores requested"
    fi
    return 0
}

orca_set_pal() {       # orca_set_pal FILE NPROCS  (edits the TMPDIR copy only)
    local f=$1 np=$2
    sed -i -E \
        -e "s/^([[:space:]]*%pal[[:space:]]+nprocs[[:space:]]+)[0-9]+/\1$np/I" \
        -e "s/^([[:space:]]*nprocs[[:space:]]+)[0-9]+/\1$np/I" \
        -e "/^[[:space:]]*!/s/(!|[[:space:]])PAL[0-9]+\b/\1/Ig" "$f"
    grep -qiE '^[[:space:]]*(%pal[[:space:]]+)?nprocs[[:space:]]' "$f" || sed -i "1i %pal nprocs $np end" "$f"
}

app_run() {
    module load "$ORCA_MODULE${version:+/$version}" || return 1
    local orca_bin cur=$SLURM_SUBMIT_DIR ext f rc
    orca_bin=$(command -v orca) || { qjob_msg "orca not found after module load"; return 1; }

    cp "$cur/$input" "$TMPDIR/" || return 1
    ( cd "$cur" && shopt -s nullglob
      for ext in $ORCA_COPY_EXT; do for f in *."$ext"; do cp -- "$f" "$TMPDIR/"; done; done )
    cd "$TMPDIR" || return 1
    [ "$orca_pal" = sync ] && orca_set_pal "$input" $((nodes*cores))

    # full log in TMPDIR (no quota) and the usual log in the submit dir;
    # if /home or /lustre hits its quota, tee keeps writing the TMPDIR copy.
    # stderr goes straight to a file (a pipe to sed hung NEB jobs).
    local log=$cur/$base-$QJOB_ID.log logtmp=$TMPDIR/$base-$QJOB_ID.log err=$TMPDIR/$base-$QJOB_ID.err
    qjob_msg "-- running $orca_bin $input"
    "$orca_bin" "$input" < /dev/null 2> "$err" | tee --output-error=warn "$logtmp" > "$log"
    rc=${PIPESTATUS[0]}

    cmp -s "$logtmp" "$log" || cp "$logtmp" "$log" \
        || qjob_msg "WARNING: could not copy the full log to $log (quota?); it stays in TMPDIR"
    if [ -s "$err" ]; then sed 's/^/    /' "$err" >&2; cp "$err" "$cur/"; fi
    qjob_msg "-- orca exit status $rc"
    ls -ltrh >&2
    return "$rc"
}
