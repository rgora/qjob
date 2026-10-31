#!/usr/bin/env bash
set -euo pipefail
[[ $(id -u) == 0 ]] || { echo 'Run as root.' >&2; exit 1; }
root=$(cd -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd)
[[ $root == /opt/qjob && -f /etc/qjob/qjob.conf ]] || exit 1
for pair in Crest:crest Xtb:xtb; do
    cmd=${pair%:*}; app=${pair#*:}
    if [[ ! -e /etc/qjob/$app.conf ]]; then
        install -m 644 "$root/site/$app.conf.example" "/etc/qjob/$app.conf"
    fi
    link=/usr/local/bin/$cmd
    target=$root/bin/$cmd
    if [[ -L $link && $(readlink -- "$link") == "$target" ]]; then continue; fi
    if [[ -e $link || -L $link ]]; then mv -- "$link" "$link.$(date +%Y%m%d-%H%M%S)-$$.old"; fi
    ln -s -- "$target" "$link"
done
