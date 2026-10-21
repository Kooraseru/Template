# Procedural Rust services

Use a procedural shape when the file **coordinates ordered operations** around an external resource, workspace, or subsystem. This is suitable for deployment steps, file workflows, request handling, command execution, and domain services.

The coordinator owns sequence and validation; private helpers own individual transformations. Whether it uses a free function or a small context `struct` depends on retained state, not on a naming rule.

```rust
fn publish(request: &Request, client: &Client) -> Result<(), Error> {
    if !request.authorized {
        return Err(Error::Forbidden);
    }

    let package = assemble(request)?;
    verify(&package)?;
    client.publish(package)
}
```

- Put authorization and input checks before side effects.
- Keep retries, rollback, and partial-success behavior explicit.
- Inject dependencies when that makes contracts and testing clearer.
- Do not scatter a single workflow over dozens of forwarding wrappers.
- Avoid global registries for dependencies a caller can pass directly.
- Define the public operation at one coherent boundary.

When a service has independently constructed instances and owned resources, consult [objects](../oop/objects.md).

[Example procedural operation](examples/install_file.rs) illustrates the structure without adding a mandatory application or CI smoke test.
