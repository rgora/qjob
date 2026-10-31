#!/usr/bin/env bash
# Install from /opt/qjob after the shared qjob site configuration exists.
set -euo pipefail
[[ $(id -u) == 0 ]] || { echo 'Run this installer as root.' >&2; exit 1; }
root=$(cd -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd)
[[ $root == /opt/qjob && -f /etc/qjob/qjob.conf ]] || { echo 'Install shared qjob at /opt/qjob first.' >&2; exit 1; }
case $(hostname -s) in
    bohr|bose|ligol) ;;
    *) echo 'Unknown host; configure OpenQP manually.' >&2; exit 1 ;;
esac
if [[ ! -e /etc/qjob/openqp.conf ]]; then
    install -o root -g root -m 644 "$root/site/openqp.conf.example" /etc/qjob/openqp.conf
fi
link=/usr/local/bin/Openqp
target=$root/bin/Openqp
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
