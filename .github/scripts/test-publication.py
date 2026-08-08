#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("build-publication.py")
SHA = "a" * 40


class PublicationBuilderTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        self.output = self.root / "output"
        self.source.mkdir()
        (self.source / "public").mkdir()
        (self.source / "public" / "artifact.txt").write_text("artifact\n", encoding="utf-8")
        (self.source / "docs").mkdir()
        (self.source / "docs" / "public.md").write_text("public\n", encoding="utf-8")
        (self.source / ".agents" / "docs").mkdir(parents=True)
        (self.source / ".agents" / "docs" / "private.md").write_text("private\n", encoding="utf-8")
        self.config = self.root / "config.yml"

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_config(self, text: str) -> None:
        self.config.write_text(text, encoding="utf-8")

    def run_builder(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--source",
                str(self.source),
                "--destination",
                str(self.output),
                "--config",
                str(self.config),
                "--channel",
                "release",
                "--version",
                "1.0.0",
                "--source-commit",
                SHA,
                "--generated-at",
                "2026-01-01T00:00:00Z",
            ],
            text=True,
            capture_output=True,
            check=False,
        )

    def test_builds_whitelisted_payload_and_manifest(self) -> None:
        self.write_config("enabled: true\ninclude: [public]\nrequired: [public/artifact.txt]\nexclude: []\n")
        result = self.run_builder()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.output / "public" / "artifact.txt").read_text(), "artifact\n")
        self.assertFalse((self.output / "docs").exists())
        manifest = json.loads((self.output / ".github" / "publication.json").read_text())
        self.assertEqual(manifest["sourceCommit"], SHA)
        self.assertEqual(manifest["channel"], "release")

    def test_disabled_publication_fails_closed(self) -> None:
        self.write_config("enabled: false\ninclude: []\nrequired: []\nexclude: []\n")
        result = self.run_builder()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("disabled", result.stderr)

    def test_private_and_wrong_generated_roots_cannot_be_included(self) -> None:
        for path in (".agents", "site"):
            with self.subTest(path=path):
                self.write_config(f"enabled: true\ninclude: [{path}]\nrequired: [{path}]\nexclude: []\n")
                result = self.run_builder()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("cannot be published", result.stderr)

    def test_public_docs_can_be_included(self) -> None:
        self.write_config("enabled: true\ninclude: [docs]\nrequired: [docs/public.md]\nexclude: []\n")
        result = self.run_builder()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.output / "docs" / "public.md").read_text(), "public\n")

    def test_parent_traversal_is_rejected(self) -> None:
        self.write_config("enabled: true\ninclude: [../outside]\nrequired: [public/artifact.txt]\nexclude: []\n")
        result = self.run_builder()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unsafe include path", result.stderr)

    def test_missing_required_path_fails(self) -> None:
        self.write_config("enabled: true\ninclude: [public]\nrequired: [missing.txt]\nexclude: []\n")
        result = self.run_builder()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing required path", result.stderr)


if __name__ == "__main__":
    unittest.main()
