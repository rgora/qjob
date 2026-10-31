#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/config" "$tmp/user"
export QJOB_CONFIG_DIR=$tmp/config QJOB_USER_CONFIG_DIR=$tmp/user
unset QJOB_PROFILE
printf 'original command\n' > "$tmp/bin/Gaussian"
bash "$root/site/install-commands.sh" --bin-dir "$tmp/bin" --profile wcss Gaussian qglobal
backup=$(find "$tmp/bin" -name 'Gaussian.qjob-backup-*')
[[ -n $backup && $(cat "$backup") == 'original command' ]]
"$tmp/bin/Gaussian" --help > "$tmp/help" 2>&1
grep -q 'qjob @ WCSS' "$tmp/help"
QJOB_PROFILE=local "$tmp/bin/Gaussian" --help > "$tmp/help" 2>&1
grep -q 'qjob @ local' "$tmp/help"
"$tmp/bin/qglobal" --help >/dev/null
count=$(find "$tmp/bin" -name '*.qjob-backup-*' | wc -l)
bash "$root/site/install-commands.sh" --bin-dir "$tmp/bin" --profile wcss Gaussian qglobal
[[ $(find "$tmp/bin" -name '*.qjob-backup-*' | wc -l) == "$count" ]]
bash "$root/site/install-commands.sh" --bin-dir "$tmp/links" Gaussian
[[ -L $tmp/links/Gaussian ]]
"$tmp/links/Gaussian" --help >/dev/null 2>&1
if bash "$root/site/install-commands.sh" --bin-dir "$tmp/rejected" Gaussian ../lib/qjob.sh >/dev/null 2>&1; then exit 1; fi
[[ ! -e $tmp/rejected ]]
echo 'PASS: profile selection, override, backups, idempotence, symlinks, portable qglobal, invalid selection'
