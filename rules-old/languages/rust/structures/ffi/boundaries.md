# Designing a safe FFI facade

Separate the unsafe foreign representation from validated Rust-facing types.

```rust
#[repr(C)]
pub struct RawDimensions {
    width: u32,
    height: u32,
}

struct Dimensions {
    width: u32,
    height: u32,
}

impl TryFrom<RawDimensions> for Dimensions {
    type Error = DimensionsError;

    fn try_from(raw: RawDimensions) -> Result<Self, Self::Error> {
        if raw.width == 0 || raw.height == 0 {
            return Err(DimensionsError::ZeroSize);
        }
        Ok(Self { width: raw.width, height: raw.height })
    }
}
```

The example uses plain values; real pointer-bearing ABI types need additional ownership and lifetime checks.

- Reject invalid external input before constructing trusted internal types.
- Keep raw handles private and encode destruction exactly once.
- Document whether callbacks may execute concurrently and what happens during shutdown.
- Do not let panics unwind across an FFI boundary unless the ABI and unwinding contract explicitly permit it.
- Test negative cases with invalid lengths, null pointers, resource teardown, and repeated calls where practical.

Use a deliberate FFI adapter only when external APIs require it, not as a way to avoid idiomatic Rust ownership.
