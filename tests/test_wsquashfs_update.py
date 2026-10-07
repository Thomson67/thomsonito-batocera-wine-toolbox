"""Update transaction and save isolation regressions, using temporary paths only."""
import json
import os
import subprocess
import shlex
import shutil
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'toolbox/helpers'))
import wsquashfs_update as update
import wsquashfs_integrity as integrity

class UpdateTests(unittest.TestCase):
    def setUp(self):
        t = tempfile.TemporaryDirectory(); self.addCleanup(t.cleanup)
        self.base = Path(t.name)
        self.archive = self.base / 'Game.wsquashfs'; self.archive.write_bytes(b'old archive')
        self.prefix = self.base / 'Game.update-test.wine'
        self.game = self.prefix / 'drive_c/game'; self.game.mkdir(parents=True)
        (self.game / 'old.exe').write_bytes(b'old')
        (self.prefix / 'autorun.cmd').write_text('ENV=FOO=bar\nLANG=fr_FR\nDIR=drive_c/game\nCMD="old.exe" --launch\nSAVEDIR=drive_c/users/root/Saved\n')
        self.source = self.base / 'replacement'; self.source.mkdir()
        (self.source / 'new.exe').write_bytes(b'new')
        self.saves = self.base / 'saves'; self.original_save = self.saves / 'Game'
        self.original_save.mkdir(parents=True)
        (self.original_save / 'slot').write_text('original')
        self.manifest = self.base / 'metadata.json'

    def prepare(self):
        update.prepare(self.prefix, self.source, self.archive, self.saves, self.manifest)
        return self.saves / self.prefix.stem

    def test_save_isolation_and_launch_arguments(self):
        save_link = self.prefix / 'drive_c/users/root/Saved'
        save_link.parent.mkdir(parents=True); save_link.symlink_to(self.original_save)
        test_save = self.prepare()
        self.assertEqual(save_link.resolve(), test_save)
        (save_link / 'slot').write_text('tested')
        self.assertEqual((self.original_save / 'slot').read_text(), 'original')
        self.assertEqual((self.source / 'new.exe').read_bytes(), b'new')
        self.assertFalse((self.game / 'old.exe').exists())
        update.write_autorun(self.prefix, 'drive_c/game/new.exe')
        autorun = (self.prefix / 'autorun.cmd').read_text()
        for line in ('ENV=FOO=bar', 'LANG=fr_FR', 'CMD="new.exe" --launch'):
            self.assertIn(line, autorun)
        update.detach_saves(self.prefix, test_save)
        self.assertFalse(save_link.is_symlink()); self.assertEqual(list(save_link.iterdir()), [])
        self.assertEqual((test_save / 'slot').read_text(), 'tested')

    def test_copy_failure_preserves_game(self):
        with patch.object(update.shutil, 'copytree', side_effect=OSError('disk full')):
            with self.assertRaises(OSError): self.prepare()
        self.assertEqual((self.game / 'old.exe').read_bytes(), b'old')
        self.assertEqual(self.archive.read_bytes(), b'old archive')

    def test_embedded_save_survives_game_replacement(self):
        (self.prefix / 'autorun.cmd').write_text('SAVEDIR=drive_c/game/Saved\n')
        (self.game / 'Saved').mkdir(); (self.game / 'Saved/slot').write_text('embedded')
        self.prepare()
        self.assertEqual((self.game / 'Saved/slot').read_text(), 'embedded')

    def test_registry_links_become_portable_files(self):
        (self.original_save / 'user.reg').write_text('registry')
        (self.prefix / 'autorun.cmd').write_text('SAVEDIR=.\nSAVEFILES=user.reg\n')
        (self.prefix / 'user.reg').symlink_to(self.original_save / 'user.reg')
        test_save = self.prepare()
        update.detach_saves(self.prefix, test_save)
        self.assertFalse((self.prefix / 'user.reg').is_symlink())
        self.assertEqual((self.prefix / 'user.reg').read_text(), 'registry')

    def test_unsafe_sources_are_refused(self):
        (self.source / 'outside').symlink_to(self.original_save)
        with self.assertRaises(ValueError): self.prepare()
        self.assertTrue((self.game / 'old.exe').exists())
        (self.source / 'outside').unlink()
        with self.assertRaises(ValueError): update.validate_source(self.prefix, self.prefix)

    def test_config_backup_and_all_game_options(self):
        conf = self.base / 'batocera.conf'
        conf.write_text('# comment\nwindows.dxvk=1\nwindows["Game.wsquashfs"].wine-runner=UMU\nwindows["Game.wsquashfs"].custom=42\n')
        backup = self.base / 'backups'
        self.assertEqual(update.copy_config(conf, 'Game.wsquashfs', self.prefix.name, backup), 'UMU')
        self.assertIn(f'windows["{self.prefix.name}"].custom=42', conf.read_text())
        self.assertEqual(len(list(backup.iterdir())), 1)
        self.assertIn('windows.dxvk=1', conf.read_text())

    def test_commit_preserves_original_archive_and_saves(self):
        self.prepare(); staged = self.base / 'replacement.wsquashfs'; staged.write_bytes(b'new archive')
        prepared = self.saves / 'validated'; prepared.mkdir(); (prepared / 'slot').write_text('new save')
        backup = update.commit(self.manifest, staged, prepared)
        self.assertEqual(backup.read_bytes(), b'old archive')
        self.assertEqual(self.archive.read_bytes(), b'new archive')
        self.assertEqual((self.original_save / 'slot').read_text(), 'new save')
        data = json.loads(self.manifest.read_text())
        self.assertEqual((Path(data['save_backup']) / 'slot').read_text(), 'original')
        self.assertTrue(data['committed'])

    def test_archive_changed_refuses_both_replacements(self):
        self.prepare(); self.archive.write_bytes(b'changed archive')
        staged = self.base / 'new.wsquashfs'; staged.write_bytes(b'new')
        prepared = self.saves / 'validated'; prepared.mkdir()
        with self.assertRaises(ValueError): update.commit(self.manifest, staged, prepared)
        self.assertEqual(self.archive.read_bytes(), b'changed archive')
        self.assertEqual((self.original_save / 'slot').read_text(), 'original')

    def test_failed_archive_swap_restores_original_saves(self):
        self.prepare(); staged = self.base / 'new.wsquashfs'; staged.write_bytes(b'new')
        prepared = self.saves / 'validated'; prepared.mkdir(); (prepared / 'slot').write_text('new save')
        with patch.object(update.os, 'replace', side_effect=OSError('write error')):
            with self.assertRaises(OSError): update.commit(self.manifest, staged, prepared)
        self.assertEqual(self.archive.read_bytes(), b'old archive')
        self.assertEqual((self.original_save / 'slot').read_text(), 'original')
        self.assertEqual((prepared / 'slot').read_text(), 'new save')

    def test_shell_compression_failure_can_resume_without_touching_original_saves(self):
        test_save = self.prepare()
        (test_save / 'slot').write_text('tested save')
        root = Path(__file__).resolve().parents[1]
        state_dir = self.base / 'state'; state_dir.mkdir()
        state = state_dir / 'wsquashfs-builder.json'
        snapshot = state_dir / 'before.json'; snapshot.write_text('{}')
        log = self.base / 'update.log'; log.touch()
        state.write_text(json.dumps(dict(prefix=str(self.prefix), game_name='Game', snapshot=str(snapshot), exe_rel='drive_c/game/new.exe', runner='__SYSTEM__', mode='update', metadata=str(self.manifest), phase='testing', update_log=str(log))))
        tools = self.base / 'bin'; tools.mkdir()
        unsquash = tools / 'unsquashfs'
        unsquash.write_text('#!/bin/sh\nif [ "$1" = -help ]; then echo "-pf pseudo-file"; fi\nexit 0\n')
        unsquash.chmod(0o755)
        q = shlex.quote
        script = f"""
WT_ROOT={q(str(root / 'toolbox'))}
WT_HOME={q(str(self.base))}
source "$WT_ROOT/modules/wsquashfs.sh"
WSQ_STATE_DIR={q(str(state_dir))}; WSQ_STATE_FILE={q(str(state))}
WSQ_SAVE_ROOT={q(str(self.saves))}; WSQ_CONF={q(str(self.base / 'batocera.conf'))}
have_dialog() {{ return 1; }}
wt_clear_tty() {{ :; }}
i18n() {{ printf '%s' "$1"; }}
msgbox() {{ :; }}
wsq_review_launch() {{ :; }}
wsq_update_review_save() {{ WSQ_SAVE_KIND=existing; WSQ_SELECTED_SAVE=drive_c/users/root/Saved; }}
yesno_default_no() {{ [ "$1" != squash_delete_source_title ]; }}
wsq_restart_emulationstation_deferred() {{ :; }}
wsq_post_build_menu() {{ :; }}
maintenance_squash_wine() {{ return 1; }}
wsq_resume_build
python3 - {q(str(self.archive))} {q(str(self.original_save / 'slot'))} "$WSQ_STATE_FILE" <<'CHECK'
import json, sys
from pathlib import Path
assert Path(sys.argv[1]).read_bytes() == b'old archive'
assert Path(sys.argv[2]).read_text() == 'original'
assert json.loads(Path(sys.argv[3]).read_text())['phase'] == 'ready'
CHECK
[ "$?" = 0 ] || exit 3
maintenance_squash_wine() {{ printf 'new archive' > "$2"; }}
wsq_resume_build
"""
        result = subprocess.run(['bash', '-c', script], env=dict(os.environ, PATH=str(tools) + ':' + os.environ['PATH']), capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(state.exists())
        self.assertEqual(self.archive.read_bytes(), b'new archive')
        self.assertEqual((self.original_save / 'slot').read_text(), 'tested save')
        self.assertEqual(len(list(self.base.glob('Game.backup-*.wsquashfs'))), 1)

    @unittest.skipUnless(shutil.which('mksquashfs') and shutil.which('unsquashfs'), 'SquashFS tools unavailable')
    def test_real_archive_round_trip_and_corruption_refusal(self):
        def run(*args):
            subprocess.run(args, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        self.archive.unlink()
        run('mksquashfs', str(self.prefix), str(self.archive), '-noappend', '-processors', '1')
        test_save = self.prepare()
        update.write_autorun(self.prefix, 'drive_c/game/new.exe')
        staged = self.base / 'new.wsquashfs'
        run('mksquashfs', str(self.prefix), str(staged), '-noappend', '-processors', '1')
        log = self.base / 'integrity.log'; cancel = self.base / 'cancel'
        self.assertEqual(integrity.check(staged, 'full', log, cancel), 0)
        backup = update.commit(self.manifest, staged)
        extracted = self.base / 'extracted'
        run('unsquashfs', '-no-xattrs', '-d', str(extracted), str(self.archive))
        self.assertEqual((extracted / 'drive_c/game/new.exe').read_bytes(), b'new')
        self.assertIn('CMD="new.exe" --launch', (extracted / 'autorun.cmd').read_text())
        old = self.base / 'old'
        run('unsquashfs', '-no-xattrs', '-d', str(old), str(backup))
        self.assertEqual((old / 'drive_c/game/old.exe').read_bytes(), b'old')
        corrupt = self.base / 'corrupt.wsquashfs'
        corrupt.write_bytes(self.archive.read_bytes()[:96])
        self.assertNotEqual(integrity.check(corrupt, 'full', log, cancel), 0)

    def test_default_launch_preserves_custom_batch_wrapper(self):
        (self.prefix / 'autorun.cmd').write_text('DIR=drive_c/game\nCMD="start.bat" --flag\n')
        (self.game / 'start.bat').write_text('new.exe\n')
        self.prepare()
        self.assertEqual(update.launch_executable(self.prefix), 'drive_c/game/start.bat')
        self.assertEqual((self.game / 'start.bat').read_text(), 'new.exe\n')

    def test_custom_save_link_is_restored_and_committed_to_its_original_name(self):
        (self.prefix / 'autorun.cmd').write_text('DIR=drive_c/game\nCMD="old.exe"\n')
        custom = self.saves / 'NameFromStartBat'; custom.mkdir()
        (custom / 'slot').write_text('custom original')
        link = self.game / 'saves'; link.symlink_to(custom)
        test_save = self.prepare()
        self.assertEqual(link.resolve(), test_save / '.legacy-shared/NameFromStartBat')
        (link / 'slot').write_text('custom tested')
        self.assertEqual((custom / 'slot').read_text(), 'custom original')
        update.stage_legacy(self.manifest)
        update.restore_legacy(self.prefix, self.manifest)
        self.assertEqual(os.readlink(link), str(custom))
        staged = self.base / 'new.wsquashfs'; staged.write_bytes(b'new archive')
        update.commit(self.manifest, staged)
        self.assertEqual((custom / 'slot').read_text(), 'custom tested')
        self.assertEqual((self.original_save / 'slot').read_text(), 'original')
        self.assertTrue(list(self.saves.glob('NameFromStartBat.backup-*')))

    def test_root_link_and_batch_paths_use_an_isolated_view(self):
        (self.prefix / 'autorun.cmd').write_text('DIR=drive_c/game\nCMD="start.bat"\n')
        custom = self.saves / 'GameCreatedName'; custom.mkdir()
        (custom / 'slot').write_text('old progress')
        unrelated = self.saves / 'UnrelatedGame'; unrelated.mkdir()
        (unrelated / 'huge').write_text('unrelated')
        batch = f'mkdir "{self.saves}/GameCreatedName"\nnew.exe\n'
        (self.game / 'start.bat').write_text(batch)
        link = self.game / 'shared'; link.symlink_to(self.saves)
        test_save = self.prepare()
        shared = test_save / '.legacy-shared'
        self.assertEqual(link.resolve(), shared)
        self.assertEqual((shared / 'GameCreatedName/slot').read_text(), 'old progress')
        self.assertFalse((shared / 'UnrelatedGame').exists())
        self.assertIn(str(shared), (self.game / 'start.bat').read_text())
        (shared / 'GameCreatedName/slot').write_text('new progress')
        (shared / 'EngineCreatedName').mkdir()
        (shared / 'EngineCreatedName/new').write_text('saved by game')
        update.stage_legacy(self.manifest); update.restore_legacy(self.prefix, self.manifest)
        self.assertEqual((self.game / 'start.bat').read_text(), batch)
        self.assertEqual(os.readlink(link), str(self.saves))
        staged = self.base / 'new.wsquashfs'; staged.write_bytes(b'new archive')
        update.commit(self.manifest, staged)
        self.assertEqual((custom / 'slot').read_text(), 'new progress')
        self.assertEqual((self.saves / 'EngineCreatedName/new').read_text(), 'saved by game')
        self.assertEqual((unrelated / 'huge').read_text(), 'unrelated')

    def test_mixed_savedir_and_custom_links_keep_their_separate_rules(self):
        standard = self.prefix / 'drive_c/users/root/Saved'
        standard.parent.mkdir(parents=True); standard.symlink_to(self.original_save)
        custom = self.saves / 'CustomOther'; custom.mkdir(); (custom / 'slot').write_text('custom')
        extra = self.game / 'extra'; extra.symlink_to(custom)
        test_save = self.prepare()
        update.stage_legacy(self.manifest)
        update.detach_saves(self.prefix, test_save)
        update.restore_legacy(self.prefix, self.manifest, 'custom')
        self.assertFalse(standard.is_symlink())
        self.assertEqual(os.readlink(extra), str(custom))

    def test_existing_executable_resolution(self):
        (self.game / 'Game Title.exe').write_text('exe')
        (self.prefix / 'autorun.cmd').write_text('DIR=C:\\game\nCMD=Game Title.exe -windowed\n')
        self.assertEqual(update.launch_executable(self.prefix), 'drive_c/game/Game Title.exe')
        update.write_autorun(self.prefix, 'drive_c/game/Game Title.exe')
        self.assertIn('CMD="Game Title.exe" -windowed', (self.prefix / 'autorun.cmd').read_text())
        (self.prefix / 'autorun.cmd').write_text('DIR=drive_c/game\nCMD="missing.exe"\n')
        self.assertEqual(update.launch_executable(self.prefix), '')

    def test_named_game_directory_and_mario_batch_layout(self):
        name = 'Super Mario Bros Remastered'
        game = self.prefix / 'drive_c' / name
        self.game.rename(game); self.game = game
        (self.prefix / 'autorun.cmd').write_text(f'DIR=drive_c/{name}\nCMD=start.bat\n')
        batch = f'@echo off\nmkdir "z:{str(self.saves).replace(chr(47), chr(92))}\\{name}"\nstart /wait "" ".\\SMB1R.exe"'
        (game / 'start.bat').write_text(batch)
        save = self.saves / name; save.mkdir(); (save / 'slot').write_text('progress')
        link = self.prefix / 'drive_c/users/root/AppData/Roaming/SMB1R'
        link.parent.mkdir(parents=True); link.symlink_to(save)
        (self.source / 'SMB1R.exe').write_text('new mario executable')
        test_save = self.prepare()
        self.assertEqual(update.game_directory(self.prefix), game)
        self.assertEqual(update.launch_executable(self.prefix), f'drive_c/{name}/start.bat')
        self.assertTrue((game / 'SMB1R.exe').exists())
        self.assertIn(str(test_save).replace('/', '\\'), (game / 'start.bat').read_text())
        update.stage_legacy(self.manifest); update.restore_legacy(self.prefix, self.manifest)
        self.assertEqual((game / 'start.bat').read_text(), batch)
        self.assertEqual(os.readlink(link), str(save))

    def test_cat_quest_named_directory_and_two_root_links(self):
        game = self.prefix / 'drive_c/Cat Quest'
        self.game.rename(game); self.game = game
        (self.prefix / 'autorun.cmd').write_text('DIR=drive_c/Cat Quest\nCMD="Cat Quest.exe"\n')
        (self.source / 'Cat Quest.exe').write_text('updated cat quest')
        links = []
        for user in ('root', 'steamuser'):
            link = self.prefix / f'drive_c/users/{user}/AppData/LocalLow/The Gentlebros Pte_ Ltd_'
            link.parent.mkdir(parents=True); link.symlink_to(self.saves); links.append(link)
        test_save = self.prepare(); shared = test_save / '.legacy-shared'
        self.assertEqual(update.game_directory(self.prefix), game)
        self.assertEqual(update.launch_executable(self.prefix), 'drive_c/Cat Quest/Cat Quest.exe')
        for link in links: self.assertEqual(link.resolve(), shared)
        (shared / 'Cat Quest').mkdir(); (shared / 'Cat Quest/slot').write_text('saved by game')
        update.stage_legacy(self.manifest); update.restore_legacy(self.prefix, self.manifest)
        for link in links: self.assertEqual(os.readlink(link), str(self.saves))
        staged = self.base / 'new.wsquashfs'; staged.write_bytes(b'new archive')
        update.commit(self.manifest, staged)
        self.assertEqual((self.saves / 'Cat Quest/slot').read_text(), 'saved by game')

    def test_update_source_menu_filters_media_and_keeps_browse(self):
        root = Path(__file__).resolve().parents[1]
        roms = self.base / 'roms'; roms.mkdir()
        for name in ('Plain Game', '.hidden', 'images', 'media', 'videos'):
            (roms / name).mkdir()
        (roms / 'alias').symlink_to(roms / 'Plain Game')
        q = shlex.quote
        setup = f"""
WT_ROOT={q(str(root / 'toolbox'))}; WT_HOME={q(str(self.base))}
source "$WT_ROOT/modules/wsquashfs.sh"
WSQ_WINDOWS_DIR={q(str(roms))}
i18n() {{ printf '%s' "$1"; }}
menu_select() {{ printf '%s\\n' "$@" >&2; printf '1'; }}
wsq_update_select_source
"""
        result = subprocess.run(['bash', '-c', setup], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(roms / 'Plain Game'))
        self.assertIn('browse', result.stderr)
        for hidden in ('.hidden', 'images', 'media', 'videos', 'alias'):
            self.assertNotIn(hidden, result.stderr)
        prefix = roms / 'A prefix.wine'
        (prefix / 'drive_c/Named Game').mkdir(parents=True)
        (prefix / 'system.reg').write_text('registry')
        (prefix / 'autorun.cmd').write_text('DIR=drive_c/Named Game\nCMD=play.exe\n')
        result = subprocess.run(['bash', '-c', setup], capture_output=True, text=True)
        self.assertEqual(result.stdout.strip(), str(prefix / 'drive_c/Named Game'))
        browse = setup.replace("printf '1';", "printf 'browse';")
        # Force the text fallback to avoid relying on an installed desktop picker.
        fallback = 'command() { [ "$*" != "-v yad" ] && builtin command "$@"; }\n'
        fallback += "input_text() { printf '%s' " + q(str(self.source)) + "; }\nwsq_update_select_source\n"
        browse = browse.replace('wsq_update_select_source\n', fallback)
        result = subprocess.run(['bash', '-c', browse], capture_output=True, text=True)
        self.assertEqual(result.stdout.strip(), str(self.source), result.stderr)

if __name__ == '__main__': unittest.main()
