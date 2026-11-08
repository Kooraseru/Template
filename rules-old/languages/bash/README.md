# Bash conventions

These conventions apply to scripts that deliberately target Bash, including MSYS2 Bash on Windows. They are not rules for POSIX `sh`, PowerShell, or native Windows batch files.

Start with [the Bash system](bash-system.md). Use [script layout](files/scripts.md) for executable files, [arguments and expansions](language/arguments.md) for command calls, [naming](language/naming.md) for declarations, and [control flow](language/control-flow.md) for failure handling. Read [MSYS2 boundaries](files/msys2.md) when native Windows programs or Windows paths are involved.

Keep configuration fields grouped, plainly named, and visually scannable. Introduce each meaningful block with a short, preferably one-sentence comment explaining its purpose. Avoid decorative separators and comments that merely repeat the syntax. The universal [comment rules](../comments.md) still apply.
