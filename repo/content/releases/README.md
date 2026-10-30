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
  release when only its tag exists. Existing release assets remain untouched.

Replacement does not delete and recreate releases, bypass protection rules, or
unlock immutable releases. Unsupported replacement fails clearly. Tag and
release updates are separate GitHub operations: if a later request fails, an
earlier successful tag update can remain; the log reports that possibility.

GitHub Packages has its own records and policy in `../packages/`.
