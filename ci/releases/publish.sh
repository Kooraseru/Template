#!/usr/bin/env bash
set -euo pipefail
source ci/access/require-publication.sh

version="$(node <<'NODE'
const fs = require("fs");
const record = JSON.parse(fs.readFileSync("build/releases/release.json", "utf8"));
if (typeof record.version !== "string"
    || !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(record.version)) {
  throw new Error("Invalid generated release version");
}
process.stdout.write(record.version);
NODE
)"
if gh release view "$version" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
  echo "Release already exists; immutable release retained."
else
  # Refuse to create a release from a pre-existing tag at another commit.
  tag_commit="$(gh api "/repos/$GITHUB_REPOSITORY/git/ref/tags/$version" --jq '.object.sha' 2>/dev/null || true)"
  if [ -n "$tag_commit" ]; then
    resolved="$(gh api "/repos/$GITHUB_REPOSITORY/commits/$version" --jq '.sha')"
    test "$resolved" = "$GITHUB_SHA"
  fi
  gh release create "$version" build/releases/packages.tar.gz --repo "$GITHUB_REPOSITORY" --target "$GITHUB_SHA" --title "$version" --notes-file build/releases/notes.md
fi
