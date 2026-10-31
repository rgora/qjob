#!/usr/bin/env bash
set -euo pipefail
[[ $(id -u) == 0 ]] || { echo 'Run this installer as root.' >&2; exit 1; }
root=$(cd -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd)
[[ $root == /opt/qjob && -f /etc/qjob/qjob.conf ]] || { echo 'Install shared qjob at /opt/qjob first.' >&2; exit 1; }
if [[ ! -e /etc/qjob/openmolcas.conf ]]; then
    install -o root -g root -m 644 "$root/site/openmolcas.conf.example" /etc/qjob/openmolcas.conf
fi
link=/usr/local/bin/OpenMolcas
target=$root/bin/OpenMolcas
if [[ -L $link && $(readlink -- "$link") == "$target" ]]; then
    echo "$link already points to $target"
else
    if [[ -e $link || -L $link ]]; then
        backup=$link.$(date +%Y%m%d-%H%M%S)-$$.old
        mv -- "$link" "$backup"
        echo "Saved $backup"
    fi
    ln -s -- "$target" "$link"
    echo "Installed $link -> $target"
fi
