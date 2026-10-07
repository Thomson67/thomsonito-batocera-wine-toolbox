#!/usr/bin/env python3
"""Canonical runner names and transactional migration of Batocera references."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
import time


def canonical(name):
    exceptions = {"wine-tkg-v41": "TKG-v41", "ge-custom-v40": "GE-Custom-v40"}
    if name in exceptions:
        return exceptions[name]
    if name.upper().endswith("-UMU"):
        return name
    match = re.fullmatch(r'GE-Proton-?(\d+)-(\d+)(-UMU)?', name, re.I)
    if match:
        return f'GE-Proton-{match[1]}-{match[2]}{match[3] or ""}'
    match = re.fullmatch(r'wine-proton-(exp-)?(\d+(?:[.-]\d+)*)-amd64(?:-wow64)?', name, re.I)
    if match:
        return f'Vanilla-Proton-{match[1] or ""}{match[2]}'
    for pattern, family in (
        (r'wine-(\d+(?:\.\d+)+)-staging-tkg-amd64(?:-wow64)?', 'TKG'),
        (r'wine-tkg-(\d+(?:\.\d+)+)-amd64(?:-wow64)?', 'TKG'),
        (r'wine-(\d+(?:\.\d+)+)-amd64(?:-wow64)?', 'Vanilla'),
    ):
        match = re.fullmatch(pattern, name, re.I)
        if match:
            return f'{family}-{match[1]}'
    return name


def atomic(path, data):
    fd, tmp = tempfile.mkstemp(prefix='.uwt-runner-names-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as out:
            out.write(data)
            out.flush()
            os.fsync(out.fileno())
        if path.exists():
            shutil.copystat(path, tmp)
        os.replace(tmp, path)
    finally:
        Path(tmp).unlink(missing_ok=True)


def migrate(root, conf, bottles, state, backup_dir):
    root.mkdir(parents=True, exist_ok=True)
    backup_dir.mkdir(parents=True, exist_ok=True)
    with (backup_dir / '.runner-names.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        mounted = []
        try:
            for line in Path('/proc/self/mountinfo').read_text().splitlines():
                mount = re.sub(r'\\([0-7]{3})', lambda m: chr(int(m[1], 8)), line.split()[4])
                mounted.append(Path(mount))
        except OSError:
            pass
        moves = []
        mapping = {}
        destinations = set()
        for source in sorted(root.iterdir()):
            if not source.is_dir():
                continue
            name = canonical(source.name)
            if name == source.name:
                continue
            old_tree = bottles / source.name
            if any(m == source or source in m.parents or m == old_tree or old_tree in m.parents for m in mounted):
                print(f'Mounted runner/prefix, unchanged: {source.name}')
                continue
            target = root / name
            old_bottle, new_bottle = bottles / source.name, bottles / name
            if os.path.lexists(target) or target in destinations or (old_bottle.exists() and os.path.lexists(new_bottle)):
                print(f'Conflict, unchanged: {source.name} -> {name}')
                continue
            destinations.add(target)
            mapping[source.name] = name
            moves.append((source, target))
            if old_bottle.exists():
                moves.append((old_bottle, new_bottle))
        if not mapping:
            return
        originals = {}
        changes = {}
        if conf.exists():
            original = conf.read_bytes()
            text = original.decode('utf-8', errors='surrogateescape')
            pattern = re.compile(r'^(\s*(?:[^#\n=]+\.wine-runner|windows(?:\["[^"\n]+"\])?\.core)\s*=\s*)([^\r\n]*?)(\s*)$', re.M)
            def replace(match):
                value = match[2].strip()
                return match[1] + mapping.get(value, value) + match[3]
            updated = pattern.sub(replace, text).encode('utf-8', errors='surrogateescape')
            if updated != original:
                originals[conf] = original
                changes[conf] = updated
        if state.exists():
            original = state.read_bytes()
            data = json.loads(original)
            if data.get('runner') in mapping:
                data['runner'] = mapping[data['runner']]
                originals[state] = original
                changes[state] = (json.dumps(data, ensure_ascii=False, indent=2)+'\n').encode()
        stamp = time.strftime('%Y%m%d-%H%M%S') + f'-{time.time_ns()}'
        backup = backup_dir / ('runner-names-' + stamp)
        backup.mkdir()
        for path, original in originals.items():
            (backup / path.name).write_bytes(original)
        (backup / 'mapping.json').write_text(json.dumps(mapping, indent=2)+'\n')
        done = []
        written = []
        try:
            for source, target in moves:
                source.rename(target)
                done.append((source, target))
            for path, data in changes.items():
                atomic(path, data)
                written.append(path)
        except BaseException:
            for path in reversed(written):
                atomic(path, originals[path])
            for source, target in reversed(done):
                target.rename(source)
            raise
        for old, new in mapping.items():
            print(f'Renamed: {old} -> {new}')
        print(f'Reference backup: {backup}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    name = sub.add_parser('name')
    name.add_argument('runner')
    migration = sub.add_parser('migrate')
    for field in ('root', 'conf', 'bottles', 'state', 'backup_dir'):
        migration.add_argument(field, type=Path)
    args = parser.parse_args()
    if args.action == 'name':
        print(canonical(args.runner))
    else:
        migrate(args.root, args.conf, args.bottles, args.state, args.backup_dir)


if __name__ == '__main__':
    main()
