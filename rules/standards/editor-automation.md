# Editor automation

Agents must not move the pointer, simulate keystrokes, change editor focus, or use
GUI automation to run development tasks. Use supported editor-host commands through
a non-GUI adapter. Do not inject task history or present an external process as an
editor-owned task. If the required adapter is unavailable, report that limitation.

Adapters must be explicit about which operations they expose, avoid arbitrary
command execution, preserve workspace trust, and refuse overlapping runs. Keep
session credentials and machine-specific discovery data in ignored runtime state.
Installation must not modify another extension's implementation or private storage.
