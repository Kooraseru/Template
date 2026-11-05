# Bash code organization

Bash scripts do not have one mandatory file skeleton. First identify what the script owns: a short command wrapper, a project entry point, a reusable sourced library, or an environment-specific adapter.

Review a script in this order:

1. **Execution boundary:** Bash version, platform, caller, current directory, and expected external tools
2. **Inputs and fields:** caller parameters, environment values, defaults, fixed paths, and derived paths
3. **Command interface:** option arrays and argument ordering
4. **Control flow:** validation, failure propagation, cleanup, and output ownership
5. **Compatibility:** MSYS2 path conversion and native Windows process boundaries where applicable

Put related settings near one another, with descriptive names and one authoritative assignment for each field. Use a concise comment to explain each logical block's role, even in short scripts; do not comment on every individual assignment. Declare values before their first use when possible. Do not move runtime-dependent values above the checks they require merely to manufacture a declarations block.

Use a function when it owns a meaningful operation, needs locals, or is reused. A short entry point can remain top-level. A helper file should not execute its main operation when sourced. Do not split a small script into forwarding files just to mimic an application module structure.

Language rules own Bash syntax and behavior. The calling repository owns workflow names, directories, CLI flags, artifact lifetimes, and which tools it supports. Apply the shared [language system](../language-system.md) and [comment rules](../comments.md), without importing Luau-specific syntax or file banners.
