#!/usr/bin/env python3
"""Export, audit and smoke-test desktop packages in an owned disposable job.

Default: retain the last two successful development package sets.
--release: publish a verified immutable candidate to dist (never auto-pruned).
"""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import platform
import sys
import time

import build_workspace as workspace
import export_artifact_audit as audit
import native_candidate_smoke as native
import release_candidate as candidate


@workspace.serialized
def publish(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_symlink():
        raise RuntimeError(f'unsafe publish destination: {destination}')
    if destination.exists():
        old = {p.name: candidate._sha256_file(p) for p in destination.iterdir()}
        new = {p.name: candidate._sha256_file(p) for p in source.iterdir()}
        if old != new:
            raise RuntimeError(f'immutable release differs; use a new build number: {destination}')
    else:
        os.replace(source, destination)


def build(release=False):
    root = workspace.ROOT
    metadata_path = root / 'release/release_metadata.json'
    metadata, presets = candidate.load_and_validate_config(root, metadata_path)
    godot = os.environ.get('GODOT_BIN', 'godot')
    version = workspace.run([godot, '--version'], capture_output=True, text=True, check=True).stdout.strip()
    if not version.startswith(metadata['godot_version'] + '.'):
        raise RuntimeError(f'Godot version differs from release contract: {version}')
    with workspace.session() as job, workspace.engine_lock():
        build_root = job.temp / 'exports'
        stage = job.temp / 'packages'
        workspace.run([godot, '--headless', '--editor', '--path', str(root), '--log-file', str(job.temp / 'import.log'), '--quit'], check=True)
        for preset in presets:
            output = candidate._artifact_path(build_root, preset)
            output.parent.mkdir(parents=True, exist_ok=True)
            workspace.run([godot, '--headless', '--path', str(root), '--log-file', str(job.temp / (preset['slug'] + '.log')), "--export-release", preset['name'], str(output)], check=True)
        audit.audit_exports(metadata_path, build_root)
        manifest = candidate.package_candidate(root, metadata_path, build_root, stage)
        candidate.verify_candidate(root, metadata_path, manifest.parent)
        native_preset = {'Darwin': 'macOS', 'Linux': 'Linux', 'Windows': 'Windows Desktop'}[platform.system()]
        native.run_native_smoke(root, metadata_path, stage, native_preset, 'quick')
        if release:
            destination = root / 'dist' / manifest.parent.name
            publish(manifest.parent, destination)
        else:
            destination = root / 'build/development' / job.id
            workspace.write_json(stage / '.development.json', {'owner': workspace.OWNER, 'kind': 'development-success', 'id': job.id, 'completed_ns': time.time_ns()})
            with workspace.Lock(job.base / 'publish.lock'):
                destination.parent.mkdir(parents=True, exist_ok=True)
                if destination.parent.is_symlink():
                    raise RuntimeError(f'unsafe development output: {destination.parent}')
                os.replace(stage, destination)
        workspace.retain_development(root)
        print(f'DESKTOP_BUILD_OK kind={"release" if release else "development"} output={destination}', flush=True)
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release', action='store_true')
    parser.add_argument('--worker', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if not args.worker:
        return workspace.bounded_command([sys.executable, str(Path(__file__).resolve()), '--worker', *(['--release'] if args.release else [])])
    try:
        return build(args.release)
    except Exception as exc:
        print(f'DESKTOP_BUILD_FAILED: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(workspace.cli(main))
