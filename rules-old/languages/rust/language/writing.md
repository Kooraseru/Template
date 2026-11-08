# Readable Rust source

Write Rust for a future maintainer who must understand **which states are valid, who owns resources, what happens on failure, and why an algorithm is correct**. Concision is useful until it obscures those answers.

## Make the main path visible

- Check blockers early when an early return or `continue` clarifies the rest of the operation.
- Use `match` for real alternatives, `let ... else` for necessary patterns, and `?` for straightforward error propagation.
- Give intermediate values names when they carry a contract, mathematical meaning, unit, or mutation.
- Use iterator combinators for genuinely simple transformations. Prefer explicit loops and named predicates when validation, errors, index relationships, or side effects complicate them.
- Do not force an algorithm into a single closure chain or macro invocation merely to reduce lines.
- Keep mutable scope narrow. Use a `struct` only if values belong together; use methods if behavior belongs to that type.

## Make complex operations navigable

When a method does multiple nontrivial jobs, readers must see **what each phase establishes**. Add short phase comments and consider separate, meaningfully named helpers. Document assumptions that later phases depend on.

```rust
/// Validates a rig before any playback resources are created.
///
/// # Errors
/// Rejects invalid dimensions, non-finite transforms, and invalid ancestry.
fn validate_rig(rig: &MotionRig) -> Result<()> {
    // Bound both collections before walking parent indices.
    validate_counts(rig)?;

    // Reject invalid numeric data before the renderer consumes transforms.
    for (index, node) in rig.nodes.iter().enumerate() {
        validate_transform(index, node)?;
    }

    // Ancestry must terminate without cycles or out-of-range parent indices.
    for index in 0..rig.nodes.len() {
        validate_parent_chain(index, &rig.nodes)?;
    }

    Ok(())
}
```

This is illustrative: names describe the contracts of helpers, not prescribed APIs. If a helper only forwards one obvious call, keep the operation inline.

### Dense expressions need explanation or extraction

A large `ensure!` expression or a chain like `iter().chain().map().sum()` can be correct and still difficult to maintain. If it establishes a non-obvious invariant, **name the invariant in a nearby comment** and consider a named predicate or helper. Preserve actionable error context (e.g. which rig node failed).

```rust
// A zero-length quaternion cannot be normalized reliably during playback.
ensure!(
    rotation_norm_squared > ROTATION_EPSILON,
    "invalid rotation at node {index}"
);
```

Do not replace purposeful comments with an unexplained helper call. Good source usually needs **both** meaningful names and an explanation of the constraint.

## API and implementation hygiene

- Public functions/types get `///` contract documentation, including relevant `# Errors`, `# Panics`, and `# Safety` sections.
- Complex private routines get a short intent/contract comment even if they are not exported.
- Important loops explain their termination condition and what makes index or pointer access safe.
- Significant constants need a rationale and units where meaningful; do not scatter unlabelled limits.
- Do not write a line-by-line prose duplicate of the code; explain the contract or design reason.
- Avoid generic `Manager`, `State`, and `Helper` names when an actual domain name is available.
- Prefer ordinary code over opaque macros, unchecked casts, and unreviewed `unwrap`/`expect`.

See [comment requirements](comments.md), [guard clauses](control-flow.md), and [structure selection](../structures/structure-system.md).
