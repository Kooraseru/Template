# Strict directive fixtures

- [Strict](valid/strict.luau) passes with the directive after the path header.
- [Nonstrict](invalid/non-strict.luau) highlights the conflicting directive.
- [Generated provenance](valid/generated-provenance.luau) passes. The check does not infer generated status from prose.

- [Decorative headers](invalid/decorative-headers.luau) reports four explicitly disallowed comment headers.
- [Unlisted header](invalid/unlisted-marker.luau) reports a marker that is not in the allowlist.
- [Approved markers](valid/approved-markers.luau) passes every name in the marker policy allowlist.
- [Header lookalikes](valid/header-lookalikes.luau) passes because approved headers, block prose, and strings are allowed.
- [Trailing marker](review/trailing-marker.luau) is an inline comment, so it produces no section-header warning.
