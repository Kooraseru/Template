# Editor automation

Prefer supported editor-host commands, adapters, and language-server diagnostics to GUI simulation. Do not move the pointer, inject keystrokes, or silently change editor focus to run development tasks when a non-GUI interface is available.

An editor adapter must expose its permitted operations explicitly, preserve workspace trust, and avoid overlapping runs. Do not modify other extensions' code or private storage. Keep local credentials and machine-specific discovery data in ignored runtime state.

Preflight and diagnostics should check saved source and report the real provider's findings with accurate paths and positions. Do not invent editor-owned task history or present a detached external process as a native editor task.

Automatic checks must be non-destructive, scoped to changed inputs, debounced, and separated from publication authority. When an adapter or language provider is unavailable, report the limitation rather than claiming the check passed.
