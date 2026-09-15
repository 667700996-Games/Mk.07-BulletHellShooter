#!/usr/bin/env python3
"""Small fixtures verify cleanup, cancellation, ownership and publication safety."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

import build_workspace as w
import release_candidate as candidate

TOOLS = Path(__file__).resolve().parent


class LifecycleTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='pv-lifecycle-', dir=w.temp_parent())
        self.root = Path(self.tmp.name)
        self.env = {**os.environ, 'PYTHONPATH': str(TOOLS), 'PYTHONDONTWRITEBYTECODE': '1'}

    def tearDown(self):
        self.tmp.cleanup()

    def jobs(self):
        return list((w.layout(self.root) / 'jobs').iterdir())

    def worker(self, body):
        code = f'''import build_workspace as w, pathlib, time, os, sys
w.ROOT = pathlib.Path({str(self.root)!r})
def main():
 with w.Job(w.ROOT) as j:
  (w.ROOT / 'ready').write_text(str(j.path))
{body}
w.cli(main)
'''
        return subprocess.Popen([sys.executable, '-c', code], env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

    def ready(self):
        deadline = time.monotonic() + 8
        while not (self.root / 'ready').exists():
            if time.monotonic() > deadline:
                self.fail('worker did not become ready')
            time.sleep(.02)

    def finish(self, p):
        _, err = p.communicate(timeout=10)
        return err.decode()

    def test_success_and_exception(self):
        with w.Job(self.root) as job:
            (job.temp / 'work.bin').write_bytes(b'x')
        self.assertEqual(self.jobs(), [])
        with self.assertRaises(ValueError):
            with w.Job(self.root) as job:
                (job.temp / 'work.bin').write_bytes(b'x')
                raise ValueError('injected build failure')
        self.assertEqual(self.jobs(), [])

    @unittest.skipIf(os.name == 'nt', 'POSIX signals; Windows locking exercised by CI fixtures')
    def test_signals(self):
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            with self.subTest(signal=sig):
                p = self.worker('  time.sleep(60)')
                self.ready(); p.send_signal(sig); self.finish(p)
                self.assertEqual(p.returncode, 128 + sig)
                self.assertEqual(self.jobs(), [])
                (self.root / 'ready').unlink()

    @unittest.skipIf(os.name == 'nt', 'SIGKILL is POSIX-specific')
    def test_killed_process_recovered_and_live_job_protected(self):
        p = self.worker('  time.sleep(60)')
        try:
            self.ready(); before = self.jobs()
            w.recover(self.root)
            self.assertEqual(self.jobs(), before)
            p.kill(); self.finish(p)
            self.assertTrue(self.jobs())
            w.recover(self.root)
            self.assertEqual(self.jobs(), [])
        finally:
            if p.poll() is None:
                p.kill(); self.finish(p)

    @unittest.skipIf(os.name == 'nt', 'Inherited fd behavior is POSIX-specific')
    def test_killed_parent_preserves_running_child(self):
        child_code = f"from pathlib import Path; import time; Path({str(self.root / 'child-ready')!r}).touch(); time.sleep(1.5)"
        p = self.worker(f'  w.run([sys.executable, "-c", {child_code!r}])')
        try:
            self.ready()
            deadline = time.monotonic() + 8
            while not (self.root / 'child-ready').exists():
                self.assertLess(time.monotonic(), deadline); time.sleep(.02)
            p.kill(); p.wait(timeout=5)
            w.recover(self.root)
            self.assertTrue(self.jobs(), 'running child lost its workspace')
            # A child may remain a zombie under unusual container init processes;
            # recovery conservatively keeps such a PID until the OS reaps it.
            self.finish(p)
            deadline = time.monotonic() + 8
            while self.jobs() and time.monotonic() < deadline:
                w.recover(self.root); time.sleep(.05)
            self.assertEqual(self.jobs(), [])
        finally:
            if p.poll() is None:
                p.kill(); self.finish(p)

    def test_unknown_and_symlink_preserved(self):
        base = w.layout(self.root)
        unknown = base / 'jobs/unknown'
        unknown.mkdir(); (unknown / 'valuable').write_text('keep')
        w.recover(self.root)
        self.assertTrue((unknown / 'valuable').exists())
        outside = self.root / 'outside'; outside.mkdir()
        (outside / 'valuable').write_text('keep')
        if os.name != 'nt':
            (base / 'jobs/link').symlink_to(outside, target_is_directory=True)
            w.recover(self.root)
            self.assertTrue((outside / 'valuable').exists())

    def test_cleanup_error_warns_with_path(self):
        with mock.patch.object(w, 'safe_remove', side_effect=PermissionError('injected denial')), mock.patch.object(w, 'warn') as warning:
            with w.Job(self.root) as job:
                (job.temp / 'file').touch()
            self.assertTrue(any(str(job.path) in str(call) for call in warning.call_args_list))
        w.recover(self.root)
        self.assertEqual(self.jobs(), [])

    def test_development_retention_and_release_protection(self):
        output = self.root / 'build/development'; output.mkdir(parents=True)
        for n in range(5):
            p = output / str(n); p.mkdir()
            w.write_json(p / '.development.json', {'owner': w.OWNER, 'kind': 'development-success', 'id': p.name, 'completed_ns': n})
            (p / 'package.zip').write_bytes(b'package')
        (output / '0/KEEP.json').write_text('{"purpose":"debug","delete_after":"test"}')
        release = self.root / 'dist/release'; release.mkdir(parents=True)
        (release / 'symbols.pdb').write_bytes(b'preserved')
        unmanaged = output / 'unknown'; unmanaged.mkdir()
        w.retain_development(self.root)
        self.assertEqual(set(p.name for p in output.iterdir()), {'0','3','4','unknown'})
        self.assertEqual((release / 'symbols.pdb').read_bytes(), b'preserved')

    def test_bounded_logs(self):
        for n in range(12):
            with w.Job(self.root):
                with mock.patch('sys.stdout'):
                    rc = w.bounded_command([sys.executable, '-c', "import sys; sys.stdout.write('x' * (1024 * 1024 + 37)); sys.exit(3)"])
                self.assertEqual(rc, 3)
        logs = list((w.layout(self.root) / 'logs').glob('*.log'))
        self.assertEqual(len(logs), 10)
        self.assertTrue(all(p.stat().st_size == w.LIMIT for p in logs))

    def test_failed_repackage_preserves_previous_and_no_partial_publish(self):
        source = candidate.ROOT
        with w.Job(self.root) as job:
            fixture = job.temp / 'fixture'
            metadata = candidate._copy_contract_fixture(source, candidate.DEFAULT_METADATA, fixture)
            _, presets = candidate.load_and_validate_config(fixture, metadata)
            exports = job.temp / 'exports'
            candidate._create_fake_exports(exports, presets)
            dist = job.temp / 'dist'
            manifest = candidate.package_candidate(fixture, metadata, exports, dist)
            before = {p.name: p.read_bytes() for p in manifest.parent.iterdir()}
            with mock.patch.object(candidate, '_package_one', side_effect=RuntimeError('injected archive failure')):
                with self.assertRaises(RuntimeError):
                    candidate.package_candidate(fixture, metadata, exports, dist)
                with self.assertRaises(RuntimeError):
                    candidate.package_candidate(fixture, metadata, exports, job.temp / 'new-dist')
            self.assertEqual(before, {p.name: p.read_bytes() for p in manifest.parent.iterdir()})
            self.assertEqual(list((job.temp / 'new-dist').iterdir()), [])
            # Same candidate ID with changed bytes must fail without replacing it.
            candidate._artifact_path(exports, presets[0]).write_bytes(b'changed')
            with self.assertRaises(candidate.ReleaseError):
                candidate.package_candidate(fixture, metadata, exports, dist)
            self.assertEqual(before, {p.name: p.read_bytes() for p in manifest.parent.iterdir()})


def main():
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(LifecycleTest)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == '__main__':
    raise SystemExit(w.cli(main))
