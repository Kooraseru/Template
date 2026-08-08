#!/usr/bin/env python3
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PUBLIC_DOCS = ROOT / "docs"
STAGING = ROOT / ".generated" / "docs-source"
DEFAULT_SITE = ROOT / ".generated" / "site"
ROOT_POLICIES = ("SOURCE.md",)


def stage_public_docs() -> None:
    if not PUBLIC_DOCS.is_dir():
        raise SystemExit(f"Missing public documentation directory: {PUBLIC_DOCS}")
    shutil.rmtree(STAGING, ignore_errors=True)
    shutil.copytree(PUBLIC_DOCS, STAGING)
    for name in ROOT_POLICIES:
        source = ROOT / name
        if not source.is_file():
            raise SystemExit(f"Missing public policy: {name}")
        shutil.copy2(source, STAGING / name)
    contributing = ROOT / ".github" / "CONTRIBUTING.md"
    if not contributing.is_file():
        raise SystemExit("Missing public contributor policy: .github/CONTRIBUTING.md")
    staged_contributing = STAGING / "CONTRIBUTING.md"
    shutil.copy2(contributing, staged_contributing)
    contributing_text = staged_contributing.read_text(encoding="utf-8")
    contributing_text = contributing_text.replace("../SOURCE.md", "SOURCE.md")
    contributing_text = contributing_text.replace("../docs/", "")
    staged_contributing.write_text(contributing_text, encoding="utf-8", newline="\n")

    # Repository-relative policy links in docs/index.md become staging-root links.
    index = STAGING / "index.md"
    text = index.read_text(encoding="utf-8")
    for name in ROOT_POLICIES:
        text = text.replace(f"../{name}", name)
    index.write_text(text, encoding="utf-8", newline="\n")


def main() -> None:
    stage_public_docs()
    command = [
        sys.executable,
        "-m",
        "mkdocs",
        "build",
        "--strict",
        "--config-file",
        str(ROOT / ".github" / "mkdocs.yml"),
        "--site-dir",
        str(DEFAULT_SITE),
    ]
    raise SystemExit(subprocess.run(command, cwd=ROOT, check=False).returncode)


if __name__ == "__main__":
    main()
