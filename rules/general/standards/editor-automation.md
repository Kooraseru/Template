# Editor automation

Prefer supported editor-host commands, adapters, and language-server diagnostics to GUI simulation. Do not move the pointer, inject keystrokes, or silently change editor focus to run development tasks when a non-GUI interface is available.

An editor adapter must expose its permitted operations explicitly, preserve workspace trust, and avoid overlapping runs. Do not modify other extensions' code or private storage. Keep local credentials and machine-specific discovery data in ignored runtime state.

Preflight and diagnostics should check saved source and report the real provider's findings with accurate paths and positions. Do not invent editor-owned task history or present a detached external process as a native editor task.

Automatic checks must be non-destructive, scoped to changed inputs, debounced, and separated from publication authority. When an adapter or language provider is unavailable, report the limitation rather than claiming the check passed.

## Codex and Workbench Bridge

Codex loads the root `AGENTS.md` in a Template project session. Read the linked policy for the area being changed. Keep the entry point short so each task loads only the rules it needs.

Review the shared Problems hooks in Codex under **Settings → Hooks** (or `/hooks` in the CLI). Once trusted, a new or resumed project session receives a compact Problems summary. Shell and patch tools take a baseline and report changes when available. Diagnostics can arrive after the tool returns, so an immediate empty delta is insufficient evidence that an edit is clean.

For a fresh snapshot, run `node dependencies/packages/editor/editorIntegration/client.cjs --problems` from the repository root. This uses the existing VS Code extension host without focusing or launching a window. If multiple sessions match, select the intended private discovery record using `WORKBENCH_BRIDGE_SESSION`. For clients that do not inherit that variable, write the record's absolute path to `.workspace/editor-problems/session-file.txt`. Keep the record and its credentials out of reports and Git.

## Unattended editor checks

Use scripts for repository edits and use the editor host for behavior that depends on VS Code. For quick actions, run an Extension Development Host test in a disposable checkout and query `vscode.executeCodeActionProvider` at the diagnostic range. For an actual edit, invoke the returned action in that checkout and assert the resulting buffer or files. For notification rendering, use an isolated graphical desktop with automation inside that environment.

Use a separate Windows VM or session for Windows UI tests. An alternate Win32 desktop is a candidate only after capture and input have been verified there. A separate `--user-data-dir` isolates VS Code settings but can still open a window on the current desktop. Configure the test profile with `chat.disableAIFeatures` enabled before launch and use a dedicated extension directory with only the extensions under test. If an isolated graphical session is unavailable, run the relevant CLI checks and report which editor behavior remains unverified.

Use deterministic commands for diagnostics, formatting, and verification. Give a smaller model a bounded task with exact files, relevant rules, and a command that checks the result. Use a stronger model for ambiguous changes or repeated failures.
