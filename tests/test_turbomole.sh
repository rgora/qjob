#!/usr/bin/env bash
set -euo pipefail
unset BASH_ENV QJOB_PROFILE
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
export QJOB_CONFIG_DIR=$test_dir/config QJOB_USER_CONFIG_DIR=$test_dir/user
export QJOB_TM_TEST=$test_dir
mkdir -p "$test_dir"/{config,user,scratch,work,turbo/bin}
cat > "$QJOB_CONFIG_DIR/qjob.conf" <<CONF
partition=normal
storage=''
QJOB_STORAGE_GRES=false
QJOB_SCRATCH_ROOT='$test_dir/scratch'
clean_tmp=success
CONF
cat > "$QJOB_CONFIG_DIR/turbomole.conf" <<'CONF'
TM_MODULE=TURBOMOLE
version=8.0.1
TM_PURGE_MODULES=true
CONF
cat > "$test_dir/turbo/Config_turbo_env" <<'CONF'
export PATH=$TURBODIR/bin:$PATH
CONF
cat > "$test_dir/turbo/bin/dscf" <<'PROG'
#!/bin/bash
printf '%s:%s:%s\n' "$PARA_ARCH" "$PARNODES" "$OMP_NUM_THREADS"
printf '%s\n' "$TMPDIR" > "$QJOB_TM_TEST/scratch-path"
exit "${TM_TEST_EXIT:-0}"
PROG
chmod +x "$test_dir/turbo/bin/dscf"
module() {
    printf '%s\n' "$*" >> "$QJOB_TM_TEST/modules"
    if [[ $1 == load ]]; then
        export TURBODIR=$QJOB_TM_TEST/turbo PARA_ARCH=SMP PARNODES=99 OMP_NUM_THREADS=99
    fi
}
export -f module
cd "$test_dir/work"
printf '$end\n' > control
printf keep > CC_user_data
"$root/bin/Turbomole" --debug -c 1 dscf > serial.sh
bash -n serial.sh
export SLURM_SUBMIT_DIR=$PWD SLURM_JOB_ID=123
bash serial.sh > serial.out 2>serial.err
grep -q '^:1:1$' work_dscf.log
[[ -s CC_user_data && ! -d $(cat "$QJOB_TM_TEST/scratch-path") ]]
"$root/bin/Turbomole" --local -c 2 dscf > smp.out 2>smp.err
grep -q '^SMP:2:2$' smp.out
"$root/bin/Turbomole" --arch mpi --local -c 2 dscf > mpi.out 2>mpi.err
grep -q '^MPI:2:1$' mpi.out
"$root/bin/Turbomole" --arch mpi --debug -c 2 dscf > mpi.sh
grep -q '^#SBATCH --ntasks-per-node=2$' mpi.sh
export TM_TEST_EXIT=7
if bash serial.sh > failed.out 2>failed.err; then exit 1; fi
[[ -d $(cat "$QJOB_TM_TEST/scratch-path") ]]
grep -q 'load TURBOMOLE/8.0.1' "$QJOB_TM_TEST/modules"
rm control
if "$root/bin/Turbomole" --debug dscf > missing.out 2>&1; then exit 1; fi
echo 'PASS: TURBOMOLE serial/SMP/MPI settings, module, Slurm header, failure scratch, user-file preservation and missing control'
