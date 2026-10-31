#!/usr/bin/env bash
# Run as root on bohr, bose or ligol, after cloning qjob to /opt/qjob.
set -euo pipefail
[[ $(id -u) == 0 ]] || { echo 'Run this installer as root.' >&2; exit 1; }
root=$(cd -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd)
[[ $root == /opt/qjob ]] || { echo 'Install the checkout at /opt/qjob first.' >&2; exit 1; }
host=$(hostname -s)
case $host in
    bohr) partition=normal; max_cores=32; max_memory=488 ;;
    bose) partition=bose; max_cores=32; max_memory=488 ;;
    ligol) partition=ligol; max_cores=16; max_memory=175 ;;
    *) echo "Unknown host: $host" >&2; exit 1 ;;
esac
install -d -o root -g root -m 755 /etc/qjob
install -d -o root -g root -m 1777 /scratch/qjob
if [[ ! -e /etc/qjob/qjob.conf ]]; then
    sed -e "s/^QJOB_SITE=.*/QJOB_SITE=$host/" \
        -e "s/^partition=.*/partition=$partition/" \
        -e "s/^QJOB_MAX_CORES=.*/QJOB_MAX_CORES=$max_cores/" \
        -e "s/^QJOB_MAX_MEMORY=.*/QJOB_MAX_MEMORY=$max_memory/" \
        "$root/site/qjob.conf.example" > /etc/qjob/qjob.conf
    chown root:root /etc/qjob/qjob.conf
    chmod 644 /etc/qjob/qjob.conf
fi
if [[ ! -e /etc/qjob/orca.conf ]]; then
    install -o root -g root -m 644 "$root/site/orca.conf.example" /etc/qjob/orca.conf
fi
link=/usr/local/bin/Orca
target=$root/bin/Orca
if [[ -L $link && $(readlink -- "$link") == "$target" ]]; then
    echo "$link already points to $target"
else
    if [[ -e $link || -L $link ]]; then
        backup=$link.old
        if [[ -e $backup || -L $backup ]]; then
            backup=$link.$(date +%Y%m%d-%H%M%S)-$$.old
        fi
        mv -- "$link" "$backup"
        echo "Saved $backup"
    fi
    ln -s -- "$target" "$link"
    echo "Installed $link -> $target"
fi
