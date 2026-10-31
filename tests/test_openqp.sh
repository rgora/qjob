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
cat > "$QJOB_CONFIG_DIR/openqp.conf" <<'CONF'
version=1.3.1-foss-2025b
CONF
module() { printf '%s\n' "$*" >> "$QJOB_TEST_DIR/modules"; }
export -f module
cat > "$test_dir/bin/openqp" <<'MOCK'
#!/bin/bash
printf '%s\n' "$@" > "$QJOB_TEST_DIR/args"
printf '%s %s %s\n' "$OMP_NUM_THREADS" "$OMP_THREAD_LIMIT" "$OPENBLAS_NUM_THREADS" > "$QJOB_TEST_DIR/threads"
printf '%s\n' "$TMPDIR" > "$QJOB_TEST_DIR/scratch-path"
input=${!#}
base=${input%.*}
[[ -f "$input" ]] || exit 9
printf native-log > "$base.log"
printf result-json > "$base.json"
echo stdout-result
if grep -q fail-test "$input"; then echo failed >&2; exit 7; fi
[[ ! -f "$QJOB_TEST_DIR/expect-extra" || -f geometry.xyz ]] || exit 8
MOCK
cat > "$test_dir/bin/mpirun" <<'MOCK'
#!/bin/bash
printf '%s\n' "$@" > "$QJOB_TEST_DIR/mpi-args"
[[ $1 == --bind-to && $2 == none && $3 == -np && $4 == 2 ]] || exit 10
shift 4
exec "$@"
MOCK
chmod +x "$test_dir/bin/"*
export PATH=$test_dir/bin:$PATH
cd "$test_dir/work"
printf input > water.inp
printf original-restart > water.json
original=$(cksum water.inp)
"$root/bin/Openqp" --debug -c 3 water.inp > openmp.sh
bash -n openmp.sh
grep -q '^#SBATCH --cpus-per-task=3$' openmp.sh
grep -q '^#SBATCH --ntasks-per-node=1$' openmp.sh
"$root/bin/Openqp" --mpi --debug -c 2 water.inp > mpi.sh
bash -n mpi.sh
grep -q '^#SBATCH --ntasks-per-node=2$' mpi.sh
! grep -q '^#SBATCH --cpus-per-task=' mpi.sh
"$root/bin/Openqp" --local -c 3 water.inp > run.out 2>run.err
[[ $(cat "$QJOB_TEST_DIR/threads") == '3 3 1' ]]
[[ $(cksum water.inp) == "$original" && $(cat water.json) == original-restart ]]
[[ ! -d $(cat "$QJOB_TEST_DIR/scratch-path") ]]
result=$(find . -maxdepth 1 -type d -name 'water-qjob-*' | head -1)
[[ -f $result/water.log && $(cat "$result/water.json") == result-json ]]
grep -q stdout-result "$result/stdout.log"
grep -q 'load OpenQP/1.3.1-foss-2025b' "$QJOB_TEST_DIR/modules"
printf canonical > second.oqp
printf coords > geometry.xyz
touch "$QJOB_TEST_DIR/expect-extra"
"$root/bin/Openqp" --local --mpi -c 2 -C geometry.xyz second.oqp > mpi.out 2>mpi.err
[[ $(cat "$QJOB_TEST_DIR/threads") == '1 1 1' ]]
grep -q '^--omp$' "$QJOB_TEST_DIR/args"
! grep -q '^--nompi$' "$QJOB_TEST_DIR/args"
rm "$QJOB_TEST_DIR/expect-extra"
printf fail-test > failure.inp
if "$root/bin/Openqp" --local failure.inp > fail.out 2>fail.err; then echo 'Expected failure propagation'; exit 1; fi
[[ -d $(cat "$QJOB_TEST_DIR/scratch-path") ]]
failed=$(find . -maxdepth 1 -type d -name 'failure-qjob-*' | head -1)
grep -q failed "$failed/stderr.log"
[[ -s $failed/failure.log ]]
if "$root/bin/Openqp" --debug -n 2 water.inp >/dev/null 2>&1; then echo 'Expected multi-node rejection'; exit 1; fi
printf bad > bad.py
if "$root/bin/Openqp" --debug bad.py >/dev/null 2>&1; then echo 'Expected unsupported input rejection'; exit 1; fi
echo 'PASS: OpenQP allocation, MPI/OpenMP, unchanged inputs, isolated results, auxiliary inputs and failure retention'
