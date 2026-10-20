# Native CI primitives

The CI controller remains Luau. This executable supplies primitives whose exact
behavior matters across languages. Cargo dependencies are pinned and locked;
`config/tools/ruleset.json.native.toolchain` selects the hosted compiler. Run
`bash .github/integration/run.sh libraries/bootstrap/native.luau` to build it locally with Cargo installed.
Outputs and the source fingerprint live under the ignored `build/native/` tree.

The `numbers` operation accepts a JSON array of decimal strings through stdin and
returns a JSON array of ECMAScript number spellings. Luau transports binary64
values using 17 significant digits; ryu-js selects the shortest representation.
No receipt keys or fingerprint contents are passed through command arguments.

Object ordering, UTF-16 escaping, null/missing handling, JSON parsing and hashing
are owned by `libraries/bootstrap/canonical.luau`. The helper does not decide receipt acceptance
or publication eligibility.

The frozen reference bytes in `libraries/bootstrap/ruleset.json` were generated from the
existing JavaScript canonicalizer before switching release planning. Luau tests
compare UTF-8 hexadecimal bytes and SHA-256 digests, rather than decoded object
equivalence. An RFC 8032 public test seed also supplies a deterministic signature
vector for receipt authentication.

References: https://docs.rs/ryu-js/1.0.3/ryu_js/struct.Buffer.html
and https://www.rfc-editor.org/rfc/rfc8032#section-7.1.

The `sign` and `verify` operations use Ed25519 with PKCS#8/SPKI keys. Private key
material travels through stdin and never through generated source or arguments.
`keygen` creates an exclusive external key file with restrictive permissions;
`keyfile` resolves the real path and rejects keys inside the repository, including
paths using traversal or links. The CLI applies a private ACL on Windows.
`uuid` uses operating-system randomness for staging identifiers.

`png` renders generated SVG with the vendored JetBrains Mono font through Rust
resvg. It does not load system fonts and caps the output pixel budget. The original
font license is retained beside the font under `publication/releases/assets/`.
This replaces the Node renderer and its container, not application rendering.
