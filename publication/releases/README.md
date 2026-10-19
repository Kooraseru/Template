# Versioned releases

The public release system has exactly two GitHub release types:

| Type | Version and tag | GitHub prerelease flag |
| --- | --- | --- |
| Release | `1.2.0` | false |
| Pre-Release | `1.3.0-pre.1` | true |

Versions follow `MAJOR.MINOR.PATCH`, optionally followed by `-pre.N`. Numeric
identifiers have no leading zeroes. The prerelease counter is a non-negative
integer. No other prerelease identifiers, build metadata, floating source selectors
or version aliases are accepted. Public tags are exactly the version string.

## Explicit version and source selection

`versions.toml` contains a publication selection list, not an inventory of all
historical releases. The template starts with `releases = []`, so normal source
pushes do not invent or automatically number a public release. Enable generation
and publication through `release.enabled` and `release.publish` in `config/project.toml`.
Replace the empty list with entries such as:

```toml
[[releases]]
version = "1.3.0-pre.1"
commit = "<full 40-character source commit SHA>"
from = "beginning"
# notes = "publication/releases/records/introduction.md"
```

Each commit must belong to source history. Optional `from` defaults to `beginning`;
a full ancestor SHA excludes that starting commit and includes the selected commit.
An equal start and endpoint is a valid empty notes range. Optional `notes` names an
existing relative Markdown file in the trusted controller checkout. The historical
versioned draft notes remain untouched.

The manual CI panel keeps twelve dropdowns and adds paired optional Release version
and Release source commit text inputs. Leaving both blank uses `versions.toml`.
Supplying both explicitly selects one version and full source SHA. If that version
already has a configured entry, its notes and range are preserved. A new version
uses the default complete history range. Publish Release and Publish Pre-Release
filter selected versions by their derived GitHub type. They are output choices,
not persistent release identities. PR targets cannot publish public versions.

## Replacement and promotion

Publication reconciles the selected version's source tag, notes, type and executable
attachments. Identical content is a no-op. Changed content replaces that version,
including moving its tag when a different source commit is explicitly selected.
Only the selected version is changed. Replacement is not transactional: a failed
upload can leave a partially updated release; retry the same selection to repair it.
Promotion selects a new stable version and leaves the prerelease unchanged.
Each published release links an Announcements discussion. Enable Discussions and
create that category in repositories using this publisher.

## Builds, evidence and artifacts

Normal builds check the current source change. Additional distinct version source
selections build their exact snapshots with the current trusted controller. Cache
reuse still requires matching accepted administrator receipts, source identity,
build fingerprints, execution evidence and manifest checksums. Verified admin
source pushes or manual requests permit missing builds to execute. Publication
continues to require protected hosted source execution and fresh controller inputs.

Output lives under `build/releases/<version>/`. Only packaged native executables
and scripts with a shebang are uploaded to GitHub Releases. Libraries, reports,
metadata, receipts and package archives remain internal workflow artifacts.
Without executables, GitHub's automatic source archives are the only downloads.
Release notes list merged PRs with author handles, collapse direct changes, and link
the Full Changelog. Co-authored-by credits come only from commit trailers; no
duplicate Contributors section is emitted. Authored notes can supply thematic sections.

## Required source protection

Each consuming repository installs both source-protection definitions under `ruleset.json.protection`
through GitHub Settings / Rules / Rulesets / Import. Templates do not transfer
these settings. The checks ruleset requires PRs, the GitHub Actions `gate` check,
up-to-date checks, and no force pushes or deletion. The supplied baseline has no
bypass actors on that checks ruleset. The update ruleset grants repository admin
role (ID 5) a PR-only bypass. Consumers may instead allow the administrator role
an always-on bypass on either ruleset to support direct administrator source pushes.
CI accepts both configurations and rejects non-admin roles or apps in bypass lists.
Contributor updates still require the protected PR path; admin overrides are explicit.
Zero required approvals permits a sole admin to merge their own passing PR.

Admin CLI setup (no token stored in the repository):

```powershell
jq '.protection.source_checks' publication/releases/ruleset.json | gh api --method POST repos/OWNER/REPO/rulesets --input -
jq '.protection.source_admins' publication/releases/ruleset.json | gh api --method POST repos/OWNER/REPO/rulesets --input -
```

Official publication requires these protections. Build and PR checks need no
admin credentials or inherited environments. Rulesets protect source edits,
including the release list; .gitattributes is not access control. Existing tag
restrictions remain authoritative.

Reference: https://docs.github.com/en/rest/repos/rules

GitHub hides bypass actors from ordinary workflow tokens. After setting up the
rulesets, a repository admin runs `node publication/releases/cli.mjs attest-protection`
using their existing GitHub CLI login. This enrolls a non-secret
`CI_SOURCE_PROTECTION` repository variable. Publication compares the complete
admin-verified snapshot against current ruleset IDs, visible contents, and update
times. Missing or changed protection fails closed. Refresh the snapshot after
any ruleset edit, including a temporary admin bypass and its restoration.
Templates do not transfer this repository variable; enroll it in each repository.
No PAT, signing key, or publication secret is stored in the template.

## Local previews and verification

Use the same workflow through act/GitHub Local Actions. Select compatible Linux
targets and required images through manual controls; native Windows/macOS builds
require their corresponding hosted runners. Local runs never publish remotely.
Release assembly uses the Ubuntu job's Docker renderer and deterministic GNU tar.

Regression tests cover version parsing, explicit commit ancestry, empty selections,
manual overrides, identical reruns, version replacement, separate prerelease promotion,
historical tag preservation, partial-draft failures and unchanged protection checks.

Reference: https://semver.org/spec/v2.0.0.html
