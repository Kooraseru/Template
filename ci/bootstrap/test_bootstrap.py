"""Focused discovery and scheduling invariants; fixtures never become CI targets."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from contracts import ContractError, discover
from planning import matrix, project_github, resolve


class BootloaderTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "ci/components").mkdir(parents=True)

    def component(self, name: str, *, provides: list[str] | None = None,
                  requires: list[str] | None = None,
                  os_name: str = "linux", arch: str = "x64", enabled: bool = True,
                  events: list[str] | None = None, directory: bool = False) -> None:
        contract = {
            "provides": provides if provides is not None else [f"capability.{name}"],
            "requires": requires or [], "inputs": ["**/*.luau"], "outputs": [],
            "events": events or ["push", "pull_request", "workflow_dispatch"],
            "runtime": {"os": os_name, "architecture": arch},
            "enabled": enabled,
        }
        base = self.root / "ci/components" / name
        if directory:
            base.mkdir()
            base /= "init.luau"
        else:
            base = base.with_suffix(".luau")
        base.write_text("--!strict\n--[[ci-contract\n" + json.dumps(contract) +
                        "\nend-ci-contract]]\nreturn function() end\n")

    def planning(self, event: str = "push") -> tuple[list[dict], list[dict]]:
        return resolve(discover(self.root), event)

    def with_preflight(self) -> None:
        self.component("preflight", provides=["validation.preflight"])

    def test_child_addition_automatically_changes_matrix(self) -> None:
        self.with_preflight()
        self.component("compile", directory=True)
        _, initial = self.planning()
        self.assertEqual([task["identity"] for task in initial[0]["tasks"]], ["compile"])
        self.component("lint")
        _, added = self.planning()
        self.assertEqual(len(matrix(project_github(added, "push"), "read")["include"]), 2)

    def test_dependencies_share_one_runner_in_topological_order(self) -> None:
        self.with_preflight()
        self.component("build", requires=["capability.compile"])
        self.component("compile")
        _, groups = self.planning()
        self.assertEqual(len(groups), 1)
        self.assertEqual([task["identity"] for task in groups[0]["tasks"]], ["compile", "build"])

    def test_cross_runner_dependency_fails(self) -> None:
        self.with_preflight()
        self.component("build", requires=["capability.compile"], os_name="windows")
        self.component("compile")
        with self.assertRaisesRegex(ContractError, "cross-runner"):
            self.planning()

    def test_missing_duplicate_and_cycle_diagnostics(self) -> None:
        self.with_preflight()
        self.component("a", requires=["missing"])
        with self.assertRaisesRegex(ContractError, "missing required"):
            self.planning()
        (self.root / "ci/components/a.luau").unlink()
        self.component("a", provides=["capability.shared"])
        self.component("b", provides=["capability.shared"])
        with self.assertRaisesRegex(ContractError, "duplicate provider"):
            self.planning()
        (self.root / "ci/components/b.luau").unlink()
        (self.root / "ci/components/a.luau").unlink()
        self.component("a", requires=["capability.b"])
        self.component("b", requires=["capability.a"])
        with self.assertRaisesRegex(ContractError, "dependency cycle"):
            self.planning()

    def test_disabled_provider_and_ambiguous_child_fail_explicitly(self) -> None:
        self.with_preflight()
        self.component("a", enabled=False)
        self.component("b", requires=["capability.a"])
        with self.assertRaisesRegex(ContractError, "missing required"):
            self.planning()
        (self.root / "ci/components/b.luau").unlink()
        self.component("a", directory=True)
        with self.assertRaisesRegex(ContractError, "ambiguous component identity"):
            discover(self.root)

    def test_event_filter_and_batch_limit(self) -> None:
        self.with_preflight()
        self.component("manual", events=["workflow_dispatch"])
        _, groups = self.planning("push")
        self.assertEqual(groups, [])
        for index in range(257):
            self.component(f"item{index}")
        _, groups = self.planning("push")
        groups = project_github(groups, "push")
        self.assertEqual(len(groups), 256)
        self.assertEqual(sum(len(group["tasks"]) for group in groups), 257)


if __name__ == "__main__":
    unittest.main()
