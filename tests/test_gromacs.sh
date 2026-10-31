#!/usr/bin/env bash
set -euo pipefail
unset BASH_ENV QJOB_PROFILE
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
export QJOB_TEST_DIR=$test_dir QJOB_CONFIG_DIR=$test_dir/config QJOB_USER_CONFIG_DIR=$test_dir/user
mkdir -p "$test_dir/config" "$test_dir/user" "$test_dir/scratch" "$test_dir/bin" "$test_dir/work"
cat > "$QJOB_CONFIG_DIR/qjob.conf" <<CONF
QJOB_SITE=test
partition=normal
storage=''
QJOB_STORAGE_GRES=false
QJOB_MAX_NODES=1
QJOB_SCRATCH_ROOT='$test_dir/scratch'
clean_tmp=success
CONF
cat > "$QJOB_CONFIG_DIR/gromacs.conf" <<'CONF'
version=2026.2-foss-2025b
CONF
module() { printf '%s\n' "$*" >> "$QJOB_TEST_DIR/modules"; }
export -f module
cat > "$test_dir/bin/gmx" <<'MOCK'
#!/bin/bash
printf '%s\n' "$@" > "$QJOB_TEST_DIR/args"
printf '%s\n' "$TMPDIR" > "$QJOB_TEST_DIR/scratch-path"
printf '%s\n' "$OMP_NUM_THREADS" > "$QJOB_TEST_DIR/threads"
base='' input='' checkpoint=''
while (( $# )); do
    case $1 in
        -deffnm) base=$2; shift ;;
        -s) input=$2; shift ;;
        -cpi) checkpoint=$2; shift ;;
    esac
    shift
done
printf partial > "$base.log"
if grep -q fail-test "$input"; then exit 7; fi
if [[ -n $checkpoint ]]; then
    cmp "$checkpoint" "$QJOB_TEST_DIR/original.cpt" || exit 8
    base=$base.part0002
fi
printf coordinates > "$base.gro"
printf energy > "$base.edr"
MOCK
chmod +x "$test_dir/bin/gmx"
export PATH=$test_dir/bin:$PATH
cd "$test_dir/work"
printf tpr > water.tpr
original=$(cksum water.tpr)
"$root/bin/Gromacs" --debug -c 3 water.tpr > cpu.sh
bash -n cpu.sh
grep -q '^#SBATCH --cpus-per-task=3$' cpu.sh
grep -q '^#SBATCH --ntasks-per-node=1$' cpu.sh
! grep -q '^#SBATCH --gres=' cpu.sh
"$root/bin/Gromacs" --local -c 3 --nsteps 100 water.tpr > cpu.out 2>cpu.err
[[ $(cat "$QJOB_TEST_DIR/threads") == 3 ]]
[[ $(cksum water.tpr) == "$original" ]]
[[ -s water.gro && -s water.edr ]]
[[ ! -d $(cat "$QJOB_TEST_DIR/scratch-path") ]]
grep -q 'load GROMACS/2026.2-foss-2025b' "$QJOB_TEST_DIR/modules"
grep -A 1 -- '^-nb$' "$QJOB_TEST_DIR/args" | grep -q '^cpu$'
"$root/bin/Gromacs" --gpu --debug water.tpr > gpu.sh
grep -q '^#SBATCH --gres=gpu:1$' gpu.sh
cat >> "$QJOB_CONFIG_DIR/gromacs.conf" <<'CONF'
GROMACS_MODE=gpu
GROMACS_GPU_GRES=''
GROMACS_GPU_EXCLUSIVE=true
CONF
"$root/bin/Gromacs" --debug water.tpr > exclusive.sh
grep -q '^#SBATCH --exclusive$' exclusive.sh
! grep -q '^#SBATCH --gres=' exclusive.sh
"$root/bin/Gromacs" --cpu --debug water.tpr > cpu-override.sh
! grep -q '^#SBATCH --exclusive$' cpu-override.sh
printf checkpoint > "$QJOB_TEST_DIR/original.cpt"
"$root/bin/Gromacs" --local --checkpoint "$QJOB_TEST_DIR/original.cpt" water.tpr > restart.out 2>restart.err
[[ -s water.part0002.gro && -s water.part0002.edr ]]
grep -q -- '^-noappend$' "$QJOB_TEST_DIR/args"
grep -A 1 -- '^-nb$' "$QJOB_TEST_DIR/args" | grep -q '^gpu$'
printf fail-test > failure.tpr
if "$root/bin/Gromacs" --local failure.tpr > fail.out 2>fail.err; then echo 'Expected mdrun failure'; exit 1; fi
[[ -d $(cat "$QJOB_TEST_DIR/scratch-path") && -s failure.log ]]
if "$root/bin/Gromacs" --debug --checkpoint missing.cpt water.tpr >/dev/null 2>&1; then echo 'Expected missing-checkpoint rejection'; exit 1; fi
if "$root/bin/Gromacs" --debug --nsteps wrong water.tpr >/dev/null 2>&1; then echo 'Expected invalid-step rejection'; exit 1; fi
if "$root/bin/Gromacs" --debug -n 2 water.tpr >/dev/null 2>&1; then echo 'Expected multi-node rejection'; exit 1; fi
echo 'PASS: GROMACS CPU/GPU allocation, OpenMP, unchanged TPR, results, checkpoint restart and failure retention'
