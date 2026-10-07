#!/usr/bin/env python3
"""Prepare an isolated game update; preserve launch directives and commit safely."""
import argparse
import json
import os
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path


def signature(path):
    st = path.stat()
    return [st.st_dev, st.st_ino, st.st_size, st.st_mtime_ns]


def save_json(path, data):
    tmp = path.with_name(path.name + '.tmp')
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    os.replace(tmp, path)


def directives(prefix):
    path = prefix / 'autorun.cmd'
    if path.is_symlink():
        raise ValueError('autorun.cmd must be an internal regular file')
    text = path.read_text(encoding='utf-8', errors='surrogateescape') if path.exists() else ''
    values = {}
    for line in text.splitlines():
        if '=' in line and not line.lstrip().startswith(('#', ';')):
            key, value = line.split('=', 1)
            values[key.strip().upper()] = value.strip()
    return text, values


def relative_path(value):
    value = value.strip().strip('"').replace('\\', '/').rstrip('/') or '.'
    path = Path(value)
    if path.is_absolute() or '..' in path.parts or any(c in value for c in '\t\n\r'):
        raise ValueError('save path must stay inside the prefix')
    return path


def validate_source(source, prefix):
    source = source.resolve(strict=True)
    prefix = prefix.resolve(strict=True)
    if not source.is_dir() or source == Path('/'):
        raise ValueError('choose a game-content directory')
    if source.is_relative_to(prefix) or prefix.is_relative_to(source):
        raise ValueError('source and working prefix must not overlap')
    if (source / 'drive_c').is_dir() and (source / 'system.reg').exists():
        raise ValueError('choose drive_c/game rather than a full Wine prefix')
    if not any(source.iterdir()):
        raise ValueError('the replacement directory is empty')
    for root, dirs, files in os.walk(source, followlinks=False):
        for name in dirs + files:
            path = Path(root) / name
            if path.is_symlink() and (Path(os.readlink(path)).is_absolute() or not path.resolve().is_relative_to(source)):
                raise ValueError(f'game-content link escapes the source: {path}')
    return source


def redirect_saves(prefix, old, new):
    """Never let the test prefix retain a link to the original game's saves."""
    old = old.resolve()
    for root, dirs, files in os.walk(prefix, followlinks=False):
        for name in dirs + files:
            path = Path(root) / name
            if path.is_symlink():
                target = path.resolve()
                if target.is_relative_to(old):
                    replacement = new / target.relative_to(old)
                    path.unlink()
                    path.symlink_to(replacement, target_is_directory=replacement.is_dir())


def prepare(prefix, source, archive, save_root, manifest):
    if archive.is_symlink() or not archive.is_file():
        raise ValueError('archive must be a regular file')
    if prefix.is_symlink() or not prefix.is_dir():
        raise ValueError('working prefix must be a real directory')
    root = prefix.resolve()
    game = root / 'drive_c/game'
    if (root / 'drive_c').is_symlink() or not game.is_dir() or game.is_symlink():
        raise ValueError('archive must contain an internal drive_c/game directory')
    source = validate_source(source, root)
    text, values = directives(root)
    savedir = relative_path(values.get('SAVEDIR', '')) if values.get('SAVEDIR') else None
    if savedir is not None and savedir != Path('.') and not (root / savedir).parent.resolve().is_relative_to(root):
        raise ValueError('save-directory parent escapes the prefix')
    original_save = save_root / archive.stem
    test_save = save_root / prefix.stem
    if test_save.exists() or test_save.is_symlink():
        raise ValueError('test-save destination already exists')
    if original_save.is_symlink():
        raise ValueError('original save directory must not be a symlink')
    if savedir is not None:
        location = root / savedir
        if location.is_symlink() and not location.resolve().is_relative_to(original_save.resolve()):
            raise ValueError('existing save link does not point to this game save directory')
    staging = root / '.uwt-update-game'
    old_game = root / '.uwt-update-old-game'
    embedded = root / '.uwt-update-embedded-save'
    if any(p.exists() or p.is_symlink() for p in (staging, old_game, embedded)):
        raise ValueError('an unfinished preparation is already present')
    data = {'archive': str(archive), 'archive_signature': signature(archive),
            'prefix': str(prefix), 'source': str(source),
            'original_save': str(original_save), 'test_save': str(test_save),
            'autorun': text, 'savedir': values.get('SAVEDIR', ''),
            'savefiles': values.get('SAVEFILES', '')}
    save_json(manifest, data)
    # Copy first; a failed copy must leave the extracted game intact.
    shutil.copytree(source, staging, symlinks=True)
    if original_save.is_dir():
        shutil.copytree(original_save, test_save, symlinks=False)
    else:
        test_save.mkdir(parents=True)
    if savedir is not None and savedir != Path('.'):
        location = root / savedir
        if location.is_relative_to(game) and location != game and location.is_dir() and not location.is_symlink():
            shutil.copytree(location, embedded, symlinks=True)
    game.rename(old_game)
    try:
        staging.rename(game)
        if embedded.exists():
            location = root / savedir
            if location.is_symlink() or not location.parent.resolve().is_relative_to(root):
                raise ValueError('replacement game redirects the savedir outside the prefix')
            shutil.copytree(embedded, location, symlinks=True, dirs_exist_ok=True)
    except Exception:
        if game.exists():
            shutil.rmtree(game)
        old_game.rename(game)
        raise
    redirect_saves(root, original_save, test_save)
    shutil.rmtree(old_game)
    if embedded.exists():
        shutil.rmtree(embedded)


def write_autorun(prefix, exe, savedir=None, savefiles=None):
    root = prefix.resolve()
    path = root / relative_path(exe)
    if not path.is_file() or not path.resolve().is_relative_to(root) or path.name.casefold() == 'autorun.cmd':
        raise ValueError('selected executable must be an internal game file')
    if '"' in path.name:
        raise ValueError('executable name contains a quote')
    text, values = directives(root)
    old_cmd = values.get('CMD', '')
    match = re.match(r'^"[^"]*"(.*)$', old_cmd)
    suffix = match.group(1) if match else (old_cmd.split(' ', 1)[1] if ' ' in old_cmd else '')
    if suffix and not suffix.startswith(' '):
        suffix = ' ' + suffix
    changes = {'DIR': path.parent.relative_to(root).as_posix(), 'CMD': f'"{path.name}"' + suffix}
    if savedir is not None:
        changes.update(SAVEDIR=savedir, SAVEFILES=savefiles or '')
    # Preserve ENV, arguments, language and every unrelated directive/comment.
    lines = [line for line in text.splitlines()
             if line.split('=', 1)[0].strip().upper() not in changes]
    lines += [f'{key}={value}' for key, value in changes.items() if value]
    tmp = root / 'autorun.cmd.uwt-update'
    tmp.write_text('\n'.join(lines) + '\n', encoding='utf-8', errors='surrogateescape')
    os.replace(tmp, root / 'autorun.cmd')


def detach_saves(prefix, save):
    """Make archive paths portable; do not change the external save copy."""
    save = save.resolve()
    for root, dirs, files in os.walk(prefix, followlinks=False):
        for name in dirs + files:
            path = Path(root) / name
            if not path.is_symlink():
                continue
            target = path.resolve()
            if not target.is_relative_to(save):
                continue
            if target.is_dir():
                path.unlink()
                path.mkdir()
            elif target.is_file():
                tmp = path.with_name(path.name + '.uwt-copy')
                shutil.copy2(target, tmp)
                path.unlink()
                os.replace(tmp, path)
            else:
                raise ValueError(f'unresolved save link: {path}')


def copy_config(conf, source, dest, backup_dir=None):
    if any(c in source + dest for c in '\n\r=#"'):
        raise ValueError('unsupported ROM name in configuration')
    if not conf.exists():
        return '__SYSTEM__'
    lines = conf.read_text(encoding='utf-8', errors='surrogateescape').splitlines(keepends=True)
    old = f'windows["{source}"].'
    new = f'windows["{dest}"].'
    selected = [line.strip()[len(old):] for line in lines if line.lstrip().startswith(old)]
    if backup_dir:
        backup_dir.mkdir(parents=True, exist_ok=True)
        backup = backup_dir / ('batocera.conf.update-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
        shutil.copy2(conf, backup)
    lines = [line for line in lines if not line.lstrip().startswith(new)]
    if lines and not lines[-1].endswith('\n'):
        lines[-1] += '\n'
    lines += [new + value + '\n' for value in selected]
    tmp = conf.with_name(conf.name + '.uwt-update')
    tmp.write_text(''.join(lines), encoding='utf-8', errors='surrogateescape')
    os.chmod(tmp, conf.stat().st_mode & 0o777)
    os.replace(tmp, conf)
    runners = [value.split('=', 1)[1] for value in selected if value.startswith('wine-runner=')]
    return runners[-1] if runners else '__SYSTEM__'


def commit(manifest, staged, prepared_save=None):
    data = json.loads(manifest.read_text())
    archive = Path(data['archive'])
    if archive.is_symlink() or signature(archive) != data['archive_signature']:
        raise ValueError('original archive changed since preparation; replacement refused')
    if staged.is_symlink() or not staged.is_file() or staged.parent.resolve() != archive.parent.resolve() or staged == archive:
        raise ValueError('validated replacement must be a distinct adjacent file')
    backup = archive.with_name(archive.stem + '.backup-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f') + archive.suffix)
    try:
        os.link(archive, backup)
    except OSError:
        shutil.copy2(archive, backup)
    original_save = Path(data['original_save'])
    save_backup = None
    if prepared_save is not None:
        if prepared_save.is_symlink() or not prepared_save.is_dir() or prepared_save.parent.resolve() != original_save.parent.resolve() or prepared_save == original_save:
            raise ValueError('prepared saves must be a distinct adjacent directory')
        if original_save.is_symlink():
            raise ValueError('original saves must not be a symlink')
        if original_save.exists():
            save_backup = original_save.with_name(original_save.name + '.backup-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
            original_save.rename(save_backup)
        try:
            prepared_save.rename(original_save)
            os.replace(staged, archive)
        except Exception:
            if original_save.exists():
                original_save.rename(prepared_save)
            if save_backup is not None:
                save_backup.rename(original_save)
            raise
    else:
        os.replace(staged, archive)
    data.update(committed=True, archive_backup=str(backup), save_backup=str(save_backup or ''))
    save_json(manifest, data)
    return backup


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sp = p.add_subparsers(dest='action', required=True)
    a = sp.add_parser('prepare')
    for name in ('prefix', 'source', 'archive', 'save_root', 'manifest'):
        a.add_argument(name, type=Path)
    a = sp.add_parser('autorun')
    a.add_argument('prefix', type=Path); a.add_argument('exe')
    a.add_argument('--savedir'); a.add_argument('--savefiles')
    a = sp.add_parser('detach')
    a.add_argument('prefix', type=Path); a.add_argument('save', type=Path)
    a = sp.add_parser('config')
    a.add_argument('conf', type=Path); a.add_argument('source'); a.add_argument('dest')
    a.add_argument('--backup-dir', type=Path)
    a = sp.add_parser('commit')
    a.add_argument('manifest', type=Path); a.add_argument('staged', type=Path); a.add_argument('--prepared-save', type=Path)
    a = sp.add_parser('value')
    a.add_argument('manifest', type=Path); a.add_argument('key')
    a = p.parse_args()
    try:
        if a.action == 'prepare': prepare(a.prefix, a.source, a.archive, a.save_root, a.manifest)
        elif a.action == 'autorun': write_autorun(a.prefix, a.exe, a.savedir, a.savefiles)
        elif a.action == 'detach': detach_saves(a.prefix, a.save)
        elif a.action == 'config': print(copy_config(a.conf, a.source, a.dest, a.backup_dir))
        elif a.action == 'commit': print(commit(a.manifest, a.staged, a.prepared_save))
        elif a.action == 'value': print(json.loads(a.manifest.read_text()).get(a.key, ''))
    except (OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)


if __name__ == '__main__':
    main()
