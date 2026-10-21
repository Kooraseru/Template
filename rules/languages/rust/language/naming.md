# Rust naming

Use Rust's own conventions rather than copying Luau's public `PascalCase` methods:

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

Don't use a leading underscore as a privacy marker; Rust visibility is `pub`, `pub(crate)`, and module scoping. Do not introduce unused bindings and silence them with `_name`; use the bare wildcard `_` for deliberately discarded pattern values, or remove the binding.

Keep renaming and module casing consistent with `rustfmt` and standard Rust linting, even when Luau's equivalent role uses different casing.
