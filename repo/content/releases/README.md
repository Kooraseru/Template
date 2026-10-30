# Release publication policy

`releases.toml` owns release records, source commits, and shared policy:

```toml
[release]
on_existing = "replace"
```

The policy applies when either the Git tag or the GitHub Release already exists:

- `skip`: leave it untouched and continue.
- `fail`: stop before making changes.
- `replace` (default): point a mutable existing tag at the configured source
  commit and update the existing release's metadata/notes in place. Create a
  release when only its tag exists. Configured assets are uploaded or replaced; unrelated release assets remain untouched.

Replacement does not delete and recreate releases, bypass protection rules, or
unlock immutable releases. Unsupported replacement fails clearly. Tag and
release updates are separate GitHub operations: if a later request fails, an
earlier successful tag update can remain; the log reports that possibility.

GitHub Packages has its own records and policy in `../packages/`.

## Compiled downloads

Declare deliverable globs in the release configuration:

```toml
[release]
assets = ["build/*.exe"]
```

The current template builds Windows fixture executables; these are attached as
standalone downloads to demonstrate the pipeline. Consuming projects select their
own apps/archives with these globs. An entry may override `assets`, including `[]`
for a notes-only release. An omitted setting also produces a notes-only release.
No GitHub Packages record or registry format is involved.

Release staging waits for compilation, copies only matching regular files, and
records SHA-256 hashes. Configured globs matching no files, filename collisions,
or a release source commit different from the checked-out build are errors.

New releases with assets remain drafts until upload completes. Existing mutable
releases use `on_existing`: `skip` leaves the release and assets alone; `fail`
stops; `replace` updates configured filenames. Matching checksums avoid re-upload.
Replacement uploads and verifies a temporary file before deleting the previous
asset, then assigns its final name. If a later request fails, the verified upload
may retain its temporary name for recovery/retry. Protected/immutable releases
are never unlocked or deleted and recreated.