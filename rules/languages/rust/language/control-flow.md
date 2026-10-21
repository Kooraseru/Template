# Guard-first control flow: “if not, not if”

**Default mental model:** establish when a function **cannot** continue, handle that condition, and leave the primary path unindented. The negation belongs to the *precondition* rather than to every `if` expression.

```rust
fn render(target: Option<&Target>) {
    let Some(target) = target else {
        return;
    };
    if !target.is_visible() {
        return;
    }

    target.render();
}
```

Compare the goal with deeply nested positive conditions:

```rust
// Avoid when the success path is needlessly buried.
if let Some(target) = target {
    if target.is_visible() {
        target.render();
    }
}
```

## Select the Rust guard that matches the meaning

| Situation | Prefer |
| --- | --- |
| Optional value cannot proceed | `let Some(value) = expression else { return; };` |
| Missing value is a real error | `let Some(value) = expression else { return Err(Error::Missing); };` or `.ok_or(Error::Missing)?` |
| Ordinary fallible operation | `operation()?` when error propagation is the contract |
| Disabled item in a loop | `if !item.enabled { continue; }` |
| Illegal state | `return Err(...)` or a meaningful assertion for an internal invariant |
| Several mutually exclusive variants | `match` with explicit arms, not unrelated repeated `if` checks |

```rust
fn publish(request: &Request) -> Result<Receipt, Error> {
    let session = request.session.as_ref().ok_or(Error::MissingSession)?;
    if !session.can_publish() {
        return Err(Error::PermissionDenied);
    }

    validate(request)?;
    write_receipt(request)
}
```

Rust's `?` is a guard in expression form: it passes through success and exits on failure. It is preferable to repeated `match Ok/Err` boilerplate when the error needs no special treatment.

## Do not turn the mnemonic into a rule against `if`

A positive branch is clearer when the *branch itself is the purpose*:

```rust
if cache.contains_key(&id) {
    return Ok(CacheOutcome::Reused);
}
```

Use `match` when variants deserve distinct behavior. Use `if let` when one pattern is the actual operation and the alternative needs no branch. Never write confusing double negatives merely to preserve `!`; rename negative predicates when possible.

Avoid stacking guards that silently discard important failures. A guard should say **return**, **continue**, **break**, or **error** deliberately. Preserve cleanup and transaction semantics; return early only after invariants are restored or via owned RAII guards.

Read [expressions](expressions.md) and [errors](errors.md) for choosing compact versus explicit forms.
