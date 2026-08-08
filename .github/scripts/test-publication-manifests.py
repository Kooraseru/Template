#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("collect-publication-manifests.py")


class PublicationManifestTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def manifest(self, channel: str, **changes: object) -> Path:
        data: dict[str, object] = {
            "channel": channel,
            "version": "1.0.0",
            "sourceCommit": "a" * 40,
            "generatedAt": "2026-01-01T00:00:00Z",
        }
        data.update(changes)
        path = self.root / f"{channel}.json"
        path.write_text(json.dumps(data), encoding="utf-8")
        return path

    def run_collector(self, release: Path | None = None, pre_release: Path | None = None) -> subprocess.CompletedProcess[str]:
        command = [sys.executable, str(SCRIPT), "--output", str(self.root / "output.json")]
        if release:
            command.extend(["--release-manifest", str(release)])
        if pre_release:
            command.extend(["--pre-release-manifest", str(pre_release)])
        return subprocess.run(command, text=True, capture_output=True, check=False)

    def test_collects_both_channels(self) -> None:
        result = self.run_collector(self.manifest("release"), self.manifest("pre-release"))
        self.assertEqual(result.returncode, 0, result.stderr)
        output = json.loads((self.root / "output.json").read_text())
        self.assertEqual(output["release"]["sourceCommit"], "a" * 40)
        self.assertEqual(output["preRelease"]["channel"], "pre-release")

    def test_missing_channels_are_optional(self) -> None:
        result = self.run_collector()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads((self.root / "output.json").read_text()), {"release": None, "preRelease": None})

    def test_channel_mismatch_fails(self) -> None:
        result = self.run_collector(self.manifest("pre-release"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("channel mismatch", result.stderr)

    def test_invalid_source_commit_fails(self) -> None:
        result = self.run_collector(self.manifest("release", sourceCommit="short"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("full lowercase SHA", result.stderr)


if __name__ == "__main__":
    unittest.main()
