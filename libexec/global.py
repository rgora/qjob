#!/usr/bin/env python3
"""Persistent per-user dispatch queue; only the coordinator writes its spool.

Each submission attempt is journalled BEFORE contacting Slurm. An uncertain
reply is reconciled by a unique Slurm job name and is never blindly retried.
No root daemon, remote shell evaluation of input data, or cross-host database.
"""
import argparse
import contextlib
import datetime
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import socket
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
CONFIG = Path(os.environ.get('QJOB_GLOBAL_CONFIG', '/etc/qjob/global.json'))
REMOTE = '/opt/qjob/libexec/global.py'
TERMINAL = {'COMPLETED', 'FAILED', 'CANCELLED', 'TIMEOUT', 'OUT_OF_MEMORY',
            'NODE_FAIL', 'PREEMPTED', 'BOOT_FAIL', 'DEADLINE', 'REVOKED'}


def config():
    return json.loads(CONFIG.read_text())


def spool():
    p = Path.home() / '.local/state/qjob-global'
    p.mkdir(mode=0o700, parents=True, exist_ok=True)
    if p.stat().st_uid != os.getuid() or p.stat().st_mode & 0o077:
        raise ValueError('global spool must be owned by you and mode 0700')
    return p


def save(job):
    p = spool() / (job['id'] + '.json')
    fd, name = tempfile.mkstemp(dir=p.parent, prefix='.write-')
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(job, f, indent=2)
            f.flush()
            os.fsync(f.fileno())
        os.replace(name, p)
        d = os.open(p.parent, os.O_RDONLY)
        try:
            os.fsync(d)
        finally:
            os.close(d)
    finally:
        if os.path.exists(name):
            os.unlink(name)


@contextlib.contextmanager
def locked():
    with (spool() / '.lock').open('a') as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        yield


def jobs():
    return sorted((json.loads(p.read_text()) for p in spool().glob('*.json')),
                  key=lambda j: j['created'])


def remote(host, command, data=None, timeout=40):
    identity = Path.home() / '.ssh/qjob-global_ed25519'
    auth = ['-i', str(identity), '-o', 'IdentitiesOnly=yes'] if identity.exists() else []
    try:
        return subprocess.run(
            ['ssh', '-o', 'BatchMode=yes', '-o', 'ForwardAgent=no',
             '-o', 'ForwardX11=no', '-o', 'StrictHostKeyChecking=yes',
             '-o', 'ConnectTimeout=5'] + auth + [host, shlex.join(command)],
            input=data, text=True, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess([], 255, '', 'SSH command timed out')


def rpc(host, action, payload):
    return remote(host, ['/usr/bin/python3', REMOTE, action], json.dumps(payload))


def result(p):
    if p.returncode:
        raise ValueError((p.stderr or p.stdout).strip())
    return p.stdout


def validate(request):
    if request['app'] not in {'orca', 'qchem', 'turbomole', 'psi4oep', 'openqp'}:
        raise ValueError('unsupported application')
    for k in ('cores', 'memory', 'nodes'):
        if not re.fullmatch(r'[1-9][0-9]*', str(request[k])):
            raise ValueError(k + ' must be a positive integer')
        request[k] = int(request[k])
    if request['nodes'] != 1:
        raise ValueError('global supports one local node per job')
    cwd = Path(request['cwd']).resolve(strict=True)
    shared = Path(config()['shared_root']).resolve(strict=True)
    if not cwd.is_relative_to(shared):
        raise ValueError('global requires the working directory and inputs in /shared')
    request['cwd'] = str(cwd)
    argv = request['argv']
    if not isinstance(argv, list) or not all(isinstance(x, str) for x in argv):
        raise ValueError('invalid argument vector')
    # Arbitrary sbatch options, host pins and scheduler identities cannot be
    # safely mapped across independent controllers in this first version.
    forbidden = ('--slurmopt', '--nodelist', '--account', '--qos', '--reservation',
                 '--gres', '--local', '--background', '--exclusive', '--mail')
    short = ('-w', '-A', '-q')
    for arg in argv:
        if any(arg == x or arg.startswith(x + '=') for x in forbidden) or any(
                arg.startswith(x) for x in short):
            raise ValueError('global does not support ' + arg)
    return request


def eligible(request):
    return [h for h in config()['targets']
            if request['cores'] <= h['cores'] and request['memory'] <= h['memory_gb']]


def render(request):
    # Generate with the TARGET's site/application settings, freeze requested
    # resources, and interpret '-p global' as that target's default partition.
    env = os.environ.copy()
    env['QJOB_DISPATCH_TARGET'] = '1'
    for k in list(env):
        if k.startswith(('SBATCH_', 'SLURM_', 'QJOB_PROFILE', 'QJOB_CONFIG_DIR',
                         'QJOB_USER_CONFIG_DIR')):
            env.pop(k)
    cmd = ['bash', str(ROOT / 'lib/qjob.sh'), request['app'], '--debug',
           '-c', str(request['cores']), '-m', str(request['memory']),
           '-n', str(request['nodes']), '-t', request['time']] + request['argv']
    p = subprocess.run(cmd, cwd=request['cwd'], env=env, text=True,
                       capture_output=True, timeout=20)
    return result(p)


def endpoint(action, payload):
    if action == 'render':
        return render(payload)
    if action not in {'probe', 'launch'}:
        raise ValueError('unknown endpoint')
    # Endpoint data are commands from the same authenticated Unix user.
    script = payload['script']
    cmd = ['sbatch', '--chdir=' + payload['cwd']]
    if action == 'probe':
        cmd += ['--test-only']
    else:
        cmd += ['--parsable', '--job-name=' + payload['name'],
                '--comment=' + payload['name']]
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('SBATCH_', 'SLURM_'))}
    p = subprocess.run(cmd, input=script, cwd=payload['cwd'], env=env,
                       capture_output=True, text=True, timeout=25)
    if p.returncode:
        raise ValueError((p.stderr or p.stdout).strip())
    return p.stdout + (p.stderr if action == 'probe' else '')


def enqueue(request):
    request = validate(request)
    hosts = eligible(request)
    if not hosts:
        raise ValueError('no configured host fits these cores/memory requirements')
    # One record per file. Parse positional inputs using qjob itself below:
    # client provides file list separately after its existing option parser.
    inputs = request.pop('inputs')
    if not inputs:
        raise ValueError('no input files')
    records = []
    for filename in inputs:
        j = dict(request)
        path = (Path(request['cwd']) / filename).resolve(strict=True)
        if not path.is_relative_to(Path(config()['shared_root']).resolve()):
            raise ValueError('input must be in /shared: ' + filename)
        if not path.is_file():
            raise ValueError('input is not a file: ' + filename)
        j['cwd'] = str(path.parent)
        # The client sends options separately from positional input names.
        j['argv'] = request['options'] + [path.name]
        j.pop('options', None)
        errors = []
        for host in hosts:
            p = rpc(host['host'], 'render', j)
            if p.returncode == 0:
                break
            errors.append(host['host'] + ': ' + p.stderr.strip())
        else:
            raise ValueError('cannot prepare job on any target: ' + '; '.join(errors))
        j.update(id='global-' + uuid.uuid4().hex, created=time.time(),
                 state='PENDING', host='', jobid='', note='')
        records.append(j)
    with locked():
        for j in records:
            save(j)
    return '\n'.join('Queued ' + j['id'] + ' ' + j['cwd'] + '/' + j['argv'][-1]
                     for j in records) + '\n'


def preview(payload):
    validate(payload)
    output = []
    successes = 0
    for h in eligible(payload):
        p = rpc(h['host'], 'render', payload)
        successes += p.returncode == 0
        output.append('# target: ' + h['host'] + '\n' + (p.stdout or p.stderr))
    if not successes:
        raise ValueError('no target can prepare the job: ' + '\n'.join(output))
    return '\n'.join(output)


def reconcile(j):
    # Query active jobs AND accounting. A vanished job with no accounting
    # record remains SUBMITTING; never infer that it is safe to submit again.
    p = remote(j['host'], ['squeue', '--noheader', '--me', '--name=' + j['id'],
                           '--format=%i|%T'])
    if p.returncode:
        return
    rows = [x.strip().split('|') for x in p.stdout.splitlines() if '|' in x]
    if not rows:
        start = datetime.datetime.fromtimestamp(j['created'] - 60).strftime('%Y-%m-%dT%H:%M:%S')
        p = remote(j['host'], ['sacct', '-X', '-n', '-P', '--name=' + j['id'],
                               '--starttime=' + start, '--format=JobIDRaw,State'])
        if p.returncode:
            return
        rows = [x.strip().split('|')[:2] for x in p.stdout.splitlines() if '|' in x]
    if rows:
        ids = {r[0] for r in rows}
        if len(ids) != 1:
            j['note'] = 'multiple Slurm IDs found; manual inspection required'
        else:
            j['jobid'], state = rows[0]
            state = state.split()[0].rstrip('+')
            j['state'] = state if state in TERMINAL else 'DISPATCHED'
            j['note'] = state
        save(j)


def tick():
    with locked():
        for j in jobs():
            if j['state'] in {'SUBMITTING', 'DISPATCHED'}:
                reconcile(j)
                continue
            if j['state'] != 'PENDING':
                continue
            errors = []
            candidates = []
            for h in eligible(j):
                p = rpc(h['host'], 'render', j)
                if p.returncode:
                    errors.append(h['host'] + ': ' + p.stderr.strip())
                    continue
                script = p.stdout
                p = rpc(h['host'], 'probe', {'script': script, 'cwd': j['cwd']})
                match = re.search(r'to start at (\S+)', p.stdout)
                if p.returncode or not match:
                    errors.append(h['host'] + ': ' + (p.stderr or p.stdout).strip())
                    continue
                # Convert the timestamp on the target so host TZ differences
                # cannot change dispatch decisions. Probe uses TZ=UTC below.
                try:
                    start = datetime.datetime.fromisoformat(match[1]).replace(
                        tzinfo=datetime.timezone.utc).timestamp()
                except ValueError:
                    continue
                if start <= time.time() + 2:
                    candidates.append((start, h['host'], script))
            if not candidates:
                j['note'] = ('; '.join(errors) if errors else 'waiting for resources')[:2000]
                save(j)
                continue
            _, host, script = min(candidates, key=lambda c: c[0])
            j.update(state='SUBMITTING', host=host,
                     note='submission journalled; uncertain replies require reconciliation')
            save(j)
            p = rpc(host, 'launch', {'script': script, 'cwd': j['cwd'], 'name': j['id']})
            match = re.fullmatch(r'(\d+)(?:;[^\s]+)?\s*', p.stdout)
            if p.returncode == 0 and match:
                j.update(state='DISPATCHED', jobid=match[1], note='submitted')
            else:
                j['note'] = 'submission reply uncertain: ' + (p.stderr or p.stdout)[-1500:]
            save(j)


def client(args):
    payload = dict(app=args.app, cwd=args.cwd, cores=args.cores, memory=args.memory,
                   nodes=args.nodes, time=args.time, argv=args.argv)
    count = args.input_count
    if not count or count > len(args.argv):
        raise ValueError('invalid input count from qjob')
    payload.update(inputs=args.argv[-count:], options=args.argv[:-count])
    if args.action == 'preview':
        print(result(rpc(args.host, 'preview-request', payload)), end='')
    else:
        print(result(rpc(args.host, 'enqueue', payload)), end='')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['submit', 'preview', 'preview-request', 'enqueue', 'render',
                                         'probe', 'launch', 'worker', 'status', 'cancel'])
    parser.add_argument('--host')
    parser.add_argument('--app')
    parser.add_argument('--cwd')
    parser.add_argument('--cores')
    parser.add_argument('--memory')
    parser.add_argument('--nodes')
    parser.add_argument('--time')
    parser.add_argument('--input-count', type=int)
    parser.add_argument('--once', action='store_true')
    parser.add_argument('argv', nargs='*')
    raw = sys.argv[1:]
    if '--' in raw:
        index = raw.index('--')
        args = parser.parse_args(raw[:index])
        args.argv.extend(raw[index + 1:])
    else:
        args = parser.parse_args(raw)
    if args.action in {'status', 'cancel'} and socket.gethostname().split('.')[0] != config()['coordinator']:
        print(result(remote(config()['coordinator'],
                            ['/usr/bin/python3', REMOTE, args.action] + args.argv)), end='')
        return
    if args.action in {'submit', 'preview'}:
        client(args)
    elif args.action == 'preview-request':
        print(preview(json.load(sys.stdin)), end='')
    elif args.action == 'enqueue':
        print(enqueue(json.load(sys.stdin)), end='')
    elif args.action in {'render', 'probe', 'launch'}:
        print(endpoint(args.action, json.load(sys.stdin)), end='')
    elif args.action == 'worker':
        if socket.gethostname().split('.')[0] != config()['coordinator']:
            raise ValueError('worker must run on the configured coordinator')
        while True:
            try:
                tick()
            except Exception as e:
                print(str(e), file=sys.stderr, flush=True)
                if args.once:
                    raise
            if args.once:
                break
            time.sleep(config().get('interval', 20))
    elif args.action == 'status':
        with locked():
            for j in jobs():
                if j['state'] in {'SUBMITTING', 'DISPATCHED'}:
                    reconcile(j)
                print(j['id'], j['state'], j['host'] or '-', j['jobid'] or '-',
                      str(j['cores']) + 'c', str(j['memory']) + 'G', j['note'])
    elif args.action == 'cancel':
        if len(args.argv) != 1 or not re.fullmatch(r'global-[a-f0-9]{32}', args.argv[0]):
            raise ValueError('usage: qglobal cancel global-<id>')
        with locked():
            j = json.loads((spool() / (args.argv[0] + '.json')).read_text())
            if j['state'] in {'SUBMITTING', 'DISPATCHED'}:
                reconcile(j)
                if not j['jobid']:
                    raise ValueError('uncertain submission; inspect target before cancellation')
                # Match the globally unique name, never a possibly recycled
                # numeric ID from a different controller or an old record.
                result(remote(j['host'], ['scancel', '--name=' + j['id']]))
                j['note'] = 'cancellation requested'
            elif j['state'] == 'PENDING':
                j.update(state='CANCELLED', note='cancelled before dispatch')
            save(j)


if __name__ == '__main__':
    # Slurm's --test-only timestamps and diagnostics must be machine-readable.
    os.environ['LC_ALL'] = 'C'
    os.environ['TZ'] = 'UTC'
    time.tzset()
    try:
        main()
    except (ValueError, OSError, KeyError, subprocess.TimeoutExpired) as e:
        print('qglobal: ' + str(e), file=sys.stderr)
        sys.exit(1)
