# Rust module organization

Organize modules around domain responsibilities and stable public APIs, not arbitrary file counts.

Rust supports `mod.rs` and newer directory layouts with `name.rs` as the module root and `name/` for its submodules. Choose a consistent, legible style; don't create both competing roots for the same module.

Keep `pub` and `pub(crate)` surfaces narrow. Prefer private implementation submodules, explicit exports, and tests near their owner. Additional crates require a real package/dependency boundary, not a cosmetic directory split.
