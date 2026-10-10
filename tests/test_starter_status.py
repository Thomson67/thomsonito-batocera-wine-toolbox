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


class DwStarterBridgeTests(unittest.TestCase):
    def test_dw_cli_selects_requested_version_and_checks_installed_manifest(self):
        original = '''#!/bin/bash
CUSTOM_DIR="$TEST_ROOT/custom"
msg() {
    echo INTERACTIVE_MESSAGE
}
install_dw() {
    local name target
    if command -v dialog >/dev/null 2>&1; then
        name="$(dialog --stdout)"
    else
        read -r name
    fi
    target="$CUSTOM_DIR/${name}-UMU"
    if ! yesno "$(i18n install_named "$name-UMU")" Confirm; then return; fi
    [ "${MOCK_FAIL:-0}" = 0 ] || return
    prepare_runtime_for_runner "$target"
    mkdir -p "$target"
    printf verified > "$target/manifest"
    msg Done Installed
}
install_runner_menu() { echo INTERACTIVE_MENU; }
install_runner_cli() {
    local base="${1%-UMU}" target="$CUSTOM_DIR/${1%-UMU}-UMU"
    case "$base" in
        proton-EM-*) install_em "$base" 1 ;;
        *) return 65 ;;
    esac
}
i18n() { printf '%s' "$1"; }
yesno() { echo INTERACTIVE_CONFIRM; return 1; }
prepare_runtime_for_runner() { echo "runtime:$1"; }
verify_runner_manifest() { [ -s "$1/manifest" ]; }
install_runner_cli "$2"
exit $?
'''
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            main = root / 'umu-toolbox.sh'
            main.write_text(original)
            main.chmod(0o755)
            script = '''
source toolbox/modules/umu.sh
UMU_TOOLBOX_ROOT="$TEST_ROOT"
UMU_TOOLBOX_MAIN="$TEST_ROOT/umu-toolbox.sh"
ensure_umu_toolbox() { return 0; }
i18n() { printf '%s' "$1"; }
install_umu_runner "$TEST_RUNNER"
'''
            env = dict(os.environ, TEST_ROOT=tmp, TEST_RUNNER='dwproton-11.0-14-UMU')
            result = subprocess.run(['bash', '-c', script], cwd=ROOT, env=env,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn('INTERACTIVE', result.stdout)
            self.assertIn('runtime:' + str(root / 'custom/dwproton-11.0-14-UMU'), result.stdout)
            self.assertTrue((root / 'custom/dwproton-11.0-14-UMU/manifest').is_file())
            env.update(TEST_RUNNER='dwproton-11.0-15-UMU', MOCK_FAIL='1')
            result = subprocess.run(['bash', '-c', script], cwd=ROOT, env=env,
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((root / 'custom/dwproton-11.0-15-UMU').exists())
            self.assertEqual(main.read_text(), original)
            self.assertFalse(list(root.glob('.starter-batch.*')))


if __name__ == '__main__':
    unittest.main()
