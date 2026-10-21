# FFI and unsafe boundaries

FFI bridges Rust's safety model to external calling conventions, pointers, buffer layouts, and ownership rules. Treat the boundary as an **explicit adapter**, not as an extension of safe Rust assumptions.

- Prefer a small safe wrapper API over exposing raw pointers throughout the application.
- Use declared calling conventions and layout (`extern "C"`, `#[repr(C)]`) only when required by the external ABI.
- Validate lengths, nullability, alignment, thread affinity, and resource ownership before using external memory.
- Document each `unsafe` block with a concrete safety argument.
- Respect foreign allocation and destruction rules; don't free memory with the wrong allocator.
- Never assume code generation from a C header proves runtime safety.

An FFI module may own a stateful handle; that does not justify building the entire application as an unsafe object framework.

See [boundary contracts](boundaries.md). Application FFI is optional and unrelated to the repository's Rustless CI helper.
