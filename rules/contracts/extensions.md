# Application extension boundaries

Plugin compatibility is bound to the application-owned host API shape. The host
owns supported capability identifiers, callable interfaces, execution mechanisms,
and permission vocabulary. Plugin metadata can request a subset of that surface;
it cannot extend the vocabulary, supply its own host policy, grant permissions,
or request unrestricted computer, shell, or administrator authority.

A recognized permission request is not authorization. The host independently grants
access and supplies restricted operations. Built-in status comes from trusted host
registration, never a user-controlled descriptor. An external execution mode,
including a mode named trusted, does not itself confer privilege.

Registrations must match declared capabilities and implement the host's required
methods. Reject missing, non-callable, undeclared, or unsupported members. Method
presence alone cannot establish argument/return semantics: applications validate
requests and responses against their capability-specific data contracts.

Plugin and Workshop contracts remain independent. Workshop is data-only, declares
assets and required providers, and cannot register executable capabilities or gain
permissions through metadata.

The template validates declarations and exposes an activation-boundary check for
host-provided registrations and grants. It does not implement an application
runtime, IPC protocol, permission broker, or sandbox. Applications must enforce
these boundaries during execution. A process boundary alone does not restrict
filesystem, network, or operating-system access. Untrusted native plugins require
an enforceable sandbox; hosts without one must decline execution. Sandboxed script
runtimes must expose only their restricted host API, without ambient OS authority.

Source build commands are authored build instructions, not the runtime plugin API.
Permission to compile a plugin is not permission to execute it with host authority.
