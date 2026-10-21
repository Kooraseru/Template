# Public releases

## Selection and types

Exactly two public types exist: Release for `MAJOR.MINOR.PATCH` and Pre-Release for
`MAJOR.MINOR.PATCH-pre.N`. Derive the type from the version. Tags equal version
strings. No channels, moving tags, aliases, or separate persistent identities.

`publication/releases/versions.toml` selects explicit versions and full source commit
SHAs. An empty list selects none. Commits belong to source history. Optional `from`
defaults to `beginning`; an explicit ancestor start is excluded from the range.
Optional `notes` names an existing relative controller Markdown file. Manual
selection supports paired version and full source-SHA overrides.

## Publication behavior

Versions support replacement. Identical publication is a no-op; changed content
reconciles that version and its source tag. Promotion creates a new stable version
without modifying the prerelease. Unrelated historical releases and tags remain
unchanged.

Only executable payloads are attached. Reports and receipts remain internal.
Source-only releases use GitHub's generated source archives. Each public release
links an Announcements discussion.

Verify a draft before publication. Failure cleanup may remove only an unpublished
draft owned by the failing attempt. Do not roll back existing tags or published
versions after uncertain API responses. Internal validation drafts are transport,
not public release types.

## Assembly and notes

Internal assembly lives under `build/releases/<version>/`. Its manifest records
version, source, and build identity. Transient controller and receipt locations
remain in an internal publication manifest. Normalize archive timestamps and
ownership so restaging identical builds preserves payload bytes.

Notes retain authored text, linked merged PRs, a Full Changelog link, and co-author
credits. Normalize Git authors and Co-authored-by trailers using the selected
snapshot's `.mailmap`; canonical emails remain internal. Bot exclusions belong to
the release policy. Do not add a duplicate contributors box or decorative dot
separators. Registry packages are outside scope.

Reference: https://semver.org/spec/v2.0.0.html
