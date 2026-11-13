#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
temp="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
archive="$temp/template-actionlint-$$.tar.gz"
directory="$temp/template-actionlint-$$"
trap 'rm -f -- "$archive"; rm -rf -- "$directory"' EXIT
curl -fLSs --retry 3 -o "$archive" https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_amd64.tar.gz
echo "8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8  $archive" | sha256sum -c -
mkdir -p "$directory"
tar -xzf "$archive" -C "$directory" actionlint
"$directory/actionlint" -shellcheck= .github/workflows/*.yml
node dependencies/packages/core/dependencyLoader/index.ts --exec luau.lute run ci/bootstrap/emitWorkflows.luau "$directory/generated"
"$directory/actionlint" -shellcheck= "$directory"/generated/*.yml
if [[ $# -gt 0 ]]; then
  [[ -d "$1" ]] || { echo "Missing generated pipeline directory: $1" >&2; exit 1; }
  "$directory/actionlint" -shellcheck= "$1"/*.yml
fi
