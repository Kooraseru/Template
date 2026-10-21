# Rust records and construction

A record groups values that have a common meaning. Keep schema conversion and validation at the boundary where uncertain data enters.

```rust
struct WindowSize {
    width: u32,
    height: u32,
}

impl WindowSize {
    fn try_new(width: u32, height: u32) -> Option<Self> {
        if width == 0 || height == 0 {
            return None;
        }

        Some(Self { width, height })
    }
}
```

This method isn't OOP merely because it is in an `impl`; it enforces a data invariant. Private fields may prevent callers from constructing invalid values.

Use `#[repr(C)]` only when an actual FFI layout contract requires it. Keep serialization formats separate from unrelated internal defaults. Avoid replacing small records with heterogeneous string maps or tuples whose positions are hard to remember.
