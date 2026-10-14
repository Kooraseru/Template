#!/usr/bin/env bash
set -euo pipefail
source ci/access/require-publication.sh

mkdir -p build/repo
tar -xf build/repository.tar -C build/repo
node <<'NODE'
const fs = require("fs");
const record = JSON.parse(fs.readFileSync("build/repo/publication.json", "utf8"));
if (record.source !== process.env.GITHUB_SHA
    || record.repository !== process.env.GITHUB_REPOSITORY) {
  throw new Error("Publication artifact does not match this source run");
}
NODE
cd build/repo
git init --initial-branch=main
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git remote add origin "https://github.com/$GITHUB_REPOSITORY.git"
authorization="$(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\n')"
echo "::add-mask::$authorization"
current="$(git -c "http.https://github.com/.extraheader=AUTHORIZATION: basic $authorization" ls-remote origin refs/heads/source | cut -f1)"
test "$current" = "$GITHUB_SHA"
existing="$(git -c "http.https://github.com/.extraheader=AUTHORIZATION: basic $authorization" ls-remote origin refs/heads/main)"
if [ -n "$existing" ]; then
  git -c "http.https://github.com/.extraheader=AUTHORIZATION: basic $authorization" fetch origin main
  git reset --soft FETCH_HEAD
fi
git add --all
git commit --allow-empty -m "Generate publication from $GITHUB_SHA"
git -c "http.https://github.com/.extraheader=AUTHORIZATION: basic $authorization" push origin HEAD:main
