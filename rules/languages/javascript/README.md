# JavaScript system

JavaScript owns behavior, state transitions, asynchronous work, and integration
with browser APIs. A file chooses its role before its syntax shape: data
adapter, pure operation, DOM controller, or entry point. Keep a small public
surface and make state ownership explicit.

When editing JavaScript, choose in this order:

1. source and destination of data
2. owner and lifetime of mutable state
3. module or entry-point role
4. browser event and asynchronous boundaries
5. public API and failure behavior

[`modules.md`](modules.md) owns module composition and state.
[`browser-boundaries.md`](browser-boundaries.md) owns DOM, catalogs, events, and
network boundaries. Repository knowledge owns its actual endpoints, cookies,
and build paths.
