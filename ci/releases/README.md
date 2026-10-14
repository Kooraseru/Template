# Release channels

Configure `channels.toml`; enable generation/publication in `ci/config.toml`.
Canary initially selects `commit = "latest"` and `from = "beginning"`.
Stable and beta remain commented examples until an admin selects full SHAs.
Ranges exclude the start and include the selected commit. Optional `notes` adds
an authored introduction; a configured missing file fails generation.
The 10.1.2026 record remains an unpublished draft.

Channels are movable GitHub tags/releases. Stable is a normal release; beta and
canary are prereleases. The source SHA is explicit in the body and metadata.
A failing or unfinished newest commit leaves the previous canary published.
The publisher rechecks source freshness and protection before promotion.

Normal builds check the current change. Additional distinct selections build
their exact source snapshots, using their declared build configuration, target
definitions, and image recipes with the current CI execution scripts. Cache
reuse requires an accepted admin receipt with matching target, source identity,
build fingerprint, execution evidence, and manifest checksums. Missing, expired,
legacy, or incompatible artifacts wait for an admin validation request rather
than automatically scheduling another hosted build. See ../receipts/README.md.

Output lives under `build/releases/<channel>/<SHA>/`. Inspect `notes.md`,
`release.json`, `packages.tar.gz`, PNGs, and `graph.html`. With no package paths
configured, this template contains no application payload. Published assets are
qualified by SHA and generation to stage replacements before deleting old ones.

The body contains optional authored text, linked changes, graph, then credits.
`changes.md` contains the complete commit list and file statistics; the body
shows up to 80 commits. PNGs contain 100 graph rows per page; self-contained HTML
contains the complete interactive graph. Credits include authors and
Co-authored-by trailers, normalized through the selected snapshot's .mailmap.
Names are public; canonical emails stay internal. Bot filters and pagination
defaults are declared in `policy.json`. GitHub automatic PR notes are not used.

Publication uses the automatic workflow token. New assets are checksum verified
before changing the channel. Failures restore the previous tag/body and remove
staged assets; incomplete recovery fails explicitly. Multiple GitHub API calls
are not an atomic transaction. Publication is serialized per channel; repeating
an already verified generation is a no-op.

## Required source protection

Each consuming repository installs both JSON rulesets under `protection/`
through GitHub Settings / Rules / Rulesets / Import. Templates do not transfer
these settings. The checks ruleset requires PRs, the GitHub Actions `gate` check,
up-to-date checks, and no force pushes or deletion, with no bypass actors.
The update ruleset grants repository admin role (ID 5) a PR-only bypass.
Together, only admins can merge source PRs and nobody can push source directly.
Zero required approvals permits a sole admin to merge their own passing PR.

Admin CLI setup (no token stored in the repository):

```powershell
gh api --method POST repos/OWNER/REPO/rulesets --input ci/releases/protection/source-checks.json
gh api --method POST repos/OWNER/REPO/rulesets --input ci/releases/protection/source-admins.json
```

Official publication requires these protections. Build and PR checks need no
admin credentials or inherited environments. Rulesets protect source edits,
including the release list; .gitattributes is not access control. Existing tag
restrictions remain authoritative.

Reference: https://docs.github.com/en/rest/repos/rules

GitHub hides bypass actors from ordinary workflow tokens. After setting up the
rulesets, a repository admin runs `node ci/releases/cli.mjs attest-protection`
using their existing GitHub CLI login. This enrolls a non-secret
`CI_SOURCE_PROTECTION` repository variable. Publication compares the complete
admin-verified snapshot against current ruleset IDs, visible contents, and update
times. Missing or changed protection fails closed. Refresh the snapshot after
any ruleset edit, including a temporary admin bypass and its restoration.
Templates do not transfer this repository variable; enroll it in each repository.
No PAT, signing key, or publication secret is stored in the template.

## Local previews

Use the actual workflow through act/GitHub Local Actions. Select Linux targets
and required images in an isolated standalone source checkout, then commit its
preview configuration. Preserve the full baseline in the development checkout.
A matrix filter alone does not change the release's expected target list.
Native Windows/macOS jobs require their GitHub runners. Local runs suppress all
publication, even when publish is true.
