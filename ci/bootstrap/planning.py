"""Backend-neutral dependency graph, then a conservative GitHub matrix projection."""

from __future__ import annotations

import heapq
from collections import defaultdict

from contracts import Component, ContractError


# Trusted GitHub-hosted runner capabilities, not an inventory of build targets.
# An administrator must explicitly approve other runner classes before use.
HOSTED = {
    ("linux", "x64"): "ubuntu-latest",
    ("linux", "arm64"): "ubuntu-24.04-arm",
    ("windows", "x64"): "windows-latest",
    ("windows", "arm64"): "windows-11-arm",
    ("macos", "arm64"): "macos-15",
    ("macos", "x64"): "macos-15-intel",
}
LIMIT = 256


def _topological(components: dict[str, Component], dependencies: dict[str, set[str]]) -> list[str]:
    successors: dict[str, list[str]] = defaultdict(list)
    incoming = {identity: len(dependencies[identity]) for identity in components}
    for identity, requirements in dependencies.items():
        for requirement in requirements:
            successors[requirement].append(identity)
    queue = [identity for identity, count in incoming.items() if count == 0]
    heapq.heapify(queue)
    ordered: list[str] = []
    while queue:
        identity = heapq.heappop(queue)
        ordered.append(identity)
        for successor in successors[identity]:
            incoming[successor] -= 1
            if incoming[successor] == 0:
                heapq.heappush(queue, successor)
    if len(ordered) != len(components):
        raise ContractError(f"dependency cycle involving: {sorted(set(components) - set(ordered))}")
    return ordered


def resolve(components: list[Component], event: str) -> tuple[list[dict], list[dict]]:
    """Return discovery-derived validation tasks and dependency-closed worker groups."""
    if event not in ("pull_request", "push", "workflow_dispatch"):
        raise ContractError(f"unsupported event: {event}")
    active = {c.identity: c for c in components if c.enabled}
    providers: dict[str, str] = {}
    for component in active.values():
        for capability in component.provides:
            if capability in providers:
                raise ContractError(f"duplicate provider for {capability}: {providers[capability]}, {component.identity}")
            providers[capability] = component.identity

    dependencies: dict[str, set[str]] = {}
    produced: dict[str, str] = {}
    for component in active.values():
        for path in component.outputs:
            if path in produced:
                raise ContractError(f"output collision at {path}: {produced[path]}, {component.identity}")
            produced[path] = component.identity
        deps: set[str] = set()
        for requirement in component.requires:
            if requirement not in providers:
                raise ContractError(f"{component.identity}: missing required capability {requirement}")
            deps.add(providers[requirement])
        dependencies[component.identity] = deps
    ordered = _topological(active, dependencies)

    selected = {identity for identity in ordered if event in active[identity].events}
    for identity in selected:
        for required in dependencies[identity]:
            if required not in selected:
                raise ContractError(f"{identity}: provider {required} does not apply to {event}")

    validators = {
        identity for identity in selected
        if any(capability.startswith("validation.") for capability in active[identity].provides)
    }
    workers = selected - validators
    if workers and "validation.preflight" not in providers:
        raise ContractError("nonempty CI requires a discovered validation.preflight provider")
    if workers and providers["validation.preflight"] not in validators:
        raise ContractError("validation.preflight must be enabled and applicable to this event")

    for identity in validators:
        component = active[identity]
        if dependencies[identity] - validators:
            raise ContractError(f"{identity}: planning-time validator depends on a worker")
        if (component.os, component.architecture, component.labels, component.boundary) != (
            "linux", "x64", (), "read"
        ):
            raise ContractError(f"{identity}: planning-time validation needs the read-only planning runner")

    parent = {identity: identity for identity in workers}

    def find(identity: str) -> str:
        while parent[identity] != identity:
            parent[identity] = parent[parent[identity]]
            identity = parent[identity]
        return identity

    for identity in workers:
        for required in dependencies[identity] & workers:
            left, right = active[identity], active[required]
            if (left.os, left.architecture, left.labels, left.boundary) != (
                right.os, right.architecture, right.labels, right.boundary
            ):
                raise ContractError(
                    f"unsupported cross-runner/boundary dependency: {required} -> {identity} "
                    f"({right.os}/{right.architecture}/{right.boundary} -> "
                    f"{left.os}/{left.architecture}/{left.boundary})"
                )
            parent[find(identity)] = find(required)

    connected: dict[str, list[str]] = defaultdict(list)
    for identity in ordered:
        if identity in workers:
            connected[find(identity)].append(identity)
    groups: list[dict] = []
    for members in connected.values():
        first = active[members[0]]
        groups.append({
            "runtime": {"os": first.os, "architecture": first.architecture,
                        "labels": list(first.labels)},
            "boundary": first.boundary,
            "tasks": [
                {"identity": identity, "entry": active[identity].entry,
                 "outputs": list(active[identity].outputs),
                 "needs": sorted(dependencies[identity] & workers)}
                for identity in members
            ],
        })
    groups.sort(key=lambda group: group["tasks"][0]["identity"])
    validation_tasks = [
        {"identity": identity, "entry": active[identity].entry,
         "outputs": list(active[identity].outputs),
         "needs": sorted(dependencies[identity] & validators)}
        for identity in ordered if identity in validators
    ]
    return validation_tasks, groups


def project_github(groups: list[dict], event: str) -> list[dict]:
    """Translate generic groups to hosted runners and enforce matrix limitations."""
    projected: list[dict] = []
    for group in groups:
        runtime = group["runtime"]
        runner = HOSTED.get((runtime["os"], runtime["architecture"]))
        if runtime["labels"] or not runner:
            raise ContractError(f"no approved GitHub runner satisfies: {runtime}")
        if group["boundary"] == "privileged" and event != "workflow_dispatch":
            raise ContractError("privileged work requires manual trusted dispatch")
        projected.append({**group, "runner": runner})
    if len(projected) > LIMIT:
        # Reserve one slot per execution shape, then spread independent work
        # across the remaining slots. Connected tasks have already been grouped.
        by_shape: dict[tuple[str, str], list[dict]] = defaultdict(list)
        for group in projected:
            by_shape[(group["runner"], group["boundary"])].append(group)
        if len(by_shape) > LIMIT:
            raise ContractError(f"{len(by_shape)} incompatible groups exceed GitHub's {LIMIT} limit")
        quota = {shape: 1 for shape in by_shape}
        for _ in range(LIMIT - len(quota)):
            shape = max(by_shape, key=lambda item: (len(by_shape[item]) - quota[item], item))
            if quota[shape] >= len(by_shape[shape]):
                break
            quota[shape] += 1
        batched: list[dict] = []
        for shape, source_groups in sorted(by_shape.items()):
            buckets = [
                {"runtime": source_groups[0]["runtime"], "runner": shape[0],
                 "boundary": shape[1], "tasks": []}
                for _ in range(quota[shape])
            ]
            for index, group in enumerate(source_groups):
                buckets[index % len(buckets)]["tasks"].extend(group["tasks"])
            batched.extend(buckets)
        projected = sorted(batched, key=lambda group: group["tasks"][0]["identity"])
    for index, group in enumerate(projected):
        group["id"] = f"group-{index:03d}"
    return projected


def matrix(groups: list[dict], boundary: str) -> dict:
    return {"include": [
        {"group": group["id"], "runner": group["runner"]}
        for group in groups if group["boundary"] == boundary
    ]}
