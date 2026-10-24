# Validation

`run.luau` owns validation stage execution and evidence reporting. The single
`.github/workflows/ci.yml` workflow owns job orchestration. Run checks locally with
`bash ci/integration/run.sh ci/validation/run.luau`.

Repository/configuration checks, workflow controls, access policies, canonical
fingerprint bytes, receipt authentication, and release tooling are validated
before publication. Tests being migrated to the shared typed contract return
`Test.new(...)`; their execution and comparisons belong to `ci/libraries/testing/`.
Policies and operational catalogues are data, not boilerplate manifests required
for ordinary source modules. Existing JSON fixture readers supply test data; they do not establish compatibility with retired formats.

## Independent source contracts

`plugins.luau` validates exactly `id`, `provides`, `requires`, `permissions`, and
`entry`. The caller supplies recognized capabilities, permissions, execution modes,
and whether a registration is application-bundled. A user descriptor cannot gain
built-in authority by selecting `builtin`. Built-ins require `entry.name`;
workers/trusted entries require a package-relative `entry.path`. Version fields,
unrecognized fields and values, duplicate identifiers, unresolved dependencies,
cycles, and ambiguous providers are rejected. Explicit provider selection resolves
conflicts. Descriptor validation does not verify that implementation interfaces
actually register, authorize requested permissions, or sandbox executable code.

`workshop.luau` independently validates `id`, `name`, and nonempty `assets` with
`path` and `requires`. It accepts no plugin entry, permissions, or registrations.
Inventory checking rejects missing/undeclared/duplicate paths, escaping paths,
reported executable content, and file/count/byte limit violations. Provider
resolution requires an available provider or an explicit choice when ambiguous.
Inventory classification must come from trusted inspection of actual content, not
from claims inside the Workshop descriptor. These functions do not extract
archives, inspect application-specific formats, load active content, or implement
rollback or decoder isolation. Those remain application/runtime responsibilities.

No VRM/VRMA identifiers or application-specific payloads are built into the template.
Applications own their contracts under `source/api/plugin/` and `source/api/workshop/`
when needed; no empty API or language folders are required here.

## Luau policy

The configured infrastructure roots follow the checked-in `.kero` Luau guidance.
Modules return their named public table, or return a shared typed test suite.
Modules are strict, imports use PascalCase, public methods use PascalCase, private
helpers use camelCase, and output belongs to callers. The policy rejects logging
calls and casts to `any`; the analyzer verifies actual types. StyLua owns formatting.
Editor sourcemap generation is disabled for this non-Roblox infrastructure.

Canonical byte/signature vectors preserve the original signed representation,
including nulls, empty arrays, Unicode edge cases, number spelling, and key order.
Directory moves recognize historical receipt-contract/configuration paths without
changing historical releases, tags, or authenticated receipt bytes.

## Optional upstream template assessment

`template.luau` reads another checkout using the current upstream workflow rules,
configuration validators and Luau policy. It reports architecture drift without
executing downstream code. Its hosted adapter is `.github/workflows/template.yml`,
independent of CI and removable without altering publication gates. See the
[conformance contract](../rules/contracts/repository/template-conformance.md).

For a local checker assessment from this trusted Template checkout:

```sh
bash ci/integration/run.sh ci/validation/template.luau /path/to/subject UPSTREAM_COMMIT_SHA
```

This is a module check, not an extension workflow run. For workflow execution use
the extension entry point documented in the local-testing contract. Only tracked
regular files are consumed. JSON output defaults to `build/template-conformance.json`;
set `TEMPLATE_REPORT` to select an existing output directory.
