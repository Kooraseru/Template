# Preflight – read-only Luau analysis

Preflight belongs to CI but does not own source operations, component registration,
data routing, execution approval or publication. It observes all applicable saved
Luau files from Git inventory, without importing or executing their contents.

Run from the repository root:

- bash ci/run.sh preflight list – report available analysis passes.
- bash ci/run.sh preflight run – inspect saved Luau sources and return JSON evidence.

The initial executable pass delegates parsing, type checking, and ordinary Luau
type refinements to the actual analyzer. It accepts CI_LUAU_ANALYZER as an
executable path, otherwise uses luau-lsp. An unavailable analyzer is not a
passing result. No custom language parser or handwritten tests have been added.

## Target control-flow analysis

The next frontend boundary must expose real Luau syntax and call relationships,
then perform path-sensitive abstract interpretation:

1. Build a control-flow graph per function and resolve imported module shapes.
2. Fork the abstract state at each conditional, guard, exceptional exit and
   protected call. Terminated paths do not rejoin.
3. Track nilness, type refinements, known values, reachable operations and
   explicit uncertainty. Inspect callees when their implementations are known.
4. Merge successor states conservatively; use a terminating fixed-point/widening
   strategy for loops and recursion.
5. Explain a possible violation using its reachable predecessor path.

A successful assert refines only its successful branch. Its unhandled failure
remains a possible exceptional exit; pcall captures that exit. Opaque external
calls, dynamic code, unknown runtime state or an exhausted analysis budget must
remain unknown, never silently proven safe.

Results are matched by field shape and named capabilities – no numeric protocol
or schema version. Compiler diagnostics alone do not prove runtime safety, nor
do they replace actual platform builds and signed acceptance receipts.

Lune remains the orchestrator. It does not itself provide the Luau parser's
internal AST or control-flow graph; full path traces must wait for a verified
frontend interface rather than relying on regex approximations.
