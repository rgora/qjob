#!/usr/bin/env bash
# Expose commands from this checkout; programs and site configuration are separate.
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
bin_dir=${HOME:?}/.local/bin
profile=''
usage() {
    echo 'Usage: bash site/install-commands.sh [--bin-dir DIR] [--profile wcss|local] [COMMAND ...]'
    echo 'Without COMMAND arguments, install all commands. Existing commands are backed up.'
    echo 'Without --profile, use symlinks and the existing /etc/qjob or user configuration.'
}
while (( $# )); do
    case $1 in
        --bin-dir) [[ $# -ge 2 && -n $2 ]] || { usage >&2; exit 2; }; bin_dir=$2; shift 2 ;;
        --profile) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; profile=$2
            [[ $profile == wcss || $profile == local ]] || { usage >&2; exit 2; }; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        -*) usage >&2; exit 2 ;;
        *) break ;;
    esac
done
commands=("$@")
if (( ${#commands[@]} == 0 )); then
    for source in "$root"/bin/*; do [[ ! -f $source || ! -x $source ]] || commands+=("${source##*/}"); done
fi
# Validate the whole selection before changing any installed command.
for command_name in "${commands[@]}"; do
    [[ $command_name =~ ^[[:alnum:]_][[:alnum:]_.+-]*$ && -x $root/bin/$command_name ]] \
        || { echo "Unknown qjob command: $command_name" >&2; exit 2; }
    [[ ! -d $bin_dir/$command_name ]] || { echo "Directory occupies $bin_dir/$command_name" >&2; exit 1; }
done
mkdir -p -- "$bin_dir"
for command_name in "${commands[@]}"; do
    target=$root/bin/$command_name
    destination=$bin_dir/$command_name
    if [[ -z $profile && -L $destination && $(readlink "$destination") == "$target" ]]; then continue; fi
    candidate=$(mktemp "$bin_dir/.qjob-install.XXXXXX")
    if [[ -n $profile ]]; then
        {
            echo '#!/usr/bin/env bash'
            printf 'export QJOB_PROFILE=${QJOB_PROFILE:-%s}\n' "$profile"
            printf 'exec %q "$@"\n' "$target"
        } > "$candidate"
        chmod 755 "$candidate"
        if [[ -f $destination && ! -L $destination ]] && cmp -s "$candidate" "$destination"; then
            rm -f -- "$candidate"; continue
        fi
    else
        rm -f -- "$candidate"
        ln -s -- "$target" "$candidate"
    fi
    if [[ -e $destination || -L $destination ]]; then
        backup=$destination.qjob-backup-$(date +%Y%m%d-%H%M%S)-$$
        mv -- "$destination" "$backup"
        echo "Saved $backup"
    fi
    mv -- "$candidate" "$destination"
    echo "Installed $destination"
done
