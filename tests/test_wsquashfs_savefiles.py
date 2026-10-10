import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'toolbox/helpers/wsquashfs_savefiles.py'
spec = importlib.util.spec_from_file_location('savefiles', HELPER)
sf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sf)


class SaveFilesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.prefix = self.root / 'Game.wine'
        self.game = self.prefix / 'drive_c/game'
        self.game.mkdir(parents=True)
        self.saves = self.root / 'saves'
        self.saves.mkdir()
        self.staged = self.root / 'staged'
        self.staged.mkdir()
        (self.game / 'Game.exe').write_bytes(b'executable')

    def test_detects_nested_changes_and_custom_game_folder(self):
        (self.game / 'profile').mkdir()
        file = self.game / 'profile/progress.sav'
        file.write_text('old')
        before = sf.inventory(self.prefix)
        file.write_text('new save data')
        (self.game / 'settings.ini').write_text('possible false positive')
        after = sf.inventory(self.prefix)
        self.assertNotEqual(before['drive_c/game/profile/progress.sav'], after['drive_c/game/profile/progress.sav'])
        self.assertIn('drive_c/game/settings.ini', after)
        self.assertNotIn('drive_c/game/Game.exe', after)
        custom = self.prefix / 'drive_c/Other Game'
        custom.mkdir()
        (custom / 'slot.sav').write_text('slot')
        (self.prefix / 'autorun.cmd').write_text('DIR=drive_c/Other Game\nCMD=game.exe\n')
        self.assertIn('drive_c/Other Game/slot.sav', sf.inventory(self.prefix))

    def test_only_selected_files_are_copied_and_removed(self):
        external = self.saves / 'profile with spaces.sav'
        external.write_text('progress')
        selected = self.game / external.name
        selected.symlink_to(external)
        (self.game / 'settings.ini').write_text('unchanged settings')
        sf.stage(self.prefix, 'drive_c/game', [selected.name], self.saves, self.staged)
        sf.remove_selected(self.prefix, 'drive_c/game', [selected.name], self.saves)
        self.assertFalse(selected.is_symlink())
        self.assertFalse(selected.exists())
        self.assertEqual(external.read_text(), 'progress')
        self.assertEqual((self.game / 'Game.exe').read_bytes(), b'executable')
        self.assertEqual((self.game / 'settings.ini').read_text(), 'unchanged settings')
        self.assertEqual([p.name for p in self.staged.iterdir()], [selected.name])

    def test_rejects_escape_binary_delimiter_and_external_directory_links(self):
        outside = self.root / 'outside.sav'
        outside.write_text('secret')
        (self.game / 'bad.sav').symlink_to(outside)
        for names in [['../outside.sav'], ['bad.sav'], ['Game.exe'], ['a;b.sav'], []]:
            with self.assertRaises(ValueError):
                sf.stage(self.prefix, 'drive_c/game', names, self.saves, self.staged)
        (self.game / 'linked').symlink_to(self.saves, target_is_directory=True)
        with self.assertRaises(ValueError):
            sf.checked_files(self.prefix, 'drive_c/game/linked', ['x.sav'], self.saves)

    def test_cli_and_autorun_preserve_spaces_and_semicolon_list(self):
        (self.game / 'profile one.sav').write_text('save')
        before = self.root / 'before.json'
        before.write_text('{}')
        result = subprocess.run(['python3', str(HELPER), 'stage', str(self.prefix), str(before),
                                 '--folder', 'drive_c/game', '--save-root', str(self.saves),
                                 '--staged', str(self.staged), 'profile one.sav'], capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        script = f'''source '{ROOT}/toolbox/modules/wsquashfs.sh'
wsq_write_autorun '{self.prefix}' 'drive_c/game/Game.exe' 'drive_c/game' 'profile one.sav;slot.dat'
'''
        # The module loads its sibling update module through WT_ROOT.
        result = subprocess.run(['bash', '-c', script], env={'WT_ROOT': str(ROOT / 'toolbox'), 'WT_HOME': str(self.root)}, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        autorun = (self.prefix / 'autorun.cmd').read_text()
        self.assertIn('SAVEDIR=drive_c/game/\n', autorun)
        self.assertIn('SAVEFILES=profile one.sav;slot.dat\n', autorun)
        self.assertIn('CMD="Game.exe"', autorun)

    def test_creation_copy_survives_replacing_existing_save_destination(self):
        dest = self.saves / 'Game'
        dest.mkdir()
        (dest / 'progress.sav').write_text('latest progress')
        (self.game / 'progress.sav').symlink_to(dest / 'progress.sav')
        state = self.root / 'state'
        state.mkdir()
        before = self.root / 'before.json'
        before.write_text('{}')
        script = f'''source '{ROOT}/toolbox/modules/wsquashfs.sh'
wsq_save_destination_prepare() {{ rm -rf -- "$1"; mkdir -p -- "$1"; }}
prefix='{self.prefix}'
snapshot='{before}'
save_rel=drive_c/game
game_name=Game
WSQ_STATE_DIR='{state}'
WSQ_SAVE_ROOT='{self.saves}'
WSQ_SELECTED_SAVEFILES=progress.sav
wsq_copy_savefiles
'''
        result = subprocess.run(['bash', '-c', script], env={'WT_ROOT': str(ROOT / 'toolbox'), 'WT_HOME': str(self.root)}, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((dest / 'progress.sav').read_text(), 'latest progress')
        self.assertFalse((self.game / 'progress.sav').is_symlink())
        self.assertFalse((self.game / 'progress.sav').exists())
        self.assertEqual((self.game / 'Game.exe').read_bytes(), b'executable')

    def test_cancel_destination_keeps_original_files(self):
        selected = self.game / 'progress.sav'
        selected.write_text('progress')
        state = self.root / 'state'
        state.mkdir()
        before = self.root / 'before.json'
        before.write_text('{}')
        script = f'''source '{ROOT}/toolbox/modules/wsquashfs.sh'
wsq_save_destination_prepare() {{ return 10; }}
prefix='{self.prefix}'
snapshot='{before}'
save_rel=drive_c/game
game_name=Game
WSQ_STATE_DIR='{state}'
WSQ_SAVE_ROOT='{self.saves}'
WSQ_SELECTED_SAVEFILES=progress.sav
wsq_copy_savefiles
'''
        result = subprocess.run(['bash', '-c', script], env={'WT_ROOT': str(ROOT / 'toolbox'), 'WT_HOME': str(self.root)}, capture_output=True)
        self.assertEqual(result.returncode, 10, result.stderr)
        self.assertEqual(selected.read_text(), 'progress')
        self.assertEqual(list(state.iterdir()), [])

    def test_snapshot_metadata_does_not_become_directory_candidate(self):
        before = self.root / 'before.json'
        subprocess.run(['python3', str(ROOT / 'toolbox/helpers/wsquashfs_builder.py'),
                        'snapshot', str(self.prefix), str(before)], check=True)
        (self.game / 'progress.sav').write_text('progress')
        result = subprocess.run(['python3', str(ROOT / 'toolbox/helpers/wsquashfs_builder.py'),
                                 'diff', str(self.prefix), str(before)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('__game_files__', result.stdout)
        self.assertIn('drive_c/game', result.stdout)
