# Services and orchestrators

A service names a domain operation and its ordering requirements. An orchestrator selects **what runs**; an internal helper decides **how one step works**.

```rust
fn import_archive(source: &Path, destination: &Path) -> Result<(), ImportError> {
    validate_archive(source)?;
    prepare_destination(destination)?;

    if !destination.exists() {
        return Err(ImportError::MissingDestination);
    }

    extract_archive(source, destination)?;
    verify_import(destination)
}
```

The guard here is only meaningful if a missing destination is an error **after** `prepare_destination`; otherwise reject it earlier. Place guards at the true contract boundary rather than following a rigid ordering formula.

- Keep service effects and failure consequences observable.
- Prefer an explicit command map or `match` at the one public dispatcher.
- A child module may export a useful API but should not create a second CLI or executable.
- Keep policy decisions testable separately from shell and network execution.
- Avoid performing work just by importing a module.

Document multi-phase workflows with phase comments and narrow operation contracts, especially when publication, credentials, rollback, or partial success are involved.
