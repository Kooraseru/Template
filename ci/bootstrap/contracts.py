"""Read CI component contracts without importing or executing Luau."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path


HEADER = re.compile(
    r"\A(?:\ufeff)?(?:--!strict[^\n]*\n)?\s*--\[\[ci-contract\r?\n"
    r"(?P<body>.*?)\r?\nend-ci-contract\]\]",
    re.DOTALL,
)
CAPABILITY = re.compile(r"^[a-z][a-z0-9_.:-]*$")
IDENTITY = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9_-]*$")
EVENTS = {"pull_request", "push", "workflow_dispatch"}
FIELDS = {"provides", "requires", "inputs", "outputs", "events", "runtime", "boundary", "enabled"}


class ContractError(ValueError):
    pass


@dataclass(frozen=True)
class Component:
    identity: str
    entry: str
    provides: tuple[str, ...]
    requires: tuple[str, ...]
    inputs: tuple[str, ...]
    outputs: tuple[str, ...]
    events: tuple[str, ...]
    os: str
    architecture: str
    labels: tuple[str, ...]
    boundary: str
    enabled: bool


def _object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ContractError(f"duplicate contract field: {key}")
        result[key] = value
    return result


def _strings(value: object, label: str, pattern: re.Pattern[str] | None = None) -> tuple[str, ...]:
    if not isinstance(value, list) or any(not isinstance(item, str) or not item for item in value):
        raise ContractError(f"{label} must be an array of nonempty strings")
    if len(value) != len(set(value)):
        raise ContractError(f"duplicate {label}")
    if pattern and any(not pattern.fullmatch(item) for item in value):
        raise ContractError(f"invalid {label}: {value}")
    return tuple(value)


def _paths(value: object, label: str) -> tuple[str, ...]:
    paths = _strings(value, label)
    for path in paths:
        if path.startswith("/") or "\\" in path or ":" in path or any(
            segment in ("", ".", "..") for segment in path.split("/")
        ):
            raise ContractError(f"unsafe {label}: {path}")
    return paths


def _read(root: Path, identity: str, entry: Path) -> Component:
    relative = entry.relative_to(root).as_posix()
    source = entry.read_text(encoding="utf-8")
    match = HEADER.match(source)
    if not match:
        raise ContractError(f"{relative}: missing leading ci-contract comment")
    try:
        raw = json.loads(match.group("body"), object_pairs_hook=_object)
    except (ValueError, json.JSONDecodeError) as error:
        raise ContractError(f"{relative}: invalid contract JSON: {error}") from error
    if not isinstance(raw, dict):
        raise ContractError(f"{relative}: contract must be an object")
    unexpected = set(raw) - FIELDS
    if unexpected:
        raise ContractError(f"{relative}: unknown fields: {sorted(unexpected)}")
    provides = _strings(raw.get("provides"), "provides", CAPABILITY)
    if not provides:
        raise ContractError(f"{relative}: provides cannot be empty")
    requires = _strings(raw.get("requires", []), "requires", CAPABILITY)
    inputs = _paths(raw.get("inputs", []), "inputs")
    outputs = _paths(raw.get("outputs", []), "outputs")
    events = _strings(raw.get("events", sorted(EVENTS)), "events")
    if not events or set(events) - EVENTS:
        raise ContractError(f"{relative}: unsupported or empty events")
    runtime = raw.get("runtime")
    if (not isinstance(runtime, dict) or not {"os", "architecture"} <= set(runtime)
        or set(runtime) - {"os", "architecture", "labels"}):
        raise ContractError(f"{relative}: runtime needs os, architecture, optional labels")
    os_name, architecture = (runtime[key] for key in ("os", "architecture"))
    if os_name not in ("linux", "windows", "macos") or architecture not in ("x64", "arm64"):
        raise ContractError(f"{relative}: unsupported runtime OS or architecture")
    labels = _strings(runtime.get("labels", []), "runtime labels", CAPABILITY)
    boundary = raw.get("boundary", "read")
    if boundary not in ("read", "privileged"):
        raise ContractError(f"{relative}: invalid boundary")
    enabled = raw.get("enabled", True)
    if type(enabled) is not bool:
        raise ContractError(f"{relative}: enabled must be boolean")
    return Component(identity, relative, provides, requires, inputs, outputs, events, os_name,
                     architecture, labels, boundary, enabled)


def discover(root: Path) -> list[Component]:
    """Only direct children are extension points. A directory owns its private internals."""
    directory = root / "ci" / "components"
    if not directory.is_dir():
        raise ContractError("missing ci/components extension point")
    found: dict[str, Component] = {}
    folded: set[str] = set()
    for child in sorted(directory.iterdir(), key=lambda path: path.name):
        if child.name == ".gitkeep":
            continue
        if child.is_symlink():
            raise ContractError(f"component symlinks are forbidden: {child}")
        if child.is_file() and child.suffix == ".luau":
            identity, entry = child.stem, child
        elif child.is_dir():
            identity, entry = child.name, child / "init.luau"
            if not entry.is_file() or entry.is_symlink():
                raise ContractError(f"{child.name}: component directory needs init.luau")
        else:
            raise ContractError(f"ineligible child under ci/components: {child.name}")
        if identity == "init" or not IDENTITY.fullmatch(identity):
            raise ContractError(f"invalid component identity: {identity}")
        if identity.casefold() in folded:
            raise ContractError(f"ambiguous component identity: {identity} (case or file/directory collision)")
        folded.add(identity.casefold())
        found[identity] = _read(root, identity, entry)
    return list(found.values())
