#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/fake/g16/bsd" "$test_dir/config" "$test_dir/work" "$test_dir/scratch"
printf ':\n' > "$test_dir/fake/g16/bsd/g16.profile"
cat > "$test_dir/config/qjob.conf" <<CONFIG
QJOB_SITE=test
partition=test
QJOB_SCRATCH_ROOT=$test_dir/scratch
QJOB_MODULEPATH=''
QJOB_MODULE_INIT=''
QJOB_STORAGE_GRES=false
storage=''
clean_tmp=success
GAUSSIAN_ROOT=$test_dir/fake
CONFIG
cat > "$test_dir/fake/g16/g16" <<'FAKE'
#!/usr/bin/env bash
cat > received.input
[[ $OMP_NUM_THREADS == 2 && $OMP_THREAD_LIMIT == 2 ]] || exit 11
[[ -d $GAUSS_SCRDIR && $GAUSS_SCRDIR != "$PWD" ]] || exit 12
[[ $(grep -ci '^%nprocshared=2$' received.input) == 2 ]] || exit 13
[[ $(grep -ci '^%mem=1638MB$' received.input) == 2 ]] || exit 14
! grep -qiE '^%(rwf|cpu|lindaworkers|nproclinda)=' received.input || exit 15
[[ -f restart.chk && -f .hidden ]] || exit 16
printf checkpoint > result.chk
printf scratch > "$GAUSS_SCRDIR/large.rwf"
if grep -q FAIL received.input; then echo 'Error termination'; exit 7; fi
if grep -q FALSE_SUCCESS received.input; then
  echo 'Normal termination of Gaussian 16'
  echo 'Error termination'; exit 0
fi
echo 'Normal termination of Gaussian 16'
FAKE
chmod +x "$test_dir/fake/g16/g16"
export QJOB_CONFIG_DIR="$test_dir/config" QJOB_USER_CONFIG_DIR="$test_dir/no-user-config"
unset QJOB_PROFILE
cd "$test_dir/work"
cat > water.com <<'INPUT'
%Mem=999GB
%NProcShared=999
%CPU=0-999
%LindaWorkers=badhost
%RWF=/bad/path
%Chk=result.chk
# HF/STO-3G

H2

0 1
H 0 0 0
H 0 0 0.74

--Link1--
%mem=999GB
%nproc=999
# HF/STO-3G geom=allcheck guess=read

INPUT
cp water.com original.com
printf restart > restart.chk
printf hidden > .hidden
"$root/bin/Gaussian" --debug -c 2 -m 2 water.com > debug.sh
grep -q '#SBATCH --cpus-per-task=2' debug.sh
"$root/bin/Gaussian" --local -c 2 -m 2 -C 'restart.chk .hidden' water.com > success.stdout 2>success.stderr
cmp water.com original.com
result=$(find . -maxdepth 1 -type d -name 'water-qjob-*')
[[ -f $result/result.chk && -f $result/.hidden && -f $result/original.input ]]
[[ ! -f $result/large.rwf ]]
[[ -z $(ls -A "$test_dir/scratch") ]]
for failure in FAIL FALSE_SUCCESS; do
    cp water.com "$failure.gjf"
    printf '\n%s\n' "$failure" >> "$failure.gjf"
    if "$root/bin/Gaussian" --local -c 2 -m 2 -C 'restart.chk .hidden' "$failure.gjf" > "$failure.stdout" 2> "$failure.stderr"; then
        echo "Expected failure: $failure"; exit 1
    fi
    grep -q 'TMPDIR contents retained' "$failure.stderr"
done
sed 's|%Chk=result.chk|%Chk=/outside/result.chk|' water.com > unsafe.inp
if "$root/bin/Gaussian" --local -c 2 -m 2 unsafe.inp >/dev/null 2>&1; then echo 'Expected unsafe checkpoint rejection'; exit 1; fi
if "$root/bin/Gaussian" --debug -n 2 water.com >/dev/null 2>&1; then echo 'Expected multi-node rejection'; exit 1; fi
QJOB_PROFILE=wcss "$root/bin/Gaussian" --debug water.com > wcss.sh
grep -q '16.C.02' wcss.sh
echo 'PASS: Gaussian resources, Link1, staging, unchanged input, checkpoint, error detection, scratch retention, WCSS profile'
