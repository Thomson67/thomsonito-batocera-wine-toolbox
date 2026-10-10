import importlib.util
import io
import json
from pathlib import Path
import shutil
import struct
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('resh_compat', ROOT / 'toolbox/helpers/reshade_compat.py')
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)


def make_archive(path, entries):
    with tarfile.open(path, 'w:gz') as tar:
        for name, value in entries:
            item = tarfile.TarInfo(name)
            if value is None:
                item.type = tarfile.SYMTYPE
                item.linkname = '../../outside'
                tar.addfile(item)
            else:
                item.size = len(value)
                tar.addfile(item, io.BytesIO(value))


class ReShadeCompatibilityTests(unittest.TestCase):
    def test_file_adapter_checks_real_pe_header_and_bitness(self):
        with tempfile.TemporaryDirectory() as folder:
            p = Path(folder) / 'Game.exe'
            for machine, expected in [(0x8664, 'x86-64'), (0x14c, '80386')]:
                data = bytearray(256)
                data[:2] = b'MZ'
                struct.pack_into('<I', data, 0x3c, 128)
                data[128:132] = b'PE\0\0'
                struct.pack_into('<H', data, 132, machine)
                p.write_bytes(data)
                self.assertIn('executable', c.describe(p))
                self.assertIn(expected, c.describe(p))
            p.write_bytes(b'MZ is not enough')
            with self.assertRaises(ValueError):
                c.describe(p)

    def test_shader_snapshot_update_preserves_local_edits_and_failed_download(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            archive = base / 'fixture.tar.gz'
            make_archive(archive, [('repo-branch/Shaders/Effect.fx', b'first')])
            destination = base / 'cache'
            def download(args, **kwargs):
                self.assertEqual(args[-3], 'https://codeload.github.com/example/shaders/tar.gz/slim')
                shutil.copyfile(archive, args[-1])
            with patch.object(c.subprocess, 'run', side_effect=download):
                c.git_call(['-c', 'http.lowSpeedLimit=1000', 'clone', '--depth', '1',
                            '--branch', 'slim', '--single-branch', 'https://github.com/example/shaders', str(destination)])
                effect = destination / 'Shaders/Effect.fx'
                self.assertEqual(effect.read_bytes(), b'first')
                make_archive(archive, [('repo-branch/Shaders/Effect.fx', b'second')])
                c.git_call(['-C', str(destination), 'pull', '--ff-only'])
                self.assertEqual(effect.read_bytes(), b'second')
                effect.write_bytes(b'user edits')
                with self.assertRaisesRegex(ValueError, 'local shader edits'):
                    c.git_call(['-C', str(destination), 'pull', '--ff-only'])
                self.assertEqual(effect.read_bytes(), b'user edits')
                effect.write_bytes(b'second')
                make_archive(archive, [('repo-branch/../outside', b'unsafe')])
                with self.assertRaises(ValueError):
                    c.git_call(['-C', str(destination), 'pull', '--ff-only'])
                self.assertEqual(effect.read_bytes(), b'second')
                self.assertEqual(json.loads((destination / '.git/uwt-archive.json').read_text())['branch'], 'slim')
            with self.assertRaises(ValueError):
                c.snapshot('https://example.com/unapproved', 'main', base / 'other')

    def test_shader_archive_rejects_links_and_traversal(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            source = base / 'source'
            source.mkdir()
            archive = base / 'fixture.tar.gz'
            for entry in [('repo/../../outside', b'unsafe'), ('repo/Shaders/link', None), ('/absolute', b'unsafe')]:
                make_archive(archive, [entry])
                with self.assertRaises(ValueError):
                    c.unpack(archive, source)
            self.assertEqual(list(source.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
