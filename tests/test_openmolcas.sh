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
QJOB_SCRATCH_ROOT='$test_dir/scratch'
clean_tmp=success
CONF
printf 'version=25.06-gompi-2025b\n' > "$QJOB_CONFIG_DIR/openmolcas.conf"
module() { printf '%s\n' "$*" >> "$QJOB_TEST_DIR/modules"; }
export -f module
cat > "$test_dir/bin/pymolcas" <<'MOCK'
#!/bin/bash
[[ $1 == -ign && -f $2 && -f geometry.xyz ]] || exit 9
[[ $PWD == "$CurrDir" && $PWD == "$MOLCAS_OUTPUT" && -d $WorkDir ]] || exit 10
[[ $WorkDir != "$PWD" && $MOLCAS_MAXMEM == "$MOLCAS_MEM" ]] || exit 11
printf '%s\n' "$TMPDIR" > "$QJOB_TEST_DIR/scratch-path"
printf '%s %s %s %s\n' "$MOLCAS_NPROCS" "$MOLCAS_THREADS" "$OMP_NUM_THREADS" "$MOLCAS_MEM" > "$QJOB_TEST_DIR/resources"
printf saved > "$WorkDir/$Project.JobIph"
printf restart > "$WorkDir/$Project.RunFile"
printf hdf5 > "$WorkDir/$Project.rasscf.h5"
printf integral > "$WorkDir/$Project.OrdInt"
echo 'Happy landing!'
if grep -q fail-test "$2"; then echo failed >&2; exit 7; fi
MOCK
chmod +x "$test_dir/bin/pymolcas"
export PATH=$test_dir/bin:$PATH
cd "$test_dir/work"
printf input > water.inp
printf xyz > geometry.xyz
original=$(cksum water.inp)
"$root/bin/OpenMolcas" --debug -c 2 water.inp > mpi.sh
bash -n mpi.sh
grep -q '^#SBATCH --ntasks-per-node=2$' mpi.sh
"$root/bin/OpenMolcas" --openmp --debug -c 3 water.inp > threads.sh
grep -q '^#SBATCH --cpus-per-task=3$' threads.sh
"$root/bin/OpenMolcas" --local -c 2 -m 4 -C geometry.xyz water.inp > mpi.out 2>mpi.err
[[ $(cat "$QJOB_TEST_DIR/resources") == '2 1 1 1638' ]]
[[ $(cksum water.inp) == "$original" ]]
[[ ! -d $(cat "$QJOB_TEST_DIR/scratch-path") ]]
result=$(find . -maxdepth 1 -type d -name 'water-qjob-*' | head -1)
[[ -f $result/water.JobIph && -f $result/water.RunFile && -f $result/water.rasscf.h5 && ! -f $result/water.OrdInt ]]
grep -q 'Happy landing' "$result/stdout.log"
grep -q 'load OpenMolcas/25.06-gompi-2025b' "$QJOB_TEST_DIR/modules"
"$root/bin/OpenMolcas" --local --openmp -c 3 -m 4 -C geometry.xyz water.inp > threads.out 2>threads.err
[[ $(cat "$QJOB_TEST_DIR/resources") == '1 3 3 3276' ]]
printf fail-test > failure.input
set +e
"$root/bin/OpenMolcas" --local -c 2 -C geometry.xyz failure.input > fail.out 2>fail.err
rc=$?
set -e
[[ $rc != 0 && -d $(cat "$QJOB_TEST_DIR/scratch-path") ]]
failed=$(find . -maxdepth 1 -type d -name 'failure-qjob-*' | head -1)
[[ -f $failed/failure.JobIph ]]
grep -q failed "$failed/stderr.log"
grep -q "exit status 7" fail.err
if "$root/bin/OpenMolcas" --debug -n 2 water.inp >/dev/null 2>&1; then exit 1; fi
QJOB_PROFILE=wcss "$root/bin/OpenMolcas" --debug water.inp > wcss.sh
grep -q '25.06-openmpi-kdm' wcss.sh
grep -q '^#SBATCH -p lem-cpu-short$' wcss.sh
echo 'PASS: OpenMolcas resources, staging, exported restarts, failure status, scratch retention and WCSS profile'
