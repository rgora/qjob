source "$QJOB_ROOT/apps/suite-common.sh"
APP_TASKS=mpi
SUITE_MODULE=Dalton
SUITE_PROGRAM=dalton
APP_LONG='molecule:'
DALTON_MOLECULE=''
APP_VARS+=' DALTON_MOLECULE'
app_option() {
    case $1 in
        --molecule) DALTON_MOLECULE=${2%.mol}; APP_SHIFT=2 ;;
        *) return 1 ;;
    esac
}
app_prepare() {
    [[ $input =~ ^[[:alnum:]_][[:alnum:]_.+-]*\.dal$ ]] || die 'use an .dal input file'
    DALTON_MOLECULE=${DALTON_MOLECULE:-$base}
    [[ $DALTON_MOLECULE =~ ^[[:alnum:]_][[:alnum:]_.+-]*$ && -f $DALTON_MOLECULE.mol ]] || die 'matching .mol file missing; use --molecule NAME'
    copy_t+=" $DALTON_MOLECULE.mol"
}
app_run() {
    local result_dir
    suite_stage || return 1
    suite_execute dalton -N "$cores" -t "$result_dir/scratch" -w "$result_dir" "$base" "$DALTON_MOLECULE"
}

app_usage() {
    suite_usage
    echo '  --molecule NAME    .mol file basename (default: basename of .dal input).' >&2
    echo '  Example: Dalton -c 4 --molecule water hf.dal' >&2
}
