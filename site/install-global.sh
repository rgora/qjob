#!/usr/bin/env bash
# Install from a staged copy; leave running Slurm jobs and application code alone.
set -euo pipefail
[[ $(id -u) == 0 ]] || { echo 'Run as root.' >&2; exit 1; }
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
[[ -f /opt/qjob/lib/runtime.sh && -f /etc/qjob/qjob.conf ]] \
    || { echo 'Install and configure local qjob first.' >&2; exit 1; }
backup=/var/backups/qjob-global-$(date -u +%Y%m%dT%H%M%SZ)-$$
mkdir -p "$backup"
for f in lib/qjob.sh libexec/global.py bin/qglobal; do
    if [[ -e /opt/qjob/$f ]]; then
        mkdir -p "$backup/$(dirname "$f")"
        cp -a "/opt/qjob/$f" "$backup/$f"
    fi
done
cp -a /etc/qjob "$backup/etc-qjob"
if [[ -e /etc/systemd/system/qjob-global@.service ]]; then
    cp -a /etc/systemd/system/qjob-global@.service "$backup/"
fi
install -d -o root -g root -m 755 /opt/qjob/libexec /opt/qjob/bin
install -o root -g root -m 755 "$root/lib/qjob.sh" /opt/qjob/lib/qjob.sh
install -o root -g root -m 755 "$root/libexec/global.py" /opt/qjob/libexec/global.py
install -o root -g root -m 755 "$root/bin/qglobal" /opt/qjob/bin/qglobal
if [[ ! -e /etc/qjob/global.json ]]; then
    install -o root -g root -m 644 "$root/site/global.json.example" /etc/qjob/global.json
fi
if ! grep -q '^QJOB_DISPATCH_HOST=' /etc/qjob/qjob.conf; then
    printf '\n# Virtual global queue (independent local Slurm controllers).\nQJOB_DISPATCH_HOST=bose\n' >> /etc/qjob/qjob.conf
fi
if [[ -e /usr/local/bin/qglobal && ! -L /usr/local/bin/qglobal ]]; then
    cp -a /usr/local/bin/qglobal "$backup/qglobal-command"
fi
ln -sfn /opt/qjob/bin/qglobal /usr/local/bin/qglobal
if [[ $(hostname -s) == bose ]]; then
    install -o root -g root -m 644 "$root/site/qjob-global@.service" /etc/systemd/system/
    systemctl daemon-reload
fi
echo "Installed global dispatcher; backup: $backup"
echo 'On bose, enable each authorised user: systemctl enable --now qjob-global@USER'
