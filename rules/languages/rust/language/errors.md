# Rust errors and failure paths

Use errors to communicate *why* an operation could not complete. Treat invalid user/environment input differently from broken internal invariants.

```rust
fn load_config(path: &Path) -> Result<Config, LoadError> {
    let text = std::fs::read_to_string(path)?;
    let config = parse_config(&text)?;
    Ok(config)
}
```

- Use `Result<T, E>` for recoverable failures. Use `Option<T>` when not finding something is ordinary, not an error.
- Use `?` for direct propagation; translate or add context when crossing a domain boundary.
- Reserve `panic!`, `unreachable!`, `unwrap`, or `expect` for justified, documented invariants (including tests), not external input.
- Avoid swallowing an error to make a guard appear neat: `if let Ok(value) = work()` can hide failures.
- Match specific variants when recovery differs; otherwise propagate.
- Do not format security-sensitive values or key material into error strings.

```rust
let session = request.session.as_ref().ok_or(Error::MissingSession)?;

if !session.authorized() {
    return Err(Error::Forbidden);
}

commit(request)?
```

On failure, leave resources and state consistent. Rust's owned resources and `Drop` help, but transactions and remote side effects still require explicit rollback or compensation.
