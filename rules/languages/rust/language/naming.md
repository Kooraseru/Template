# Rust naming

Follow Rust identifier conventions:

| Element | Naming |
| --- | --- |
| Local variables, parameters, functions, methods, modules, fields | `snake_case` |
| Types, structs, enums, traits, type parameters | `PascalCase` |
| Associated constants, module constants, statics | `SCREAMING_SNAKE_CASE` |
| Enum variants | `PascalCase` |
| Crates | `snake_case` in code; Cargo package names may be kebab-case |

```rust
const MAX_RETRIES: usize = 3;

struct BuildReceipt {
    source_sha: String,
    accepted_at: Timestamp,
}

impl BuildReceipt {
    fn can_publish(&self) -> bool {
        self.source_sha.len() == 40
    }
}
```

Names should reveal domain and responsibility. Prefer `receipt`, `selection`, `request`, `source_sha` over generic `state`, `data`, `manager`, `helper`. When the type or scope provides context, use a shorter name rather than repeating it in every field.

Don't use a leading underscore as a privacy marker; Rust visibility is `pub`, `pub(crate)`, and module scoping. Use `_` for intentionally discarded pattern values. A leading underscore on a binding (such as `_guard`) is legitimate when the value must stay owned or alive but not be referenced, or when a trait signature requires the parameter. Do not apply underscores as a privacy convention.

Keep module casing consistent with `rustfmt` and standard Rust linting. Name numeric constants for their domain meaning and document non-obvious bounds or units.
