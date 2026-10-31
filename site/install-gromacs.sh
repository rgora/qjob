#!/usr/bin/env bash
# Install from /opt/qjob after the shared qjob site configuration exists.
set -euo pipefail
[[ $(id -u) == 0 ]] || { echo 'Run this installer as root.' >&2; exit 1; }
root=$(cd -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd)
[[ $root == /opt/qjob && -f /etc/qjob/qjob.conf ]] || { echo 'Install shared qjob at /opt/qjob first.' >&2; exit 1; }
case $(hostname -s) in
    bohr|bose) config=gromacs.conf.example ;;
    ligol) config=gromacs-gpu.conf.example ;;
    *) echo 'Unknown host; configure GROMACS manually.' >&2; exit 1 ;;
esac
if [[ ! -e /etc/qjob/gromacs.conf ]]; then
    install -o root -g root -m 644 "$root/site/$config" /etc/qjob/gromacs.conf
    if [[ $(hostname -s) == ligol ]]; then
        # ligol currently has one GPU and no Slurm GPU GRES. Keep GPU jobs exclusive.
        printf '\nGROMACS_GPU_GRES=""\nGROMACS_GPU_EXCLUSIVE=true\n' >> /etc/qjob/gromacs.conf
    fi
fi
link=/usr/local/bin/Gromacs
target=$root/bin/Gromacs
if [[ -L $link && $(readlink -- "$link") == "$target" ]]; then
    echo "$link already points to $target"
else
    if [[ -e $link || -L $link ]]; then
        backup=$link.old
        [[ ! -e $backup && ! -L $backup ]] || backup=$link.$(date +%Y%m%d-%H%M%S)-$$.old
        mv -- "$link" "$backup"
        echo "Saved $backup"
    fi
    ln -s -- "$target" "$link"
    echo "Installed $link -> $target"
fi
