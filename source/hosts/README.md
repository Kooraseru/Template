# Source-owned build hosts

A host exists only when this repository contains a buildable implementation for it.
Host names and architectures come from implementation paths, not a universal CI
catalogue or a JSON inventory.

An application can provide `<platform>/build.luau` and matching
`<platform>/targets/<architecture>/build.toml` under this directory. A host
implementation must expose its executable build contract and reference real
source manifests and toolchains; a target description on its own is not a host.
CI may discover and select declared implementations, but cannot invent one.

This template deliberately ships **zero host implementations**. Adding a target
requires implementing the host first, then connecting its discovery and build
validation. Until that work is complete, no host should be advertised as
supported, buildable, or verified. A successful static preflight alone is not
proof that a native toolchain or platform build succeeds.

Source code and target-specific dependencies belong under `source/`.
CI orchestration, artifact receipts, authorization, and publication remain
under `ci/` and `.github/`.
