# Structural compatibility

Contracts are versionless. Determine compatibility from required fields and types,
validated relationships, supported capabilities, and permissions. A numeric schema,
format, protocol, or API revision must not select behavior or grant compatibility.
Do not add revision markers as a substitute for specifying the accepted structure.

Reject unsupported structures with actionable diagnostics. Define optional fields
and extension points explicitly; do not silently infer meaning from unfamiliar
fields. Capability declarations do not prove authorization or runtime enforcement.

Do not add retired-path lookup, old-format adapters, migration dispatch, or silent
normalization merely to keep historical inputs working. Historical data can remain
unchanged without remaining consumable by the current implementation. Rebuild or
regenerate evidence when it no longer satisfies the current contract.

Release versions identify software publications. Dependency versions, native
package metadata, action references, compiler pins, and image digests identify
external inputs. These are legitimate identifiers, not contract compatibility
revisions. Third-party API requirements remain external requirements.

Regression tests verify current behavior and invariants. Keep independent golden
bytes and signature vectors when exact representation matters. Synthetic numeric
fields inside frozen serializer vectors are input data, not active compatibility
policy; preserve their expected bytes. Do not add tests promising retired-format
support. Test missing or malformed data, unsupported capabilities, denied
permissions, and valid compatible structures instead.

Changes to signed or hashed structures change their authenticated bytes. Never
rewrite existing signed evidence to fit a new structure or bypass verification.
Issue fresh evidence and retain the cryptographic checks.
