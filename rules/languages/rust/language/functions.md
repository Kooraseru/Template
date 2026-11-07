# Rust functions and methods

Use a free function for behavior that doesn't require an owned receiver. Use an inherent `impl` method when behavior is naturally tied to an instance, and a trait when callers require a shared contract across distinct implementations.

```rust
fn normalize_name(input: &str) -> String {
    input.trim().to_owned()
}

impl Window {
    fn resize(&mut self, width: u32, height: u32) {
        self.size = Size { width, height };
    }

    fn size(&self) -> Size {
        self.size
    }
}
```

Use `&self` for reading, `&mut self` for mutation, and `self` for intentional consumption. Don't add a receiver just to make code appear “object-oriented.”

- Keep parameters and returns explicit; Rust type inference inside the body is generally sufficient.
- Prefer early guards to wrapping the entire operation in a positive `if`.
- Return domain types and errors rather than unrelated tuples of booleans and strings.
- Use `impl Trait` at call boundaries when the caller need not care about the concrete type.
- Keep free/private helpers near the functionality they serve. Public surface is defined by `pub`, not by artificial file sections.
- Constructors may use `new`, but use `try_new` or a domain-specific verb when validation can fail.

Functions that do one transformation can stay free functions or small return values. Don't manufacture structs solely to group a function and its name.
