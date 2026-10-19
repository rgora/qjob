# =============================================================================
# qjob runtime - executed inside the job (appended to every job script)
# all messages go to stderr (slurm-<jobid>.out; terminal with --local)
# =============================================================================
qjob_msg() { printf '%s\n' "$*" >&2; }

qjob_copy() {          # qjob_copy FROM TO "patterns"   (globs expand in FROM)
    local from=$1 to=$2 pats=$3
    [ -n "$pats" ] || return 0
    ( cd "$from" || exit 1
      shopt -s nullglob
      local rc=0 f
      for f in $pats; do
          [ -e "$f" ] || continue
          if cp -r -- "$f" "$to/"; then qjob_msg "    $f"; else rc=1; fi
      done
      return "$rc" )
}

qjob_main() {
    if [ -n "$QJOB_MODULE_INIT" ]; then
        [ -r "$QJOB_MODULE_INIT" ] && source "$QJOB_MODULE_INIT" \
            || { qjob_msg "cannot initialize modules: $QJOB_MODULE_INIT"; exit 1; }
    elif ! type module >/dev/null 2>&1; then
        if [ -r /usr/local/sbin/modules.sh ]; then
            source /usr/local/sbin/modules.sh
        elif [ -r /etc/profile.d/lmod.sh ]; then
            source /etc/profile.d/lmod.sh
        fi
    fi
    if [ -n "$QJOB_MODULEPATH" ]; then
        module use "$QJOB_MODULEPATH" || exit 1
    fi
    local scratch_owned=0
    if (( run_local )); then
        QJOB_ID=local-$$
        export SLURM_SUBMIT_DIR=$PWD
    else
        QJOB_ID=$SLURM_JOB_ID
    fi
    if [ -n "$QJOB_SCRATCH_ROOT" ]; then
        TMPDIR=$(mktemp -d "$QJOB_SCRATCH_ROOT/qjob-$(id -u).$QJOB_ID.XXXXXX") || exit 1
        scratch_owned=1
        export TMPDIR
    elif (( run_local )); then
        TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/qjob.XXXXXX") || exit 1
        scratch_owned=1
        export TMPDIR
    else
        if [ -z "${TMPDIR:-}" ] || [ ! -d "$TMPDIR" ]; then
            TMPDIR=$(mktemp -d "/tmp/qjob.$SLURM_JOB_ID.XXXX") || exit 1
            scratch_owned=1
            export TMPDIR
        fi
    fi
    local t0=$SECONDS status pid dt
    qjob_msg "== $jobname   id $QJOB_ID   $(date)"
    qjob_msg "   host      $(hostname -s)   nodes: ${SLURM_JOB_NODELIST:-local}"
    qjob_msg "   resources $nodes node(s) x $cores cores, $memory GB"
    qjob_msg "   workdir   $SLURM_SUBMIT_DIR"
    qjob_msg "   TMPDIR    $TMPDIR"
    cd "$SLURM_SUBMIT_DIR" || exit 1

    if [ -n "$copy" ]; then
        qjob_msg "-- copy to TMPDIR"
        qjob_copy "$SLURM_SUBMIT_DIR" "$TMPDIR" "$copy" || exit 1
    fi

    if (( run_local )); then
        app_run; status=$?
    else
        # USR1 arrives signal_lead s before the time limit: save what is there
        trap 'qjob_msg "!! time limit approaching: copying results back"
              qjob_copy "$TMPDIR" "$SLURM_SUBMIT_DIR" "$copy_back"' USR1
        app_run & pid=$!
        wait "$pid"; status=$?
        while kill -0 "$pid" 2>/dev/null; do wait "$pid"; status=$?; done
        trap - USR1
    fi

    cd "$SLURM_SUBMIT_DIR"
    if [ -n "$copy_back" ]; then
        qjob_msg "-- copy back from TMPDIR"
        qjob_copy "$TMPDIR" "$SLURM_SUBMIT_DIR" "$copy_back" || status=1
    fi
    if [ "$clean_tmp" = always ] || { [ "$clean_tmp" = success ] && [ "$status" -eq 0 ]; }; then
        qjob_msg "-- cleaning TMPDIR"
        if (( scratch_owned )); then
            rm -rf -- "${TMPDIR:?}" || status=1
        else
            find "${TMPDIR:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + || status=1
        fi
    else
        qjob_msg "   TMPDIR contents retained at $TMPDIR"
    fi
    dt=$((SECONDS - t0))
    qjob_msg "== exit status $status   elapsed $(printf '%02d:%02d:%02d' $((dt/3600)) $((dt%3600/60)) $((dt%60)))   $(date)"
    exit "$status"
}

qjob_main
