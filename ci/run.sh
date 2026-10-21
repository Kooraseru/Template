#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

if ! command -v lune >/dev/null 2>&1; then
  echo "Lune is required for repository operations; run the standard setup-lune action in CI." >&2
  exit 127
fi

exec lune run ci/main.luau "$@"
