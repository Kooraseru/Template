# Release publication policy

`settings.json` owns shared release settings and policy. Each direct release directory contains a `release.json` record and its notes. Records are discovered without a central list:

```json
{
  "release": {
    "on_existing": "replace"
  }
}
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

## Planned release milestones

Planned milestones live in `.github/config/issues/milestones/records/`; they are
synchronized independently and are never staged as releases. Each publishable
release has its own directory, for example `0.1.0/release.json`:

```json
{
  "version": "0.1.0",
  "sequence": 1,
  "prerelease": false,
  "previous_tag": "beginning",
  "notes": "notes.md"
}
```

Sequence is a unique positive integer and determines release order when
`previous_tag` is `previous`. `notes` names a Markdown file in the same
release directory. Shared format, source and asset defaults live in `settings.json`.

Milestones match by exact version title. Synchronization creates missing
milestones and updates only the declared fields (`status` controls open/closed
state). `released` closes a matching existing milestone and does not create one
if it is missing. Removing an entry never deletes or modifies its GitHub milestone.
Milestone synchronization runs on source pushes and requires the workflow's
`issues: write` permission; local runs validate the plan but skip remote writes.

## Compiled downloads

Declare deliverable globs in the release configuration:

```json
{
  "release": {
    "assets": ["build/run/ci-execution/artifacts/application/*.exe"]
  }
}
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
