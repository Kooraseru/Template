# Rust comments and navigability

**Comments are part of the implementation contract, not optional decoration for difficult code.** Code review should reject an exported or substantially complex Rust routine whose intent, important invariants, and failure behavior are only recoverable by reading every expression.

## Required documentation

Use `///` at public API boundaries (public types, methods, functions, traits, and externally consumed modules). Explain **the contract**, not merely the identifier. Include sections when relevant:

- `# Errors`: when a returned `Result` can fail and what class of error a caller should expect
- `# Panics`: any public operation that can panic under caller-relevant circumstances
- `# Safety`: obligations for unsafe functions, and a `// SAFETY:` rationale at each meaningful unsafe block
- `# Examples`: for non-obvious public APIs when a usage example materially clarifies their contract

For private, nontrivial routines use `///` or an immediately preceding `//` comment explaining the goal, assumptions, and returned result. Private one-line helpers with obvious behavior do not need forced Rustdoc.

## Required inline explanations

Add nearby `//` comments, regardless of visibility, for:

- **Multi-stage validation**: what a group of checks guarantees before the next phase
- **Indexed or parent-chain traversal**: sentinel meaning, bounds, maximum depth, cycle detection, and termination
- **Math/geometry**: reference frame, unit, normalization/epsilon policy, and why a threshold is safe
- **Stateful operations**: ordering, lifecycle, cleanup, cache invalidation, and partial-failure behavior
- **Security/FFI/unsafe**: trust boundary, caller assumptions, checks, and memory/resource ownership
- **Non-obvious optimization/workarounds**: the constraint that necessitates them
- **Macros hiding validation**: an explanatory comment above groups of `ensure!`, assertions, or dense predicates

Do not label every assignment or insert fake section banners. Use concise phase comments where they actually help a reader navigate long methods.

## Example: an input validator with hierarchy traversal

```rust
/// Checks the motion rig before creating or binding playback resources.
///
/// # Errors
/// Returns an error if a count, transform, rotation, or parent chain is invalid.
fn validate_motion_rig(rig: &MotionRig) -> Result<()> {
    // Limit allocation and traversal work before inspecting individual nodes.
    ensure!(!rig.nodes.is_empty(), "rig has no nodes");
    ensure!(rig.nodes.len() <= MAX_RIG_NODES, "too many rig nodes");

    // Verify that numeric transforms are usable by downstream animation math.
    for (index, node) in rig.nodes.iter().enumerate() {
        ensure!(
            node.translation.iter().all(|value| value.is_finite()),
            "node {index} has non-finite translation"
        );

        // A quaternion with zero length cannot be normalized for playback.
        ensure!(
            rotation_is_valid(node.rotation),
            "node {index} has invalid rotation"
        );
    }

    // Parent walks must terminate and stay within the validated node range.
    // A walk exceeding the node count implies a cycle or broken hierarchy.
    for index in 0..rig.nodes.len() {
        validate_parent_chain(index, &rig.nodes)?;
    }

    Ok(())
}
```

The example illustrates **comment location and granularity**, not a replacement for any existing validator. `MAX_RIG_NODES`, `rotation_is_valid`, and `validate_parent_chain` are project-owned contracts whose definitions must be documented. Parent-link sentinels (`-1`, `None`, etc.) must be explained where their representation is defined.

A traversal loop should explicitly convey which conditions are guaranteed before indexing into an array, why it terminates, and whether malformed input yields an error instead of silently stopping. A single “walk parents” comment is not sufficient for a subtle ancestor algorithm.

## Review standard

Ask: **Can a maintainer find the validation stages, understand the safety assumptions, and identify the reason for each unusual constraint without reconstructing the full algorithm?** If not, add contract comments, simplify the code, or extract a named helper.

Documentation may not be the only explanation for a fragile algorithm: prefer to make invalid states unrepresentable, add useful tests, and keep comments synchronized when the code changes. See [readable source](writing.md) and the shared [comment standard](../../comments.md).
