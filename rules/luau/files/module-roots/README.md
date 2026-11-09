# Luau directory module roots

A directory may expose one public module surface when it hides meaningful internal implementation.

- `init.luau` is the preferred modular directory head when the resolver supports directory imports (including Lute and common Rojo workflows).
- `index.luau` is permitted only when the project deliberately uses an explicit resolver convention. Do not assume every Luau runtime resolves a directory import to `index.luau`.
- Keep a standalone `name.luau` file until there are real internal modules or coordination that justify `name/init.luau`.
- Never create an empty or forwarding-only directory head merely to standardize appearance.

Keep imported directory heads side-effect-free except for explicitly declared lifecycle behavior; expose a coherent contract. Executable entry points remain explicit, and importing a module should not unintentionally launch an application, build, or CI operation.

When adopting a directory root, check import resolution in the actual target runtime rather than assuming Roblox, Lute, and custom loaders have identical behavior.

## Automated check

Template defaults to init.luau for directory heads. Rules flags files named index.luau so the resolver convention is explicit. If a source path deliberately uses index.luau, document that convention and set a file-scoped severity override to off for this rule. Runtime resolution and whether the module owns meaningful behavior still need review.

See the [fixture matrix](tests/TEST_MATRIX.md).
