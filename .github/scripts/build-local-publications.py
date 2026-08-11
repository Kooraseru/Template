#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BUILDER = Path(__file__).with_name("build-publication.py")
CONFIG = ROOT / ".github" / "publication" / "config.yml"


def run(
    command: list[str],
    *,
    capture: bool = False,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        capture_output=capture,
        check=False,
        env=env,
    )


def git_value(*arguments: str) -> str:
    result = run(["git", *arguments], capture=True)
    if result.returncode:
        raise SystemExit(result.stderr.strip() or f"git {' '.join(arguments)} failed")
    return result.stdout.strip()


def snapshot_commit() -> tuple[str, bool]:
    head = git_value("rev-parse", "HEAD")
    status = git_value("status", "--porcelain", "--untracked-files=all")
    if not status:
        return head, False

    with tempfile.TemporaryDirectory() as temporary:
        index = Path(temporary) / "index"
        environment = dict(os.environ)
        environment["GIT_INDEX_FILE"] = str(index)
        for command in (["git", "read-tree", "HEAD"], ["git", "add", "-A", "--", "."]):
            result = run(command, capture=True, env=environment)
            if result.returncode:
                raise SystemExit(result.stderr.strip() or f"{' '.join(command)} failed")
        tree_result = run(["git", "write-tree"], capture=True, env=environment)
        if tree_result.returncode:
            raise SystemExit(tree_result.stderr.strip() or "git write-tree failed")
        tree = tree_result.stdout.strip()

    head_date = git_value("show", "-s", "--format=%aI", "HEAD")
    environment = dict(os.environ)
    environment.update({
        "GIT_AUTHOR_DATE": head_date,
        "GIT_COMMITTER_DATE": head_date,
    })
    result = run(
        [
            "git",
            "-c",
            "user.name=Local Publication Snapshot",
            "-c",
            "user.email=local-publication@invalid",
            "commit-tree",
            tree,
            "-p",
            head,
            "-m",
            "Local publication snapshot",
        ],
        capture=True,
        env=environment,
    )
    if result.returncode:
        raise SystemExit(result.stderr.strip() or "git commit-tree failed")
    return result.stdout.strip(), True


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build local pre-release and release payloads from the current source state."
    )
    parser.add_argument("--version", required=True)
    parser.add_argument("--generated-at")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    branch = git_value("branch", "--show-current")
    if branch != "source":
        raise SystemExit(f"Local publication must run from source, got {branch or 'detached HEAD'}")
    source_commit, is_snapshot = snapshot_commit()
    generated_at = args.generated_at or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    for channel in ("pre-release", "release"):
        destination = ROOT / ".generated" / "repo" / channel
        result = run(
            [
                sys.executable,
                str(BUILDER),
                "--source",
                str(ROOT),
                "--destination",
                str(destination),
                "--config",
                str(CONFIG),
                "--channel",
                channel,
                "--version",
                args.version,
                "--source-commit",
                source_commit,
                "--generated-at",
                generated_at,
            ]
        )
        if result.returncode:
            raise SystemExit(result.returncode)

    source_kind = "temporary working-tree snapshot" if is_snapshot else "source HEAD"
    print(f"Built local publication payloads for {args.version} from {source_kind} {source_commit}")


if __name__ == "__main__":
    main()
