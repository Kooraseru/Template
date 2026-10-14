# Release channels

The release list is `ci/releases/channels.toml`. Supported channels are stable,
beta, and canary. Stable and beta select full source commit SHAs. Only canary may
select `latest`, which resolves the newest source commit once per execution.

Every channel declares `from`. A SHA range excludes that start and includes the
selected commit. `beginning` includes all reachable history. Selected commits
must belong to source history; a SHA start must be their ancestor. Equal start
and endpoint is a valid empty range. Optional `notes` names an existing relative
Markdown file in the controller checkout; omitting it generates no introduction.

Channels are movable GitHub releases and tags. Stable is a normal release; beta
and canary are prereleases. No immutable-release policy is imposed. Publication
uses verified packages for the selected SHA, never packages from another commit.
If the newest canary commit fails or is still building, retain the previously
published SHA and assets. Recheck source freshness before updating the channel.

The body presents authored notes, changes, commit graph, and contributor names,
in that order. Credits cover Git authors and Co-authored-by trailers in the
exclusive-start range, normalized by the selected snapshot's .mailmap. Canonical
emails are internal identity keys and must not appear in generated public graph
or contributor metadata. Bot exclusions are declared in the release policy.

Native source rules require PRs and passing GitHub Actions gate checks without
direct-push bypass. A separate update restriction allows only repository admins
to merge via PR. Admins may merge their own PRs. All source changes follow this
policy, including the release list. Templates do not transfer rulesets: each
consumer imports them separately. Publication fails closed without them.

All operations belong to the single CI workflow. Local act runs generate
previews but never publish. CI images are workflow artifacts, not registry
packages. Deleting historical registry packages requires a separate reviewed
cleanup. Generated release state lives under build/releases/<channel>/<SHA>.

Artifact provenance includes source SHA, target, build-input fingerprint, and
checksums. Reuse requires a successful source-push run from this repository and
matching validated provenance; missing, expired, or incompatible artifacts are
rebuilt. Only the automatic repository GITHUB_TOKEN is needed for publication.
