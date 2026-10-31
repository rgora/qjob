#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root"/{config,scratch,nx/bin,trajectory/JOB_AD}
printf 'fixture\n' > "$test_root/trajectory/JOB_AD/input"
ln -s ../JOB_AD/input "$test_root/trajectory/JOB_AD/linked"
# Use a valid link that is resolved while staging the source directory.
ln -s JOB_AD/input "$test_root/trajectory/geometry"
cat > "$test_root/nx/bin/nx_moldyn" <<'DRIVER'
#!/bin/bash
set -e
[[ $(cat geometry) == fixture ]]
mkdir -p RESULTS
printf '3.0\n' > RESULTS/final_time
printf 'NX output\n'
printf 'NX diagnostic\n' >&2
exit "${NX_TEST_EXIT:-0}"
DRIVER
chmod +x "$test_root/nx/bin/nx_moldyn"
cat > "$test_root/config/qjob.conf" <<CONFIG
partition=test
nodes=1
cores=1
memory=1
storage=''
run_local=0
QJOB_MODULEPATH=''
QJOB_MODULE_INIT=''
QJOB_SCRATCH_ROOT='$test_root/scratch'
QJOB_STORAGE_GRES=false
clean_tmp=success
NX_ROOT='$test_root/nx'
CONFIG
export QJOB_PROFILE='' QJOB_CONFIG_DIR=$test_root/config QJOB_USER_CONFIG_DIR=$test_root/config
cd "$test_root/trajectory"
"$root/bin/Newtonx" --debug nx_moldyn > job.sbatch
bash -n job.sbatch
export SLURM_SUBMIT_DIR=$PWD SLURM_JOB_ID=success
bash job.sbatch > "$test_root/success.log" 2>&1
[[ $(cat trajectory-qjob-success/RESULTS/final_time) == 3.0 ]]
grep -q 'NX output' trajectory-qjob-success/stdout.log
grep -q 'NX diagnostic' trajectory-qjob-success/stderr.log
[[ -L geometry && ! -L trajectory-qjob-success/geometry ]]
[[ -z $(ls -A "$test_root/scratch") ]]
export SLURM_JOB_ID=failure NX_TEST_EXIT=7
if bash job.sbatch > "$test_root/failure.log" 2>&1; then echo 'failure was lost'; exit 1; else [[ $? == 7 ]]; fi
[[ -f trajectory-qjob-failure/RESULTS/final_time ]]
[[ -n $(ls -A "$test_root/scratch") ]]
[[ ! -e trajectory-qjob-failure/trajectory-qjob-success ]]
if "$root/bin/Newtonx" --debug -n 2 nx_moldyn >/dev/null 2>&1; then exit 1; fi
if "$root/bin/Newtonx" --debug ../nx_moldyn >/dev/null 2>&1; then exit 1; fi
echo 'Newton-X staging, symlinks, copy-back, exit status and failed-scratch retention: PASS'
