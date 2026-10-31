# Shared-memory Gaussian; the original input is never changed.
APP_SYNOPSIS='input.com|input.gjf|input.inp [input2 ...]'
APP_TASKS=threads
cores=4 memory=8 time_limit=24
copy_back='%b-qjob-*'
GAUSSIAN_ROOT=/opt/gaussian
GAUSSIAN_MODULE=''
GAUSSIAN_MODULE_VERSION=''
GAUSSIAN_SERIES=g16
APP_VARS='GAUSSIAN_ROOT GAUSSIAN_MODULE GAUSSIAN_MODULE_VERSION GAUSSIAN_SERIES'
app_usage() {
    echo '  One node, shared memory. -c: cores; -m: TOTAL Slurm memory in GB.' >&2
    echo '  Working input: %NProcShared=-c, %Mem=80% of -m (every Link1 section).' >&2
    echo '  Default: G16; -v g09 or -v g03 selects an existing legacy installation.' >&2
    echo '  Module sites also accept -v 16.C.02 (or the installed module version).' >&2
    echo '  Results: <base>-qjob-<host>-<id>/, including .log, .chk and working input.' >&2
    echo '  Checkpoint paths must be relative; stage restart files with -C.' >&2
    echo '  %RWF is managed by qjob; failed calculations retain scratch.' >&2
}
app_setup() {
    (( nodes == 1 )) || die 'Gaussian supports one node per job (no Linda)'
    case $version in
        ''|g16) GAUSSIAN_SERIES=g16 ;;
        g09|g03) GAUSSIAN_SERIES=$version ;;
        [0-9]*.[A-Za-z].[0-9]*)
            [[ -n $GAUSSIAN_MODULE ]] || die 'revision selection requires a Gaussian module'
            GAUSSIAN_MODULE_VERSION=$version; GAUSSIAN_SERIES=g16 ;;
        *) die 'use -v g16, g09, g03 or a configured G16 module revision' ;;
    esac
    [[ $GAUSSIAN_SERIES == g16 || -z $GAUSSIAN_MODULE ]] || die 'legacy versions require a local installation'
}
app_prepare() {
    [[ $input =~ ^[[:alnum:]_][[:alnum:]_.+-]*\.(com|gjf|inp)$ ]] || die 'use a .com, .gjf or .inp filename without spaces'
}
app_run() {
    local driver profile f allowed result_name result_dir scratch_dir
    local -a statuses=()
    if [[ -n $GAUSSIAN_MODULE ]]; then
        module purge || return 1
        module load "$GAUSSIAN_MODULE${GAUSSIAN_MODULE_VERSION:+/$GAUSSIAN_MODULE_VERSION}" || return 1
        driver=$(command -v "$GAUSSIAN_SERIES") || return 1
        # Some site modulefiles contain a stray quote in GAUSS_BSDDIR.
        export GAUSS_BSDDIR="$(dirname -- "$driver")/bsd"
    else
        profile=$GAUSSIAN_ROOT/$GAUSSIAN_SERIES/bsd/$GAUSSIAN_SERIES.profile
        [[ -r $profile ]] || { qjob_msg "Gaussian profile not found: $profile"; return 1; }
        export "${GAUSSIAN_SERIES}root=$GAUSSIAN_ROOT"
        # Old Gaussian profiles locate gau-machine through PATH.
        export PATH="$GAUSSIAN_ROOT/$GAUSSIAN_SERIES/bsd:$GAUSSIAN_ROOT/$GAUSSIAN_SERIES:$PATH"
        source "$profile" || return 1
        driver=$GAUSSIAN_ROOT/$GAUSSIAN_SERIES/$GAUSSIAN_SERIES
    fi
    [[ -x $driver ]] || { qjob_msg "Gaussian executable not found: $driver"; return 1; }
    result_name=$base-qjob-$(hostname -s)-$QJOB_ID
    result_dir=$TMPDIR/$result_name
    scratch_dir=$TMPDIR/gaussian-scratch
    mkdir -m 700 -- "$result_dir" || return 1
    ( shopt -s dotglob nullglob
      for f in "$TMPDIR"/*; do
          [[ $f == "$result_dir" ]] || cp -r -- "$f" "$result_dir/" || exit 1
      done ) || return 1
    mkdir -m 700 -- "$scratch_dir" || return 1
    cp -- "$SLURM_SUBMIT_DIR/$input" "$result_dir/original.input" || return 1
    cd "$result_dir" || return 1
    python3 - "$input" "$base" "$cores" "$memory" "$GAUSSIAN_SERIES" <<'PY'
import pathlib, re, sys
output, base, cores, memory, series = sys.argv[1:]
text = pathlib.Path('original.input').read_text()
parts = re.split(r'(?im)^\s*--link1--\s*$', text)
new = []
for i, part in enumerate(parts):
    kept, has_chk = [], False
    for line in part.lstrip('\n').splitlines():
        match = re.match(r'\s*%\s*([a-z0-9]+)\s*(?:=\s*(.*))?$', line, re.I)
        if match:
            key, value = match.group(1).lower(), (match.group(2) or '').strip()
            if key in {'mem', 'nproc', 'nprocshared', 'cpu', 'lindaworkers', 'nproclinda', 'rwf'}:
                continue
            if key in {'chk', 'oldchk', 'int', 'd2e'}:
                path = pathlib.PurePosixPath(value)
                if not value or path.is_absolute() or '..' in path.parts or '\\' in value:
                    sys.exit('Use relative Gaussian file paths and -C for restart files: ' + line)
                if key == 'chk':
                    has_chk = True
        kept.append(line)
    resource = '%nproc' if series == 'g03' else '%nprocshared'
    header = [f'{resource}={cores}', f'%mem={int(memory)*1024*80//100}MB']
    if i == 0 and not has_chk:
        header.append(f'%chk={base}.chk')
    new.append('\n'.join(header + kept) + '\n')
pathlib.Path(output).write_text('\n--Link1--\n'.join(new) + '\n')
PY
    [[ $? == 0 ]] || return 1
    export GAUSS_SCRDIR=$scratch_dir
    export OMP_NUM_THREADS=$cores OMP_THREAD_LIMIT=$cores
    export MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
    unset GAUSS_PDEF GAUSS_MDEF GAUSS_WDEF GAUSS_CDEF
    if [[ $GAUSSIAN_SERIES == g16 ]]; then
        allowed=$(python3 - "$cores" <<'CPUS'
import pathlib, sys
for line in pathlib.Path('/proc/self/status').read_text().splitlines():
    if line.startswith('Cpus_allowed_list:'):
        cpus = []
        for group in line.split(':', 1)[1].strip().split(','):
            bounds = group.split('-')
            cpus.extend(range(int(bounds[0]), int(bounds[-1]) + 1))
        count = int(sys.argv[1])
        if len(cpus) < count:
            sys.exit('Fewer allowed CPUs than requested')
        print(','.join(map(str, cpus[:count])))
CPUS
        ) || return 1
        [[ -z $allowed ]] || export GAUSS_CDEF=$allowed
    fi
    ulimit -s unlimited 2>/dev/null
    qjob_msg "-- $GAUSSIAN_SERIES: $cores cores, $((memory * 1024 * 80 / 100)) MB Gaussian memory"
    qjob_msg "   live output: $result_dir/$base.log"
    qjob_msg "   results: $SLURM_SUBMIT_DIR/$result_name/"
    "$driver" < "$input" 2>stderr.log | tee "$base.log"
    statuses=("${PIPESTATUS[@]}")
    (( statuses[0] == 0 )) || return "${statuses[0]}"
    (( statuses[1] == 0 )) || return "${statuses[1]}"
    # A zero process status alone does not establish successful Gaussian completion.
    awk 'NF {last=$0} END {exit !(last ~ /Normal termination of Gaussian/)}' "$base.log" || {
        qjob_msg 'Gaussian did not report normal termination'; return 1;
    }
}
