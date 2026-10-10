import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class StarterStatusTests(unittest.TestCase):
    def test_list_includes_installed_and_missing_runners_without_modifying_them(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            custom = base / 'custom'
            custom.mkdir()
            for name in ('GE-Proton-10-25', 'wine-9.17-amd64', 'GE-Proton10-25-UMU'):
                (custom / name).mkdir()
            ids = ['GE-Proton10-25', 'Vanilla-9.17', 'dwproton-11.0-14']
            starter = base / 'starter.json'
            starter.write_text(json.dumps({'version': 'test', 'classic_runner_ids': ids,
                'umu_runner_ids': ['GE-Proton10-25-UMU', 'GE-Proton11-7-UMU']}))
            catalog = base / 'runners.json'
            catalog.write_text(json.dumps({'install_path': str(custom), 'runners': [
                dict(id=rid, name=name, legacy_id=legacy, file='test.tar.xz',
                     size_bytes=1, download_url='unused', sha256='unused')
                for rid, name, legacy in zip(ids, ['GE-Proton-10-25', 'Vanilla-9.17',
                    'dwproton-11.0-14'], ['GE-Proton10-25', 'wine-9.17-amd64',
                    'dwproton-11.0-14'])]}))
            before = sorted(str(p.relative_to(base)) for p in base.rglob('*'))
            for lang, installed, missing in [('fr', 'Installé', 'Manquant'),
                                             ('en', 'Installed', 'Missing')]:
                result = subprocess.run(['bash', '-c', '''
source toolbox/lib/common.sh
WT_LANGUAGE="$TEST_LANG"
load_i18n
source toolbox/modules/starter-pack.sh
STARTER_DATA="$TEST_STARTER"
RUNNERS_DATA="$TEST_CATALOG"
have_dialog() { return 0; }
wt_clear_tty() { :; }
dialog() {
    while [ "$#" -gt 0 ]; do
        if [ "$1" = --textbox ]; then cat "$2"; return; fi
        shift
    done
    return 1
}
starter_view_runners
'''], cwd=ROOT, env=dict(os.environ, WT_ROOT=str(ROOT / 'toolbox'),
                    TEST_LANG=lang, TEST_STARTER=str(starter), TEST_CATALOG=str(catalog)),
                    text=True, capture_output=True, check=True)
                self.assertEqual(result.stdout, '')
                for name in ('GE-Proton-10-25', 'Vanilla-9.17', 'GE-Proton10-25-UMU'):
                    self.assertIn(f'{name} | {installed}', result.stderr)
                for name in ('dwproton-11.0-14', 'GE-Proton11-7-UMU'):
                    self.assertIn(f'{name} | {missing}', result.stderr)
                self.assertNotIn('missing translation', result.stderr)
            self.assertEqual(before, sorted(str(p.relative_to(base)) for p in base.rglob('*')))


if __name__ == '__main__':
    unittest.main()
