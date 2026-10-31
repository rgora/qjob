#!/usr/bin/env bash
set -euo pipefail
unset BASH_ENV QJOB_PROFILE
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
export QJOB_TEST_DIR=$test_dir QJOB_CONFIG_DIR=$test_dir/config QJOB_USER_CONFIG_DIR=$test_dir/user
mkdir -p "$test_dir"/{config,user,scratch,bin,work}
cat > "$test_dir/config/qjob.conf" <<CONF
partition=normal
storage=''
QJOB_STORAGE_GRES=false
QJOB_SCRATCH_ROOT='$test_dir/scratch'
clean_tmp=success
CONF
module() { :; }
export -f module
cat > "$test_dir/bin/xtb" <<'MOCK'
#!/bin/bash
[[ -f $1 && -f constraints.inp && $OMP_NUM_THREADS == 2 && $OPENBLAS_NUM_THREADS == 1 ]] || exit 12
printf '%s\n' "$TMPDIR" > "$QJOB_TEST_DIR/scratch-path"
printf '%s\n' "$@" > args.txt
printf result > xtbopt.xyz
printf hidden > .xtbrestart
echo 'mock completed'
[[ $1 != failure.xyz ]] || exit 7
MOCK
cp "$test_dir/bin/xtb" "$test_dir/bin/crest"
chmod +x "$test_dir/bin/"*
export PATH=$test_dir/bin:$PATH
cd "$test_dir/work"
printf xyz > water.xyz
printf aux > constraints.inp
for cmd in Xtb Crest; do
    "$root/bin/$cmd" --debug -c 2 water.xyz --opt > job.sh
    bash -n job.sh
    grep -q '^#SBATCH --cpus-per-task=2$' job.sh
    "$root/bin/$cmd" --local -c 2 -C constraints.inp water.xyz --opt > out.log 2> err.log
    result=$(find . -maxdepth 1 -type d -name 'water-qjob-*' | head -1)
    [[ -f $result/xtbopt.xyz && -f $result/.xtbrestart ]]
    grep -q '^--opt$' "$result/args.txt"
    grep -q 'mock completed' "$result/stdout.log"
    [[ ! -d $(cat "$test_dir/scratch-path") ]]
    rm -r "$result"
    printf xyz > failure.xyz
    if "$root/bin/$cmd" --local -c 2 -C constraints.inp failure.xyz > out.log 2> err.log; then exit 1; fi
    [[ -d $(cat "$test_dir/scratch-path") ]]
    grep -q 'exit status 7' err.log
    if "$root/bin/$cmd" --debug -n 2 water.xyz > /dev/null 2>&1; then exit 1; fi
    if "$root/bin/$cmd" --debug water.xyz -T 5 > /dev/null 2>&1; then exit 1; fi
done
echo 'PASS: Crest/Xtb staging, native options, threads, hidden results, failure and scratch retention'
