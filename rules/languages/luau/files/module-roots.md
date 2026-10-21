# Luau directory module roots

A directory may expose one public module surface, conceptually similar to Rust's `mod.rs`. Choose a root only when it hides meaningful internal implementation files.

- `init.luau`: use where the target runtime/module resolver treats a directory as an importable module (including Lune and common Rojo workflows).
- `index.luau`: an explicit project-level convention when import sites resolve that file by name or an established toolchain maps it. Do **not** assume every Luau resolver automatically resolves `require("./directory")` to `index.luau`.
- Other filenames are fine for private implementation modules.

Keep directory roots side-effect-free; export a coherent API. Executable entry points remain explicit (e.g. `ci/main.luau`), and importing a module must not run CI.

When adopting a directory root, update all import paths and run tests on the actual target runtime; don't infer portability from Roblox-specific behavior.
