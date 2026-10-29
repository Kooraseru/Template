# Luau directory module roots

A directory may expose one public module surface when it hides meaningful internal implementation.

- `init.luau` is the preferred modular directory head when the resolver supports directory imports (including Lune and common Rojo workflows).
- `index.luau` is permitted only when the project deliberately uses an explicit resolver convention. Do not assume every Luau runtime resolves a directory import to `index.luau`.
- Keep a standalone `name.luau` file until there are real internal modules or coordination that justify `name/init.luau`.
- Never create an empty or forwarding-only directory head merely to standardize appearance.

Keep imported directory heads side-effect-free except for explicitly declared lifecycle behavior; expose a coherent contract. Executable entry points remain explicit, and importing a module should not unintentionally launch an application, build, or CI operation.

When adopting a directory root, check import resolution in the actual target runtime rather than assuming Roblox, Lune, and custom loaders have identical behavior.
