source "$QJOB_ROOT/apps/suite-common.sh"
APP_TASKS=mpi
SUITE_MODULE=molpro
SUITE_PROGRAM=molpro
app_run() {
    local result_dir
    suite_stage || return 1
    mkdir -p scratch wfu || return 1
    suite_execute molpro -n "$cores" -d "$result_dir/scratch" -W "$result_dir/wfu" -I "$result_dir/scratch" -o "$base.out" "$input"
}
