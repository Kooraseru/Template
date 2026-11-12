#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
node dependencies/packages/core/dependencyLoader/index.ts
node ci/bootstrap/run-tests.cjs
