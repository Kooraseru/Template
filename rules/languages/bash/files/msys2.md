# MSYS2 Bash and Windows boundaries

MSYS2 Bash follows Bash syntax while providing a POSIX-like environment on Windows. Do not treat MSYS2 paths, native Windows paths, and the arguments passed to Windows executables as interchangeable.

- In Bash code, use quoted POSIX-style paths such as `/c/...` or `/usr/...` where the active MSYS2 environment understands them. A Windows program may instead require a native path; convert at that boundary with `cygpath -w` or `cygpath -m` when needed.
- MSYS2 can rewrite path-looking arguments when launching native Windows executables. Inspect the receiving tool's expectations before applying `MSYS_NO_PATHCONV=1` or `MSYS2_ARG_CONV_EXCL`. Scope an override to the specific command rather than disabling conversion globally.
- Explicitly consider whether a resolved command is an MSYS2 program or a native `.exe`. Quoting preserves a Bash argument but does not prevent MSYS2's native-process conversion.
- Do not prepend `/usr/bin` to `PATH` universally. Prefer a known tool or a narrowly scoped path adjustment when command precedence is part of the script's contract.
- Use `#!/usr/bin/env bash` for scripts launched from the MSYS2 environment. Do not assume `bash`, `sh`, Git Bash, and PowerShell are equivalent runtimes.
- Keep machine-specific drive letters, user directories, and executable installation paths out of global conventions. Detect or document those requirements in the owning project.

Example of an intentionally scoped conversion boundary:

```bash
# Convert this path only at the native Windows executable boundary.
windows_output_dir="$(cygpath -w "$output_dir")"
native_tool.exe --output "$windows_output_dir"
```

When a native tool already accepts converted arguments from MSYS2, do not manually convert the same path again. Check behavior with the actual executable; command-line parsing and path handling differ among tools. Paths passed through JSON, environment variables, or subprocesses may follow different rules from ordinary command arguments.
