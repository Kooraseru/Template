"""Trusted CI coordinator. Components own behavior; this only plans and invokes it."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

from contracts import ContractError, discover
from planning import matrix, project_github, resolve


def _root() -> Path:
    return Path(__file__).resolve().parents[2]


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _save(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _prepare(event: str) -> dict:
    validations, groups = resolve(discover(_root()), event)
    groups = project_github(groups, event)
    return {"event": event, "sha": os.environ.get("GITHUB_SHA", ""),
            "validations": validations, "groups": groups}


def _invoke(task: dict, event: str) -> bool:
    args = [os.environ.get("CI_LUNE", "lune"), "run", "ci/bootstrap/invoke.luau", task["entry"], event]
    print(f"::group::{task['identity']}", flush=True)
    try:
        execution = subprocess.run(args, cwd=_root(), check=False)
        return execution.returncode == 0
    except OSError as error:
        print(f"::error::{task['identity']}: {error}", file=sys.stderr)
        return False
    finally:
        print("::endgroup::", flush=True)


def _execute(tasks: list[dict], event: str) -> tuple[list[dict], bool]:
    status: dict[str, str] = {}
    results: list[dict] = []
    for task in tasks:
        blocked = [needed for needed in task["needs"] if status.get(needed) != "passed"]
        if blocked:
            state = "blocked"
            print(f"::error::{task['identity']} blocked by {', '.join(blocked)}")
        else:
            passed = _invoke(task, event)
            missing = [path for path in task["outputs"] if not (_root() / path).exists()]
            if passed and missing:
                print(f"::error::{task['identity']} did not produce: {', '.join(missing)}")
            state = "passed" if passed and not missing else "failed"
        status[task["identity"]] = state
        results.append({"identity": task["identity"], "status": state})
    return results, all(result["status"] == "passed" for result in results)


def _outputs(values: dict[str, str]) -> None:
    destination = os.environ.get("GITHUB_OUTPUT")
    if destination:
        with open(destination, "a", encoding="utf-8") as output:
            for name, value in values.items():
                if "\n" in value:
                    raise ContractError(f"multiline job output: {name}")
                output.write(f"{name}={value}\n")
    for name, value in values.items():
        print(f"{name}: {value}")


def plan(event: str, destination: Path) -> None:
    document = _prepare(event)
    privileged = matrix(document["groups"], "privileged")
    ordinary = matrix(document["groups"], "read")
    if privileged["include"] and (
        event != "workflow_dispatch" or os.environ.get("GITHUB_REF") != "refs/heads/source"
    ):
        raise ContractError("privileged plans require workflow_dispatch on the trusted source branch")

    results, valid = _execute(document["validations"], event)
    if not valid:
        raise ContractError(f"discovered planning-time validation failed: {results}")
    _save(destination, document)
    _outputs({
        "matrix": json.dumps(ordinary, separators=(",", ":")),
        "privileged_matrix": json.dumps(privileged, separators=(",", ":")),
        "has_work": str(bool(ordinary["include"])).lower(),
        "has_privileged": str(bool(privileged["include"])).lower(),
    })
    print(f"Planned {len(document['validations'])} validators and {len(document['groups'])} execution groups")


def run(source: Path, group_id: str, boundary: str, destination: Path) -> None:
    recorded = _load(source)
    expected = _prepare(recorded["event"])
    if recorded != expected:
        raise ContractError("plan and checked-out source differ; refusing to execute")
    if boundary == "privileged" and (
        recorded["event"] != "workflow_dispatch" or os.environ.get("GITHUB_REF") != "refs/heads/source"
    ):
        raise ContractError("privileged execution requires trusted manual source dispatch")
    groups = [group for group in recorded["groups"] if group["id"] == group_id]
    if len(groups) != 1 or groups[0]["boundary"] != boundary:
        raise ContractError(f"unknown or incorrectly permissioned group: {group_id}")
    results, passed = _execute(groups[0]["tasks"], recorded["event"])
    _save(destination / f"{group_id}.json", {
        "id": group_id, "sha": recorded["sha"], "boundary": boundary, "results": results,
    })
    if not passed:
        raise ContractError(f"{group_id}: one or more tasks failed or were blocked")


def reconcile(source: Path, directory: Path) -> None:
    document = _load(source)
    failures: list[str] = []
    expected_ids = {group["id"] for group in document["groups"]}
    observed_ids: set[str] = set()
    for path in sorted(directory.glob("*.json")) if directory.exists() else []:
        receipt = _load(path)
        group_id = receipt.get("id")
        if group_id not in expected_ids or group_id in observed_ids:
            failures.append(f"unexpected or duplicate group receipt: {group_id}")
            continue
        group = next(group for group in document["groups"] if group["id"] == group_id)
        expected_tasks = [task["identity"] for task in group["tasks"]]
        actual = receipt.get("results", [])
        if (receipt.get("sha") != document["sha"] or
            receipt.get("boundary") != group["boundary"] or
            [item.get("identity") for item in actual] != expected_tasks):
            failures.append(f"invalid group receipt: {group_id}")
        for item in actual:
            if item.get("status") != "passed":
                failures.append(f"{group_id}/{item.get('identity')}: {item.get('status')}")
        observed_ids.add(group_id)
    for missing in sorted(expected_ids - observed_ids):
        failures.append(f"missing group receipt: {missing}")
    if failures:
        raise ContractError("CI reconciliation failed:\n" + "\n".join(failures))
    print(f"Reconciled {len(expected_ids)} execution groups")


def main() -> int:
    parser = argparse.ArgumentParser()
    subcommands = parser.add_subparsers(dest="command", required=True)
    planning = subcommands.add_parser("plan")
    planning.add_argument("--event", required=True)
    planning.add_argument("--output", type=Path, required=True)
    execution = subcommands.add_parser("run")
    execution.add_argument("--plan", type=Path, required=True)
    execution.add_argument("--group", required=True)
    execution.add_argument("--boundary", choices=("read", "privileged"), required=True)
    execution.add_argument("--results", type=Path, required=True)
    reconciliation = subcommands.add_parser("reconcile")
    reconciliation.add_argument("--plan", type=Path, required=True)
    reconciliation.add_argument("--results", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == "plan":
            plan(args.event, args.output)
        elif args.command == "run":
            run(args.plan, args.group, args.boundary, args.results)
        else:
            reconcile(args.plan, args.results)
    except (ContractError, OSError, ValueError) as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
