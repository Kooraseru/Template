# OOP-style ownership in Rust

Rust does not require class inheritance to model objects. A `struct` with inherent `impl` methods can own instance identity, invariants, resources, and lifetime.

Use an object-style shape when the useful question is:

> Which independently constructed instance owns this resource and its changes?

```rust
struct AudioSession {
    stream: Stream,
    paused: bool,
}

impl AudioSession {
    fn pause(&mut self) -> Result<(), Error> {
        if self.paused {
            return Ok(());
        }
        self.stream.pause()?;
        self.paused = true;
        Ok(())
    }
}
```

Methods express legitimate changes to owned state. There is no reason to make every utility function a method or every record an object. `Drop` can release owned resources; fallible teardown needs explicit APIs because `Drop::drop` cannot report an ordinary `Result`.

Interfaces and shared behavior are modeled with [traits](traits.md) and composition, not forced inheritance hierarchies.

[Example owned object](examples/session.rs) illustrates one possible shape; adapt it to the project’s actual contracts.
