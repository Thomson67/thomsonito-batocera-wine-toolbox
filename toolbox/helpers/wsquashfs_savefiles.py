#!/usr/bin/env python3
"""Discover and externalize only explicitly selected individual game saves."""
import argparse
import json
import os
from pathlib import Path
import shutil
import sys

BINARY_EXT = {'.exe', '.dll', '.so', '.pak', '.ucas', '.utoc', '.vpk', '.mp4', '.ogg', '.wav', '.dds', '.png', '.jpg', '.zip', '.7z'}


def game_roots(prefix):
    root = prefix.resolve()
    candidates = [root / 'drive_c/game']
    try:
        for line in (root / 'autorun.cmd').read_text().splitlines():
            if line.startswith('DIR='):
                candidates.append(root / line[4:].strip().strip('"').replace('\\', '/'))
    except OSError:
        pass
    return list(dict.fromkeys(p for p in candidates if p.is_dir() and not p.is_symlink()
                              and p.resolve().is_relative_to(root) and p != root
                              and p != root / "drive_c"
                              and not any(part.casefold() in ("windows", "users", "dosdevices")
                                          for part in p.relative_to(root).parts)))


def valid_name(name):
    return name not in ('', '.', '..') and not any(c in name for c in '/\\;\t\n\r')


def inventory(prefix):
    root = prefix.resolve()
    result = {}
    for base in game_roots(root):
        for folder, dirs, files in os.walk(base, followlinks=False):
            dirs[:] = [d for d in dirs if not (Path(folder) / d).is_symlink()
                       and d.casefold() not in ('windows', '_commonredist')]
            for name in files:
                if not valid_name(name) or Path(name).suffix.casefold() in BINARY_EXT:
                    continue
                path = Path(folder) / name
                try:
                    if not path.is_file():
                        continue
                    stat = path.stat()
                    result[path.relative_to(root).as_posix()] = [stat.st_mtime_ns, stat.st_size]
                except OSError:
                    continue
    return result


def checked_files(prefix, folder, names, save_root):
    root = prefix.resolve()
    parent = root / folder
    if not parent.is_dir() or parent.is_symlink() or not parent.resolve().is_relative_to(root):
        raise ValueError('save parent must be an internal directory')
    if not any(parent.resolve().is_relative_to(base.resolve()) for base in game_roots(root)):
        raise ValueError('save parent must be inside the game directory')
    if not names or len(set(names)) != len(names):
        raise ValueError('empty or duplicate selection')
    for name in names:
        if not valid_name(name) or Path(name).suffix.casefold() in BINARY_EXT:
            raise ValueError('invalid save filename')
        path = parent / name
        target = path.resolve()
        if not path.is_file() or (not target.is_relative_to(root)
                                 and not target.is_relative_to(save_root.resolve())):
            raise ValueError('missing file or unsupported external link')
    return parent


def stage(prefix, folder, names, save_root, output):
    parent = checked_files(prefix, folder, names, save_root)
    for name in names:
        shutil.copyfile(parent / name, output / name, follow_symlinks=True)


def remove_selected(prefix, folder, names, save_root):
    root = prefix.resolve()
    parent = root / folder
    if (not parent.is_dir() or parent.is_symlink()
            or not parent.resolve().is_relative_to(root)
            or not any(parent.resolve().is_relative_to(base.resolve()) for base in game_roots(root))):
        raise ValueError('save parent must remain inside the game directory')
    paths = []
    for name in names:
        if not valid_name(name) or Path(name).suffix.casefold() in BINARY_EXT:
            raise ValueError('invalid save filename')
        path = parent / name
        target = path.resolve()
        if path.is_dir() or (not target.is_relative_to(root)
                            and not target.is_relative_to(save_root.resolve())):
            raise ValueError('unsupported save path')
        paths.append(path)
    for path in paths:
        path.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['list', 'stage', 'remove'])
    parser.add_argument('prefix', type=Path)
    parser.add_argument('before', type=Path)
    parser.add_argument('--folder', default='')
    parser.add_argument('--save-root', type=Path, default=Path('/userdata/saves/windows'))
    parser.add_argument('--staged', type=Path)
    parser.add_argument('names', nargs='*')
    args = parser.parse_intermixed_args()
    if args.command == 'list':
        before = json.loads(args.before.read_text()).get('__game_files__', {})
        for rel, state in sorted(inventory(args.prefix).items()):
            print(f'{rel}\t{state[1]}\t{int(rel not in before or before[rel] != state)}')
    elif args.command == 'stage':
        stage(args.prefix, args.folder, args.names, args.save_root, args.staged)
    else:
        remove_selected(args.prefix, args.folder, args.names, args.save_root)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
