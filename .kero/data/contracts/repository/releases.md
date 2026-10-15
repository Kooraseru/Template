# Versioned release contract

Public publication has exactly two types: Release for `MAJOR.MINOR.PATCH` and
Pre-Release for `MAJOR.MINOR.PATCH-pre.N`. Types are derived from the version.
There are no public release channels, moving tags, alternate aliases or separate
persistent release identities. Public tags equal the selected version string.

The publication selection list is `ci/releases/versions.toml`. Each entry declares
an explicit version and full source commit SHA. An empty list publishes no public
version. Commits must belong to source history. Optional `from` defaults to
`beginning`; a SHA range excludes its ancestor start and includes the selected
commit. Optional `notes` references an existing relative controller Markdown file.
The manual workflow supports paired version and full source-SHA overrides.

Published content is immutable. Identical publication is a no-op; mismatched source,
notes, type, manifest or assets fails without mutation. The publisher never moves
or deletes tags and never patches published release content. Promotion from a
prerelease to a stable version creates a new release and tag, preserving the
prerelease. Historical releases and tags remain unchanged.

New publication uses a verified draft before making a version public. Only an
unpublished draft owned by the failing attempt may be removed. Existing tags and
published versions are never rolled back, even after an uncertain API response.
Internal `ci-validation-*` drafts remain validation staging with existing receipts,
retention and trust rules, independent of public version selection.

The single CI workflow preserves current build targets, accepted-artifact reuse,
execution evidence, publication gates and source protection. Administrator merge
or push approval authorizes missing builds to execute; it does not fabricate
successful build evidence. Public packages require verified matching accepted
receipts. Source PR/check rules and admin-only update or bypass permissions remain
mandatory. Local act execution can produce previews but cannot publish.

Public artifacts live under `build/releases/<version>/`. The public manifest
contains version, source and build identity; transient controller and receipt
locations remain in an internal publication manifest. Archive timestamps and
ownership are normalized so restaging identical builds preserves public bytes.

Notes retain authored text, changes, commit graph and contributor names. Credits
cover Git authors and Co-authored-by trailers in the selected range, normalized by
the selected snapshot's .mailmap. Canonical emails remain internal. Bot exclusions
are defined in the release policy. Registry packages remain out of scope.

Reference: https://semver.org/spec/v2.0.0.html
