#!/usr/bin/env bash
# =============================================================================
# qjob - minimal Slurm job submission (WCSS)
#
#   qjob.sh <app> [options] inputs...        (normally called via bin/<App>)
#
#   lib/qjob.sh     option parsing, #SBATCH header, submission      (this file)
#   lib/runtime.sh  code run inside the job: prologue, copy in/out, epilogue
#   apps/<app>.sh   per-application defaults, extra options, job body app_run()
#
# The job script is assembled as:
#   #SBATCH header + variable block (declare -p) + app functions (declare -f)
#   + lib/runtime.sh
# so no escaping of \$ is needed anywhere; '--debug' prints the complete script.
# =============================================================================

QJOB_ROOT=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
QJOB_APP=${1:?usage: qjob.sh <app> [options] inputs}; shift
QJOB_CMD=${QJOB_CMD:-$QJOB_APP}
QJOB_ARGS=$(printf '%q ' "$@")

red=$'\e[1;31m' blu=$'\e[1;34m' end=$'\e[0m'
[ -t 2 ] || red='' blu='' end=''
die()  { printf '%s\n' "${red}${QJOB_CMD}: $*${end}" >&2; exit 1; }
warn() { printf '%s\n' "${red}warning:${end} $*" >&2; }

# ------------------------------------------------------------ generic defaults
if id -nG 2>/dev/null | grep -qw plgrid; then partition=plgrid-lem-cpu; else partition=lem-cpu; fi
nodes=1 cores=8 memory=16 time_limit=1 storage=shm:40g gres=""
nodelist="" account="" qos="" mail="" reservation="" exclusive=0 slurmopt=""
name="" version="" copy="" copy_back="" clean_tmp=false
debug=0 run_local=0 show_help=0
signal_lead=300        # s before the time limit: USR1 -> copy-back of current results
QJOB_SITE=WCSS
QJOB_SCRATCH_ROOT="" QJOB_MODULEPATH="" QJOB_STORAGE_GRES=true
QJOB_MAX_NODES=0 QJOB_MAX_CORES=0 QJOB_MAX_MEMORY=0

# ------------------------------------------------------------ application hooks
APP_SYNOPSIS="input [input2 ...]"
APP_INPUT=file         # file: one job per input file (run in its directory)
                       # args: one job, positional arguments = command (Turbomole)
APP_TASKS=mpi          # mpi: --ntasks-per-node=cores;  threads: --cpus-per-task=cores
APP_SHORT="" APP_LONG="" APP_VARS="" APP_FUNCS=""
app_usage()   { :; }
app_option()  { return 1; }   # app_option "$1" "$2": set APP_SHIFT, return 1 if unknown
app_setup()   { :; }          # after option parsing (once)
app_prepare() { :; }          # at submission, once per job; $input/$base set, cwd = input dir
app_run()     { :; }          # job body (runs inside the job)

[ -f "$QJOB_ROOT/apps/$QJOB_APP.sh" ] || die "unknown application '$QJOB_APP'"
# shellcheck source=/dev/null
source "$QJOB_ROOT/apps/$QJOB_APP.sh"     # may override the defaults above

# Site defaults belong outside the Git checkout. CLI options take precedence.
QJOB_CONFIG_DIR=${QJOB_CONFIG_DIR:-/etc/qjob}
for config in "$QJOB_CONFIG_DIR/qjob.conf" "$QJOB_CONFIG_DIR/$QJOB_APP.conf"; do
    if [ -f "$config" ]; then
        [ -r "$config" ] || die "configuration is not readable: $config"
        source "$config" || die "could not load configuration: $config"
    fi
done

usage() {
cat >&2 <<EOF
${blu}$QJOB_CMD${end} (qjob @ $QJOB_SITE)
Usage: $QJOB_CMD [options] $APP_SYNOPSIS

Resources                                              [default]
  -p, --partition NAME     partition                    [$partition]
  -n, --nodes N            nodes                        [$nodes]
  -c, --cores N            cores per node               [$cores]
  -m, --memory GB          memory per node (integer)    [$memory]
  -t, --time H             wall time in hours or D-HH:MM:SS  [$time_limit]
  -s, --storage TYPE:SIZE  TMPDIR, TYPE=shm|local|lustre [$storage]
      --gres STR           additional gres (e.g. gpu:...)
  -w, --nodelist LIST      specific nodes
  -A, --account ACC        -q, --qos QOS     --reservation NAME     --exclusive
      --mail TYPE          BEGIN,END,FAIL,ALL
      --slurmopt "OPTS"    any further sbatch options, e.g. "--dependency=afterok:123"
Files
  -C, --copy "FILES"       copy to TMPDIR before the run          [$copy]
  -B, --copy-back "FILES"  copy back from TMPDIR after the run    [$copy_back]
                           (%b = input name without extension; also done
                            ${signal_lead} s before the time limit)
      --clean-tmp WHEN     empty TMPDIR at the end: false|success|always [$clean_tmp]
Other
  -v, --version VER        module version                         [${version:-default}]
      --name NAME          job name (default: input file name)
      --local              run here without Slurm (e.g. in an interactive allocation)
      --debug              print the job script, do not submit
  -h, --help
EOF
app_usage
}

# ------------------------------------------------------------ options
SHORT="+hp:n:c:m:t:s:w:A:q:C:B:v:${APP_SHORT}"
LONG="help,debug,local,partition:,nodes:,cores:,memory:,time:,storage:,gres:,nodelist:"
LONG+=",account:,qos:,reservation:,exclusive,mail:,slurmopt:,copy:,copy-back:,clean-tmp:"
LONG+=",version:,name:${APP_LONG:+,$APP_LONG}"
PARSED=$(getopt -o "$SHORT" -l "$LONG" -n "$QJOB_CMD" -- "$@") || { echo "Try '$QJOB_CMD -h'." >&2; exit 2; }
eval set -- "$PARSED"
while :; do
    case $1 in
        -h|--help)      show_help=1; shift ;;
        --debug)        debug=1; shift ;;
        --local)        run_local=1; shift ;;
        --exclusive)    exclusive=1; shift ;;
        -p|--partition) partition=$2; shift 2 ;;
        -n|--nodes)     nodes=$2; shift 2 ;;
        -c|--cores)     cores=$2; shift 2 ;;
        -m|--memory)    memory=$2; shift 2 ;;
        -t|--time)      time_limit=$2; shift 2 ;;
        -s|--storage)   storage=$2; shift 2 ;;
        --gres)         gres=$2; shift 2 ;;
        -w|--nodelist)  nodelist=$2; shift 2 ;;
        -A|--account)   account=$2; shift 2 ;;
        -q|--qos)       qos=$2; shift 2 ;;
        --reservation)  reservation=$2; shift 2 ;;
        --mail)         mail=$2; shift 2 ;;
        --slurmopt)     slurmopt=$2; shift 2 ;;
        -C|--copy)      copy=$2; shift 2 ;;
        -B|--copy-back) copy_back=$2; shift 2 ;;
        --clean-tmp)    clean_tmp=$2; shift 2 ;;
        -v|--version)   version=$2; shift 2 ;;
        --name)         name=$2; shift 2 ;;
        --)             shift; break ;;
        *)              APP_SHIFT=0
                        app_option "$1" "${2-}" || die "unhandled option $1"
                        shift "$APP_SHIFT" ;;
    esac
done

if (( show_help )); then usage; exit 0; fi
[ $# -gt 0 ] || { usage; exit 1; }

# ------------------------------------------------------------ checks
for v in nodes cores memory; do
    [[ ${!v} =~ ^[1-9][0-9]*$ ]] || die "--$v must be a positive integer (got '${!v}')"
done
app_setup
for v in NODES CORES MEMORY; do
    limit_var=QJOB_MAX_$v
    [[ ${!limit_var} =~ ^[0-9]+$ ]] || die "invalid site limit $limit_var"
    resource=${v,,}
    (( ${!limit_var} == 0 || ${!resource} <= ${!limit_var} )) \
        || die "--$resource exceeds the site limit (${!limit_var})"
done
if [[ $time_limit =~ ^[0-9]+$ ]]; then wall="$time_limit:00:00"; else wall=$time_limit; fi
[ -z "$storage" ] || [[ $storage =~ ^(shm|local|lustre):[0-9]+[kKmMgGtT]?[bB]?$ ]] \
    || die "--storage must be shm|local|lustre:<size>, e.g. shm:200g"
[[ $clean_tmp =~ ^(false|success|always)$ ]] || die "--clean-tmp must be false|success|always"
[ "$APP_TASKS" = threads ] && (( nodes > 1 )) && die "$QJOB_APP in this mode runs on one node only"
if [ -n "$QJOB_SCRATCH_ROOT" ] && [ -n "$storage" ] && [[ $storage != local:* ]]; then
    die "this site uses local scratch; use --storage local:<size> or omit --storage"
fi
gres_all=""
[ "$QJOB_STORAGE_GRES" != true ] || gres_all=${storage:+storage:$storage}
gres_all=${gres_all}${gres:+${gres_all:+,}$gres}

# ------------------------------------------------------------ job script
QJOB_VARS="QJOB_APP QJOB_CMD jobname input base nodes cores memory version copy copy_back clean_tmp run_local"
QJOB_VARS+=" QJOB_SCRATCH_ROOT QJOB_MODULEPATH"

make_script() {
    local quoted_jobname=${jobname//\\/\\\\}
    quoted_jobname=${quoted_jobname//\"/\\\"}
    echo '#!/bin/bash'
    printf '#SBATCH --job-name="%s"\n' "$quoted_jobname"
    echo "#SBATCH -p $partition"
    echo "#SBATCH -N $nodes"
    if [ "$APP_TASKS" = mpi ]; then
        echo "#SBATCH --ntasks-per-node=$cores"
    else
        echo "#SBATCH --ntasks-per-node=1"
        echo "#SBATCH --cpus-per-task=$cores"
    fi
    echo "#SBATCH --mem=${memory}G"
    echo "#SBATCH -t $wall"
    echo "#SBATCH --signal=B:USR1@$signal_lead"
    [ -n "$gres_all" ]    && echo "#SBATCH --gres=$gres_all"
    [ -n "$nodelist" ]    && echo "#SBATCH --nodelist=$nodelist"
    [ -n "$account" ]     && echo "#SBATCH -A $account"
    [ -n "$qos" ]         && echo "#SBATCH --qos=$qos"
    [ -n "$reservation" ] && echo "#SBATCH --reservation=$reservation"
    [ -n "$mail" ]        && echo "#SBATCH --mail-type=$mail"
    (( exclusive ))       && echo "#SBATCH --exclusive"
    local o; for o in $slurmopt; do echo "#SBATCH $o"; done
    echo
    echo "# generated by qjob ($QJOB_CMD) $(date '+%F %T') in $PWD"
    echo "# command: $QJOB_CMD $QJOB_ARGS"
    local v; for v in $QJOB_VARS $APP_VARS; do declare -p "$v"; done
    echo
    declare -f $APP_FUNCS app_run
    echo
    cat "$QJOB_ROOT/lib/runtime.sh"
}

submit() {             # uses $input, $base, cwd
    jobname="$QJOB_APP:${name:-${input:-$base}}"
    local value
    for value in "$jobname" "$partition" "$wall" "$nodelist" "$account" "$qos" "$reservation" "$mail" "$gres_all" "$slurmopt"; do
        [[ $value != *$'\n'* && $value != *$'\r'* ]] || die "newlines are not allowed in Slurm options or job names"
    done
    app_prepare || return 1
    copy=${copy_t//%b/$base} copy_back=${copy_back_t//%b/$base}
    local script; script=$(make_script)
    if (( debug )); then
        printf '%s\n' "$script"
    elif (( run_local )); then
        local f; f=$(mktemp "${TMPDIR:-/tmp}/qjob.XXXXXX.sh")
        printf '%s\n' "$script" > "$f"
        bash "$f"; local rc=$?
        rm -f "$f"; return $rc
    else
        printf '%s\n' "${blu}$jobname${end}  $partition  ${nodes}x${cores} cores  ${memory} GB  ${wall}  ${gres_all}" >&2
        printf '%s\n' "$script" | sbatch
    fi
}

copy_t=$copy copy_back_t=$copy_back
rc=0
if [ "$APP_INPUT" = file ]; then
    for f in "$@"; do
        [ -f "$f" ] || { warn "no such file: $f"; rc=1; continue; }
        ( cd "$(dirname -- "$f")" || exit 1
          input=$(basename -- "$f"); base=${input%.*}
          submit ) || rc=1
    done
else
    APP_ARGS=("$@") input="" base=""
    submit || rc=1
fi
exit $rc
