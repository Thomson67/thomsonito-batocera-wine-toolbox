import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class UIOutputTests(unittest.TestCase):
    def test_missing_executable_message_does_not_pollute_selection(self):
        result = subprocess.run(
            ["bash", "-c", r'''
source toolbox/lib/common.sh
source toolbox/modules/wsquashfs-update.sh
have_dialog() { return 0; }
wt_clear_tty() { :; }
i18n() { printf '%s' "$1"; }
# Model dialog's screen output, including terminal escape sequences.
dialog() { printf '\033[?1049hMissing executable\033[?1049l'; }
python3() {
    case "$2" in
        exe) printf ''; ;;
        game-dir) printf 'drive_c/game\n'; ;;
        *) return 1 ;;
    esac
}
wsq_select_executable() { printf 'drive_c/game/New folder/Game.exe\n'; }
selected="$(wsq_update_select_executable '/tmp/Game.wine')" || exit
printf '%s' "$selected"
'''],
            cwd=ROOT, capture_output=True, text=True, check=True,
        )
        self.assertEqual(result.stdout, "drive_c/game/New folder/Game.exe")
        self.assertIn("Missing executable", result.stderr)


if __name__ == "__main__":
    unittest.main()
