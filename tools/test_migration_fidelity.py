import shutil
import tempfile
from pathlib import Path
import unittest

from migration_fidelity import compare, fixtures, inventory, write_report


class MigrationFidelityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        self.expected = fixtures(self.source)
        self.exported = self.root / "exported"
        shutil.copytree(self.source, self.exported)

    def test_exact_export_preserves_duplicate_counts_and_album_paths(self):
        result = compare(self.expected, inventory(self.exported))
        self.assertTrue(result["all_expected_bytes_present"])
        self.assertEqual(result["byte_identical_count"], 4)
        self.assertTrue(all(row["album_path_preserved"] for row in result["matches"]))
        self.assertEqual(result["extra_exports"], [])

    def test_flattening_and_renaming_preserve_bytes_but_report_lost_structure(self):
        shutil.rmtree(self.exported)
        self.exported.mkdir()
        for index, source in enumerate(sorted(self.source.rglob("*.png"))):
            shutil.copyfile(source, self.exported / f"renamed-{index}.png")
        result = compare(self.expected, inventory(self.exported))
        self.assertTrue(result["all_expected_bytes_present"])
        self.assertEqual(result["byte_identical_count"], 4)
        self.assertTrue(all(not row["name_preserved"] for row in result["matches"]))

    def test_a_single_export_does_not_satisfy_two_identical_source_items(self):
        (self.exported / "Album B/duplicate.png").unlink()
        result = compare(self.expected, inventory(self.exported))
        self.assertFalse(result["all_expected_bytes_present"])
        self.assertEqual(len(result["missing_originals"]), 1)
        self.assertEqual(result["missing_originals"][0]["path"], "Album B/duplicate.png")

    def test_truncated_file_is_detected_even_when_its_name_is_unchanged(self):
        target = self.exported / "Album B/shared.png"
        target.write_bytes(target.read_bytes()[:-8])
        result = compare(self.expected, inventory(self.exported))
        self.assertEqual(result["changed_at_same_path"], ["Album B/shared.png"])
        self.assertEqual(result["byte_identical_count"], 3)
        self.assertEqual(len(result["extra_exports"]), 1)

    def test_symlink_inventory_is_rejected_and_existing_fixtures_are_not_overwritten(self):
        (self.exported / "link.png").symlink_to(self.source / "Album A/shared.png")
        with self.assertRaises(ValueError):
            inventory(self.exported)
        with self.assertRaises(FileExistsError):
            fixtures(self.source)

    def test_report_cannot_modify_a_file_in_the_scanned_input(self):
        target = self.exported / "Album A/shared.png"
        before = target.read_bytes()
        with self.assertRaises(ValueError):
            write_report(self.expected, target, self.exported)
        self.assertEqual(target.read_bytes(), before)

    def test_existing_baseline_or_report_is_never_overwritten(self):
        target = self.root / "baseline.json"
        target.write_text("keep this baseline")
        with self.assertRaises(FileExistsError):
            write_report(self.expected, target, self.exported)
        self.assertEqual(target.read_text(), "keep this baseline")


if __name__ == "__main__":
    unittest.main()
