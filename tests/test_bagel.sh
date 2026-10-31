#!/usr/bin/env bash
set -euo pipefail
unset BASH_ENV QJOB_PROFILE
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
export QJOB_TEST_DIR=$test_dir QJOB_CONFIG_DIR=$test_dir/config QJOB_USER_CONFIG_DIR=$test_dir/user
mkdir -p "$test_dir"/{config,user,scratch,bin,work}
cat > "$QJOB_CONFIG_DIR/qjob.conf" <<CONF
QJOB_SITE=test
partition=normal
storage=''
QJOB_STORAGE_GRES=false
QJOB_MAX_NODES=1
QJOB_SCRATCH_ROOT='$test_dir/scratch'
clean_tmp=success
CONF
printf 'version=1.2.2-foss-2025b\n' > "$QJOB_CONFIG_DIR/bagel.conf"
module() { printf '%s\n' "$*" >> "$QJOB_TEST_DIR/modules"; }
export -f module
cat > "$test_dir/bin/BAGEL" <<'MOCK'
#!/bin/bash
printf '%s\n' "$TMPDIR" > "$QJOB_TEST_DIR/scratch-path"
printf '%s %s %s %s\n' "$BAGEL_NUM_THREADS" "$OMP_NUM_THREADS" "$OMP_THREAD_LIMIT" "$OPENBLAS_NUM_THREADS" > "$QJOB_TEST_DIR/threads"
[[ -f $1 && -f restart.archive ]] || exit 9
printf saved > saved.archive
echo 'SCF iteration converged.'
if grep -q fail-test "$1"; then echo failed >&2; exit 7; fi
MOCK
cat > "$test_dir/bin/mpirun" <<'MOCK'
#!/bin/bash
printf '%s\n' "$@" > "$QJOB_TEST_DIR/mpi-args"
[[ $1 == --bind-to && $3 == -np ]] || exit 10
[[ $2 == core && $4 == 2 || $2 == none && $4 == 1 ]] || exit 11
shift 4
exec "$@"
MOCK
chmod +x "$test_dir/bin/"*
export PATH=$test_dir/bin:$PATH
cd "$test_dir/work"
printf input > hf.json
printf original > restart.archive
original=$(cksum hf.json)
"$root/bin/Bagel" --debug -c 2 hf.json > mpi.sh
bash -n mpi.sh
grep -q '^#SBATCH --ntasks-per-node=2$' mpi.sh
"$root/bin/Bagel" --openmp --debug -c 3 hf.json > threads.sh
bash -n threads.sh
grep -q '^#SBATCH --cpus-per-task=3$' threads.sh
"$root/bin/Bagel" --local -c 2 -C restart.archive hf.json > mpi.out 2>mpi.err
[[ $(cat "$QJOB_TEST_DIR/threads") == '1 1 1 1' ]]
[[ $(cksum hf.json) == "$original" && $(cat restart.archive) == original ]]
[[ ! -d $(cat "$QJOB_TEST_DIR/scratch-path") ]]
result=$(find . -maxdepth 1 -type d -name 'hf-qjob-*' | head -1)
[[ -f $result/saved.archive ]]
grep -q converged "$result/stdout.log"
grep -q 'load BAGEL/1.2.2-foss-2025b' "$QJOB_TEST_DIR/modules"
"$root/bin/Bagel" --local --openmp -c 3 -C restart.archive hf.json > threads.out 2>threads.err
[[ $(cat "$QJOB_TEST_DIR/threads") == '3 3 3 3' ]]
printf fail-test > failure.json
if "$root/bin/Bagel" --local -c 2 -C restart.archive failure.json > fail.out 2>fail.err; then echo 'Expected failure propagation'; exit 1; fi
[[ -d $(cat "$QJOB_TEST_DIR/scratch-path") ]]
failed=$(find . -maxdepth 1 -type d -name 'failure-qjob-*' | head -1)
grep -q failed "$failed/stderr.log"
[[ -f $failed/saved.archive ]]
if "$root/bin/Bagel" --debug -n 2 hf.json >/dev/null 2>&1; then echo 'Expected multi-node rejection'; exit 1; fi
QJOB_PROFILE=wcss "$root/bin/Bagel" --debug hf.json > wcss.sh
grep -q '1.2.2-foss-2021a' wcss.sh
grep -q '^#SBATCH -p lem-cpu-short$' wcss.sh
grep -q '/usr/local/sbin/modules.sh' wcss.sh
echo 'PASS: BAGEL MPI/threads allocation, auxiliary inputs, isolated results, failure propagation, scratch retention and WCSS profile'
