# Lifetimes

A lifetime records the validity relationship of references; it is not a runtime timer, resource scheduler, or ownership substitute.

Prefer owned return values when data must outlive the input. Prefer borrowed returns when a view into the input is precisely what callers need. Let lifetime elision work where the relationship is unambiguous.

```rust
fn chosen_label(primary: &str, fallback: &str, prefer_primary: bool) -> &str {
    // A named lifetime would be required: two independent input references.
    // See the corrected signature below.
    unreachable!()
}
```

With two independent inputs, state the relationship explicitly:

```rust
fn chosen_label<'a>(primary: &'a str, fallback: &'a str, prefer_primary: bool) -> &'a str {
    if prefer_primary { primary } else { fallback }
}
```

The first signature above intentionally illustrates an incomplete lifetime contract; do not copy it into production. In normal code, write only the complete signature.

Avoid putting borrowed references into persistent structs unless a caller truly owns the referenced data for the necessary lifetime. Document safety invariants wherever `unsafe` manipulates raw pointers or lifetimes.
