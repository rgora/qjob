#!/usr/bin/env bash
# Linux integration tests: generated jobs, private scratch and copy-back failures.
set -euo pipefail
unset BASH_ENV
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
export QJOB_TEST_DIR=$test_dir
mkdir -p "$test_dir"/{config,scratch,fake-bin,work}
export QJOB_CONFIG_DIR=$test_dir/config
cat > "$QJOB_CONFIG_DIR/qjob.conf" <<CONF
QJOB_SITE=test
partition=normal
QJOB_MAX_NODES=1
QJOB_MAX_CORES=16
QJOB_MAX_MEMORY=32
QJOB_SCRATCH_ROOT='$test_dir/scratch'
QJOB_STORAGE_GRES=false
QJOB_MODULEPATH=''
storage=''
clean_tmp=success
CONF
cat > "$QJOB_CONFIG_DIR/orca.conf" <<'CONF'
cores=2 memory=4 version=6.1.1 time_limit=2
ORCA_MODULE_TEMPLATE='ORCA/%v-gompi-2023b-avx2'
ORCA_PURGE_MODULES=true
CONF
module() { printf '%s\n' "$*" >> "$QJOB_TEST_DIR/modules.txt"; }
export -f module
cat > "$test_dir/fake-bin/orca" <<'MOCK'
#!/bin/bash
printf '%s\n' "$TMPDIR" >> "$QJOB_TEST_DIR/scratch-paths.txt"
stat -c %a "$TMPDIR" > run-details.txt
cp -- "$1" pal-copy.txt
printf gbw > "${1%.*}.gbw"
if grep -q fail-test "$1"; then echo 'Simulated ORCA failure' >&2; exit 7; fi
echo 'ORCA TERMINATED NORMALLY'
MOCK
chmod +x "$test_dir/fake-bin/orca"
export PATH=$test_dir/fake-bin:$PATH
cd "$test_dir/work"
printf '! HF STO-3G PAL8\n%%pal\n nprocs_group 1\nend\n%%maxcore 100\n* xyz 0 1\nH 0 0 0\nH 0 0 0.74\n*\n' > water.inp
original=$(sha256sum water.inp)
"$root/bin/Orca" --debug water.inp > debug.sh
bash -n debug.sh
grep -q '^#SBATCH -p normal$' debug.sh
grep -q '^#SBATCH --ntasks-per-node=2$' debug.sh
! grep -q '^#SBATCH --gres=' debug.sh
if "$root/bin/Orca" --debug -n 2 water.inp >/dev/null 2>&1; then echo 'Expected node-limit rejection'; exit 1; fi
if "$root/bin/Orca" --debug -c 0 water.inp >/dev/null 2>&1; then echo 'Expected zero-core rejection'; exit 1; fi
if "$root/bin/Orca" --debug -m 33 water.inp >/dev/null 2>&1; then echo 'Expected memory-limit rejection'; exit 1; fi
"$root/bin/Orca" --local water.inp > success.stdout 2>success.stderr
[[ $(sha256sum water.inp) == "$original" ]]
[[ $(cat run-details.txt) == 700 ]]
grep -qi '^%pal nprocs 2' pal-copy.txt
! grep -q PAL8 pal-copy.txt
[[ $(grep -ic '^%pal' pal-copy.txt) == 1 ]]
[[ -s water.gbw ]]
[[ ! -d $(tail -1 "$test_dir/scratch-paths.txt") ]]
grep -q 'load ORCA/6.1.1-gompi-2023b-avx2' "$test_dir/modules.txt"
printf '! fail-test\n' > failure.inp
if "$root/bin/Orca" --local failure.inp > failure.stdout 2>failure.stderr; then echo 'Expected ORCA failure'; exit 1; fi
[[ -d $(tail -1 "$test_dir/scratch-paths.txt") ]]
# Failure copying a result must keep scratch and fail the job even after ORCA succeeds.
cp() {
    if [[ ${1-} == -r && ${4-} == "$QJOB_TEST_DIR/work/" ]]; then return 1; fi
    command cp "$@"
}
export -f cp
if "$root/bin/Orca" --local water.inp > copy-failure.stdout 2>copy-failure.stderr; then echo 'Expected copy-back failure'; exit 1; fi
[[ -d $(tail -1 "$test_dir/scratch-paths.txt") ]]
unset -f cp
# Preserve WCSS defaults in a checkout without site configuration.
mkdir "$test_dir/no-config"
QJOB_CONFIG_DIR=$test_dir/no-config "$root/bin/Orca" --debug water.inp > wcss.sh
grep -q '^#SBATCH --gres=storage:shm:400g$' wcss.sh
echo 'PASS: site defaults, Slurm script, resource validation, PAL sync, unchanged input, private scratch, copy-back and failure retention'
