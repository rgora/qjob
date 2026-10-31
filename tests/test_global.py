#!/usr/bin/env python3
"""Fault-oriented dispatch tests, without SSH or a running Slurm controller."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('dispatch', Path(__file__).resolve().parents[1] / 'libexec/global.py')
d = importlib.util.module_from_spec(spec)
spec.loader.exec_module(d)


class DispatchTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.shared = self.home / 'shared'
        self.shared.mkdir()
        for name in ['a.inp', 'b.inp']:
            (self.shared / name).write_text('! HF\n')
        self.cfg = self.home / 'config.json'
        self.cfg.write_text(json.dumps(dict(shared_root=str(self.shared), targets=[
            dict(host='bohr', cores=32, memory_gb=488),
            dict(host='ligol', cores=16, memory_gb=175)])))
        self.addCleanup(patch.stopall)
        patch.object(d, 'CONFIG', self.cfg).start()
        patch.dict(os.environ, HOME=str(self.home)).start()

    def request(self, **kw):
        r = dict(app='orca', cwd=str(self.shared), cores=4, memory=8, nodes=1,
                 time='1', argv=['-p', 'global', 'a.inp'],
                 options=['-p', 'global'], inputs=['a.inp'])
        r.update(kw)
        return r

    def rpc(self, host, action, payload):
        if action == 'render':
            return subprocess.CompletedProcess([], 0, '#!/bin/bash\ntrue\n', '')
        if action == 'probe':
            stamp = time.strftime('%Y-%m-%dT%H:%M:%S', time.gmtime())
            return subprocess.CompletedProcess([], 0, 'sbatch: Job 1 to start at ' + stamp + ' using 8 processors', '')
        if action == 'launch':
            self.launches.append((host, payload))
            return subprocess.CompletedProcess([], 0, '123\n', '')
        self.fail(action)

    def enqueue(self, **kw):
        with patch.object(d, 'rpc', self.rpc):
            d.enqueue(self.request(**kw))

    def test_multiple_inputs_and_resource_filter(self):
        self.enqueue(inputs=['a.inp', 'b.inp'])
        records = d.jobs()
        self.assertEqual(len(records), 2)
        self.assertNotEqual(records[0]['id'], records[1]['id'])
        self.assertEqual({j['argv'][-1] for j in records}, {'a.inp', 'b.inp'})
        self.assertEqual([h['host'] for h in d.eligible(self.request(cores=32))], ['bohr'])

    def test_no_shared_paths_or_unmappable_options(self):
        for kw in [dict(cwd=str(self.home)), dict(cores=64),
                   dict(argv=['--slurmopt=--dependency=afterok:12']), dict(nodes=2)]:
            with self.assertRaises(ValueError):
                self.enqueue(**kw)
        self.assertEqual(d.jobs(), [])

    def test_wait_when_busy_and_submit_once_when_available(self):
        self.enqueue()
        self.launches = []
        original = self.rpc
        def busy(host, action, payload):
            if action == 'probe':
                stamp = time.strftime('%Y-%m-%dT%H:%M:%S', time.gmtime(time.time() + 3600))
                return subprocess.CompletedProcess([], 0, 'to start at ' + stamp, '')
            return original(host, action, payload)
        with patch.object(d, 'rpc', busy):
            d.tick()
        self.assertEqual(d.jobs()[0]['state'], 'PENDING')
        self.assertEqual(self.launches, [])
        with patch.object(d, 'rpc', self.rpc):
            d.tick()
        self.assertEqual(d.jobs()[0]['state'], 'DISPATCHED')
        self.assertEqual(d.jobs()[0]['jobid'], '123')
        self.assertEqual(len(self.launches), 1)

    def test_lost_submission_reply_never_causes_resubmission(self):
        self.enqueue()
        self.launches = []
        def lost(host, action, payload):
            if action == 'launch':
                self.launches.append(host)
                # State is already on disk before any remote submission.
                self.assertEqual(d.jobs()[0]['state'], 'SUBMITTING')
                return subprocess.CompletedProcess([], 255, '', 'connection lost')
            return self.rpc(host, action, payload)
        empty = subprocess.CompletedProcess([], 0, '', '')
        with patch.object(d, 'rpc', lost), patch.object(d, 'remote', return_value=empty):
            d.tick()
            d.tick()
            d.tick()
        self.assertEqual(d.jobs()[0]['state'], 'SUBMITTING')
        self.assertEqual(len(self.launches), 1)
        found = subprocess.CompletedProcess([], 0, '321|RUNNING\n', '')
        with patch.object(d, 'remote', return_value=found):
            d.tick()
        self.assertEqual(d.jobs()[0]['jobid'], '321')
        self.assertEqual(d.jobs()[0]['state'], 'DISPATCHED')

    def test_accounting_recovers_completed_job_after_restart(self):
        self.enqueue()
        j = d.jobs()[0]
        j.update(state='SUBMITTING', host='bohr')
        d.save(j)
        replies = [subprocess.CompletedProcess([], 0, '', ''),
                   subprocess.CompletedProcess([], 0, '123|COMPLETED|\n', '')]
        with patch.object(d, 'remote', side_effect=replies):
            d.tick()
        self.assertEqual(d.jobs()[0]['state'], 'COMPLETED')


if __name__ == '__main__':
    unittest.main()
