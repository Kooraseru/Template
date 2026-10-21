# Rust system conventions

- Prefer simple crates and clear ownership boundaries over gratuitous workspaces.
- Express fallible behavior with typed `Result`; reserve panics for violated internal invariants.
- Favor explicit lifetimes and borrowing where they improve clarity, but do not introduce unnecessary cloning to appease the borrow checker.
- Keep `unsafe` behind small, documented interfaces, each with stated invariants.
- Do not introduce dependencies without a clear functional need.
- Run `cargo fmt`, `cargo clippy`, and relevant tests when Rust is an active project target, never as unconditional template smoke tests.
