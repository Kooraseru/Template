# Concurrency and async responsibilities

Concurrency belongs to code that coordinates work across tasks/threads, synchronizes shared state, or transfers ownership through messages. It is not a default structure for ordinary asynchronous I/O.

Choose the simplest useful ownership model:

- Single owner, direct calls, no concurrency where practical
- Scoped threads/tasks for bounded parallel work
- Channels/message passing when an actor owns mutable resources
- Shared `Arc<T>` for genuinely shared immutable data
- `Mutex`/`RwLock` for unavoidable concurrent mutation, with narrow lock scope

Avoid creating a global scheduler, shared registry, or blanket `Arc<Mutex<_>>` graph just because a Rust framework supports it. Define cancellation, shutdown, and failure propagation before spawning background tasks.

The language-wide guard-first convention applies to task admission and early cancellation. Do not return early while accidentally leaving unmanaged tasks or locks.
