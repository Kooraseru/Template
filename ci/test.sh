#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

node dependencies/packages/core/dependencyLoader/index.ts
mapfile -d '' suites < <(find ci dependencies/packages -type f \\( -name '*.test.cjs' -o -name '*.test.ts' \\) -not -path '*/managed/*' -print0)

if (( ${#suites[@]} == 0 )); then
  echo "No repository test suites were found." >&2
  exit 1
fi

node --test "${suites[@]}"
