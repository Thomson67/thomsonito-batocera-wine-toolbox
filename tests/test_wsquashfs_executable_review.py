"""Regression checks for WSquashFS executable selection timing."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
CREATE = (ROOT / "toolbox/modules/wsquashfs.sh").read_text()
UPDATE = (ROOT / "toolbox/modules/wsquashfs-update.sh").read_text()
FR = (ROOT / "toolbox/lang/fr.sh").read_text()
EN = (ROOT / "toolbox/lang/en.sh")


def function_body(source, name, next_name):
    start = source.index(f"{name}() {{")
    end = source.index(f"{next_name}() {{", start)
    return source[start:end]


class ExecutableReviewTests(unittest.TestCase):
    def test_creation_keeps_initial_selection_and_adds_post_launch_review(self):
        create_new = function_body(CREATE, "wsq_create_new", "wsq_resume_build")
        self.assertIn('exe_rel="$(wsq_select_executable "$target")"', create_new)
        self.assertIn('wsq_write_autorun "$target" "$exe_rel"', create_new)
        self.assertIn('"exe" "$(i18n wsq_executable_review)"', CREATE)
        self.assertIn("wsq_update_game_executable || continue", CREATE)

    def test_update_uses_existing_command_before_launch_without_selector_step(self):
        update_new = function_body(UPDATE, "wsq_update_new", "wsq_update_review_save")
        self.assertNotIn("wsq_update_select_executable", UPDATE)
        self.assertIn('python3 "$WSQ_UPDATE_HELPER" exe "$prefix"', update_new)
        self.assertIn('wsq_request_game_launch "$prefix"', update_new)

    def test_post_launch_change_preserves_update_launch_directives(self):
        change = function_body(CREATE, "wsq_update_game_executable", "wsq_launch_failure_menu")
        self.assertIn('python3 "$WSQ_UPDATE_HELPER" autorun "$prefix" "$new_exe"', change)
        self.assertIn('wsq_write_autorun "$prefix" "$new_exe"', change)
        self.assertIn('wsq_save_state "$prefix" "$game_name" "$snapshot" "$exe_rel" "$runner"', change)
        failure = function_body(CREATE, "wsq_launch_failure_menu", "wsq_review_launch")
        self.assertIn('"exe" "$(i18n wsq_executable_review)"', failure)
        self.assertIn("wsq_retry_pending", failure)
        review = function_body(CREATE, "wsq_review_launch", "wsq_resume_build")
        self.assertIn('"exe" "$(i18n wsq_executable_review)"', review)

    def test_label_is_translated(self):
        self.assertIn('[wsq_executable_review]="Vérifier / modifier le choix de l’exécutable du jeu"', FR)
        self.assertIn('[wsq_executable_review]="Review / change the selected game executable"', EN.read_text())


if __name__ == "__main__":
    unittest.main()

