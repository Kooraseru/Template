# Runtime child discovery with shape validation

## Discovery and identity

An owning directory is the source of truth for which interchangeable child components exist. Discover eligible direct children from that directory; derive each component's identity from its file or directory name. Consumers must not repeat those names in code, manifests, dispatch tables, CI matrices, or validation catalogues.

The parent may define its **entry path**, supported child shapes, reserved entry filenames, and contract. Those are structural rules, not an inventory of instances. Adding, renaming, or removing a conforming child should not require editing its parent or consumers.

Discover components recursively only where the owning contract declares a nested extension point. A normal implementation dependency is not automatically an interchangeable child. Keep discovery deterministic and make duplicate or ambiguous identities an error.

## Shape before use

Discovery finds candidates; validation establishes whether they conform. Validate required entries, data types, relationships, declared capabilities, and trust boundaries before using a candidate. An optional category may be absent; an invalid child that **is present** must produce an actionable error instead of disappearing from the available set.

Static shape checks do not prove that executable behavior succeeds. Actual execution still verifies runtime, platform, and external dependencies. When static analysis cannot prove a path safe, report the uncertainty instead of silently accepting or inventing behavior.

Do not execute untrusted discovered code merely to determine whether its shape is valid. Resolve trusted sources and security boundaries before loading or executing implementation code.

## Files and directories

Use a file for a component that only requires one module. Promote it to a directory when it genuinely needs multiple implementation modules, coordinated responsibilities, or a public module head. Never create a folder containing a placeholder entry file purely for visual consistency.

In Luau, a modular directory normally exposes `init.luau` as its head. A single-file sibling and a directory with `init.luau` are alternate representations of the same kind of component when their contracts match:

```text
components/
  x64.luau
  arm64/
    init.luau
    compiler.luau
    packaging.luau
```

The generic discoverer does not hardcode `x64` or `arm64`. It understands the `.luau` file shape and the directory-head shape. A simultaneous `name.luau` and `name/init.luau` must not silently override one another.

Other languages use their own established module entry conventions. This rule does not require every language to imitate Luau's filenames.

## Ownership

Keep behavior, configuration, and validation close to their actual owner. Shared behavior belongs to a shared contract; host-specific implementations belong to the host. Build images and toolchains are capabilities of the hosts that use them, not a global inventory that causes unused combinations to be built.

Keep source declarations, validation, and execution separate. Discovery is not a registry that needs manually entered components, and preflight is an analyzer of existing code, not the source of operational truth.
