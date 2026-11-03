"""Host checks only. This does not compile Swift or run XCTest."""
from pathlib import Path
import os
import sqlite3
import plistlib
import unittest
import yaml
from tree_sitter import Language, Parser
import tree_sitter_swift

ROOT = Path(__file__).resolve().parents[1]
SQL = ROOT / "Sources/SoNoCore/Persistence/Migrations/001_initial.sql"
GENERATED = {".git", ".ci-venv", ".venv", ".build", "DerivedData", "build", "node_modules", "__pycache__"}


def workspace_files():
    for folder, directories, files in os.walk(ROOT):
        directories[:] = [name for name in directories if name not in GENERATED]
        for name in files:
            yield Path(folder) / name


class WorkspaceTests(unittest.TestCase):
    def test_swift_syntax(self):
        parser = Parser(Language(tree_sitter_swift.language()))
        failures = []
        files = sorted(path for path in workspace_files() if path.suffix == ".swift")
        for path in files:
            source = path.read_bytes()
            tree = parser.parse(source)
            if tree.root_node.has_error:
                stack = [tree.root_node]
                while stack:
                    node = stack.pop()
                    if node.type == "ERROR" or node.is_missing:
                        failures.append(f"{path.relative_to(ROOT)}:{node.start_point.row + 1}: {source[node.start_byte:node.end_byte][:100]!r}")
                    stack.extend(node.children)
        self.assertTrue(files)
        self.assertEqual(failures, [], "\n".join(failures))

    def test_project_manifest_and_resources(self):
        project = yaml.safe_load((ROOT / "project.yml").read_text(encoding="utf-8"))
        self.assertEqual(project["options"]["deploymentTarget"]["iOS"], "17.0")
        self.assertIn("SoNoAppTests", project["targets"])
        self.assertTrue(SQL.is_file())
        self.assertTrue((ROOT / "Sources/CSQLite/shim.h").is_file())
        privacy = plistlib.loads((ROOT / "App/PrivacyInfo.xcprivacy").read_bytes())
        self.assertFalse(privacy["NSPrivacyTracking"])
        self.assertEqual(privacy["NSPrivacyAccessedAPITypes"][0]["NSPrivacyAccessedAPITypeReasons"], ["CA92.1"])
        for path in workspace_files():
            if path.suffix not in {".swift", ".sql", ".md", ".yml", ".yaml", ".py", ".sh", ".h", ".xcprivacy"}:
                continue
            lines = path.read_text(encoding="utf-8").splitlines()
            self.assertFalse(any(line.rstrip() != line for line in lines), f"Trailing whitespace in {path}")


class SQLiteContractTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:")
        self.db.execute("PRAGMA foreign_keys=ON")
        self.db.executescript(SQL.read_text(encoding="utf-8"))
        self.db.execute("INSERT INTO customers VALUES('c','nam',?)", (b'{}',))
        self.db.commit()

    def tearDown(self):
        self.db.close()

    def insert_entry(self, entry_id, amount=500, customer="c", reversal=None, key=None):
        kind = "reversal" if reversal else "debt"
        self.db.execute("INSERT INTO transactions VALUES(?,?,?,?,?,?,?,?)", (entry_id, customer, amount, 0.0, kind, reversal, key, b'{}'))

    def test_foreign_keys_and_amount_constraints(self):
        for amount, customer in [(0, "c"), (-1, "c"), (100, "missing")]:
            with self.assertRaises(sqlite3.IntegrityError):
                self.insert_entry("bad", amount, customer)

    def test_unique_import_and_reversal(self):
        self.insert_entry("original", key="row-1")
        with self.assertRaises(sqlite3.IntegrityError):
            self.insert_entry("duplicate", key="row-1")
        self.insert_entry("r1", reversal="original")
        with self.assertRaises(sqlite3.IntegrityError):
            self.insert_entry("r2", reversal="original")

    def test_audit_cannot_be_changed_or_deleted(self):
        self.db.execute("INSERT INTO audit VALUES('a','c',0,?)", (b'{}',))
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE audit SET entity_id='x'")
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("DELETE FROM audit")

    def test_transaction_rolls_back_entry_when_audit_fails(self):
        self.db.execute("INSERT INTO audit VALUES('a','c',0,?)", (b'{}',))
        self.db.commit()
        try:
            with self.db:
                self.insert_entry("debt")
                self.db.execute("INSERT INTO audit VALUES('a','c',0,?)", (b'{}',))
        except sqlite3.IntegrityError:
            pass
        self.assertEqual(self.db.execute("SELECT count(*) FROM transactions").fetchone()[0], 0)
        self.assertEqual(self.db.execute("SELECT count(*) FROM audit").fetchone()[0], 1)

    def test_restore_deletes_self_referencing_entries_atomically(self):
        self.insert_entry("d")
        self.insert_entry("r", reversal="d")
        self.db.commit()
        try:
            with self.db:
                self.db.execute("DELETE FROM transactions")
                self.db.execute("DELETE FROM customers")
                self.insert_entry("invalid", customer="missing")
        except sqlite3.IntegrityError:
            pass
        self.assertEqual(self.db.execute("SELECT count(*) FROM transactions").fetchone()[0], 2)
        self.assertEqual(self.db.execute("PRAGMA integrity_check").fetchone()[0], "ok")


if __name__ == "__main__":
    unittest.main(verbosity=2)
