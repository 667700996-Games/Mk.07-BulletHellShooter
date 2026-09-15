#!/usr/bin/env python3
"""Owned build workspaces, process leases, bounded logs and safe retention."""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import functools
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
OWNER = 'psychic-vector-build-workspace-v1'
LIMIT = 1024 * 1024
_active = None
_publish_depth = 0


def warn(path, exc):
    print(f'BUILD_CLEANUP_WARNING remaining={path}: {exc}', file=sys.stderr, flush=True)


def regular(path):
    return path.is_file() and not path.is_symlink()


def write_json(path, value):
    # Registry writes are protected by the guard. Corrupt metadata fails closed.
    with path.open('w', encoding='utf-8') as f:
        json.dump(value, f, sort_keys=True)
        f.flush()
        os.fsync(f.fileno())


class Lock:
    def __init__(self, path, blocking=True):
        if path.is_symlink():
            raise RuntimeError(f'unsafe lock: {path}')
        self.file = path.open('a+b')
        try:
            if os.name == 'nt':
                import msvcrt
                self.file.seek(0)
                if not self.file.read(1):
                    self.file.write(b'0'); self.file.flush()
                self.file.seek(0)
                while True:
                    try:
                        msvcrt.locking(self.file.fileno(), msvcrt.LK_NBLCK, 1)
                        break
                    except OSError:
                        if not blocking:
                            raise
                        time.sleep(.05)
            else:
                import fcntl
                fcntl.flock(self.file, fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB))
        except BaseException:
            self.file.close()
            raise

    def close(self):
        # Closing (not LOCK_UN) keeps inherited POSIX leases alive in children.
        self.file.close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()


def layout(root=ROOT):
    root = Path(root).resolve()
    for path in [root / 'build', root / 'build/.work']:
        if path.is_symlink():
            raise RuntimeError(f'unsafe workspace: {path}')
        path.mkdir(exist_ok=True)
    base = root / 'build/.work'
    with Lock(base / '.init.lock'):
        marker = base / 'owner.json'
        if marker.exists():
            if not regular(marker) or json.loads(marker.read_text()) != {'owner': OWNER, 'root': str(root)}:
                raise RuntimeError(f'unknown workspace owner: {base}')
        else:
            if set(p.name for p in base.iterdir()) != {'.init.lock'}:
                raise RuntimeError(f'refusing to adopt nonempty workspace: {base}')
            write_json(marker, {'owner': OWNER, 'root': str(root)})
        for name in ['jobs', 'logs']:
            p = base / name
            if p.is_symlink():
                raise RuntimeError(f'unsafe workspace directory: {p}')
            p.mkdir(exist_ok=True)
    return base


def alive(pid):
    if not isinstance(pid, int) or pid <= 0:
        return True
    if os.name == 'nt':
        import ctypes
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel.OpenProcess.restype = ctypes.c_void_p
        handle = kernel.OpenProcess(0x1000, False, pid)
        if not handle:
            return ctypes.get_last_error() != 87  # Access denied is not dead.
        code = ctypes.c_ulong()
        ok = kernel.GetExitCodeProcess(ctypes.c_void_p(handle), ctypes.byref(code))
        kernel.CloseHandle(ctypes.c_void_p(handle))
        return not ok or code.value == 259
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def safe_remove(path):
    if path.is_symlink() or not path.is_dir():
        raise RuntimeError(f'not an owned directory: {path}')
    # Never follow links or junctions, including those left by an external tool.
    for parent, dirs, files in os.walk(path, followlinks=False):
        for name in dirs + files:
            p = Path(parent) / name
            if p.is_symlink() or (hasattr(p, 'is_junction') and p.is_junction()):
                raise RuntimeError(f'link found in workspace: {p}')
    shutil.rmtree(path)


def _reap(base):
    for path in (base / 'jobs').iterdir():
        try:
            if path.is_symlink() or not path.is_dir() or not regular(path / 'owner.json'):
                warn(path, 'unknown ownership; preserved'); continue
            state = json.loads((path / 'owner.json').read_text())
            if state.get('owner') != OWNER or state.get('id') != path.name:
                warn(path, 'invalid ownership; preserved'); continue
            try:
                lease = Lock(path / 'lease', blocking=False)
            except OSError:
                continue
            with lease:
                if (not state.get('finished') and alive(state['pid'])) or any(alive(pid) for pid in state.get('children', [])):
                    continue
                if state.get('spawn_pending') and os.name == 'nt':
                    warn(path, 'interrupted Windows child registration; inspect before manual recovery'); continue
            # Guard excludes other collectors; no process can join an abandoned job.
            safe_remove(path)
        except (OSError, ValueError, KeyError, RuntimeError) as exc:
            warn(path, exc)


def recover(root=ROOT):
    base = layout(root)
    with Lock(base / 'guard'):
        _reap(base)
        logs = sorted((p for p in (base / 'logs').glob('*.log') if regular(p)), key=lambda p: p.name)
        for p in logs[:-10]:
            try:
                p.unlink()
            except OSError as exc:
                warn(p, exc)


class Job:
    def __init__(self, root=ROOT):
        self.root = Path(root).resolve()

    def __enter__(self):
        global _active
        self.previous = _active
        self.base = layout(self.root)
        with Lock(self.base / 'guard'):
            _reap(self.base)
            self.id = uuid.uuid4().hex
            self.path = self.base / 'jobs' / self.id
            self.path.mkdir()
            self.lease = Lock(self.path / 'lease')
            self.state = {'owner': OWNER, 'id': self.id, 'pid': os.getpid(), 'children': [], 'spawn_pending': False}
            write_json(self.path / 'owner.json', self.state)
        self.extra_fds = []
        self.temp = self.path / 'tmp'
        self.temp.mkdir()
        self.old_env = {key: os.environ.get(key) for key in ('TMPDIR', 'TMP', 'TEMP', 'PYTHONDONTWRITEBYTECODE')}
        for key in ('TMPDIR', 'TMP', 'TEMP'):
            os.environ[key] = str(self.temp)
        os.environ['PYTHONDONTWRITEBYTECODE'] = '1'
        _active = self
        return self

    def __exit__(self, *args):
        global _active
        _active = self.previous
        for key, value in self.old_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        with Lock(self.base / 'guard'):
            self.state['finished'] = True  # Children still require checks.
            write_json(self.path / 'owner.json', self.state)
            self.lease.close()
            try:
                if any(alive(pid) for pid in self.state['children']):
                    warn(self.path, 'child still running; deferred cleanup')
                else:
                    with Lock(self.path / 'lease', blocking=False):
                        pass
                    safe_remove(self.path)
            except (OSError, RuntimeError) as exc:
                warn(self.path, exc)
        recover(self.root)


@contextmanager
def session():
    if _active is not None:
        yield _active
    else:
        with Job() as job:
            yield job


def serialized(fn):
    @functools.wraps(fn)
    def wrapped(*args, **kwargs):
        global _publish_depth
        with session() as job:
            if _publish_depth:
                return fn(*args, **kwargs)
            with Lock(job.base / 'publish.lock'):
                _publish_depth += 1
                try:
                    return fn(*args, **kwargs)
                finally:
                    _publish_depth -= 1
    return wrapped


def run(command, **kwargs):
    """subprocess.run with durable child registration and inherited POSIX lease."""
    with session() as job:
        timeout = kwargs.pop('timeout', None)
        check = kwargs.pop('check', False)
        capture = kwargs.pop('capture_output', False)
        input_data = kwargs.pop('input', None)
        if capture:
            kwargs.update(stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if input_data is not None:
            kwargs['stdin'] = subprocess.PIPE
        with Lock(job.base / 'guard'):
            job.state['spawn_pending'] = True
            write_json(job.path / 'owner.json', job.state)
            if os.name != 'nt':
                kwargs['pass_fds'] = (*kwargs.get('pass_fds', ()), job.lease.file.fileno(), *job.extra_fds)
                kwargs['start_new_session'] = True
            try:
                process = subprocess.Popen(command, **kwargs)
            except BaseException:
                job.state['spawn_pending'] = False
                write_json(job.path / 'owner.json', job.state)
                raise
            job.state['children'].append(process.pid)
            job.state['spawn_pending'] = False
            write_json(job.path / 'owner.json', job.state)
        try:
            stdout, stderr = process.communicate(input_data, timeout=timeout)
        except BaseException:
            if process.poll() is None:
                if os.name == 'nt':
                    process.terminate()
                else:
                    os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    if os.name == 'nt':
                        process.kill()
                    else:
                        os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
            raise
        finally:
            with Lock(job.base / 'guard'):
                if process.poll() is not None:
                    job.state['children'].remove(process.pid)
                    write_json(job.path / 'owner.json', job.state)
        result = subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
        if check:
            result.check_returncode()
        return result


def temp_parent(requested=None):
    if _active is None:
        raise RuntimeError('temporary files require build_workspace.session() or cli()')
    if requested is not None and Path(requested).stat().st_dev != _active.temp.stat().st_dev:
        raise RuntimeError(f'atomic output must share workspace filesystem: {requested}')
    return _active.temp


def bounded_command(command):
    with session() as job:
        buffer = bytearray()
        read_fd, write_fd = os.pipe()
        def consume():
            with os.fdopen(read_fd, 'rb') as stream:
                while chunk := stream.read(4096):
                    buffer.extend(chunk)
                    del buffer[:-LIMIT]
                    try:
                        sys.stdout.buffer.write(chunk); sys.stdout.buffer.flush()
                    except (BrokenPipeError, AttributeError):
                        pass
        reader = threading.Thread(target=consume, daemon=True)
        reader.start()
        try:
            return run(command, stdout=write_fd, stderr=subprocess.STDOUT).returncode
        finally:
            os.close(write_fd)
            reader.join(timeout=5)
            if reader.is_alive():
                warn(job.path, 'output pipe remains open in a descendant')
            path = job.base / 'logs' / f'{time.time_ns():020d}-{job.id}.log'
            with Lock(job.base / 'guard'):
                path.write_bytes(bytes(buffer[-LIMIT:]))


def cli(main):
    def interrupted(signum, frame):
        raise SystemExit(128 + signum)
    old = {}
    for name in ('SIGINT', 'SIGTERM', 'SIGHUP', 'SIGBREAK'):
        sig = getattr(signal, name, None)
        if sig is not None:
            old[sig] = signal.signal(sig, interrupted)
    try:
        with session():
            return main()
    finally:
        for sig, handler in old.items():
            signal.signal(sig, handler)


def retain_development(root=ROOT):
    """Only explicit successful development runs; releases/evidence never enter here."""
    base = layout(root)
    output = Path(root) / 'build/development'
    if not output.exists():
        return
    if output.is_symlink():
        raise RuntimeError(f'unsafe development output: {output}')
    with Lock(base / 'publish.lock'):
        runs = []
        for p in output.iterdir():
            try:
                marker = p / '.development.json'
                if p.is_symlink() or not p.is_dir() or not regular(marker):
                    warn(p, 'unmanaged development output; preserved'); continue
                state = json.loads(marker.read_text())
                if state.get('owner') != OWNER or state.get('kind') != 'development-success' or state.get('id') != p.name:
                    warn(p, 'unknown development marker; preserved'); continue
                if (p / 'KEEP.json').exists():
                    continue
                runs.append((state['completed_ns'], p))
            except (OSError, ValueError, KeyError) as exc:
                warn(p, exc)
        for _, p in sorted(runs, reverse=True)[2:]:
            try:
                safe_remove(p)
            except (OSError, RuntimeError) as exc:
                warn(p, exc)


@contextmanager
def engine_lock():
    with session() as job:
        with Lock(job.base / 'engine.lock') as lock:
            job.extra_fds.append(lock.file.fileno())
            try:
                yield
            finally:
                job.extra_fds.remove(lock.file.fileno())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    sub.add_parser('recover')
    cmd = sub.add_parser('run')
    cmd.add_argument('--engine', action='store_true')
    cmd.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.action == 'recover':
        recover(); retain_development(); return 0
    command = args.command
    if command[:1] == ['--']:
        command = command[1:]
    if not command:
        parser.error('run requires a command')
    if args.engine:
        with engine_lock():
            return bounded_command(command)
    return bounded_command(command)


if __name__ == '__main__':
    raise SystemExit(cli(main))
