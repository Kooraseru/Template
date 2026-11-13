#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

export CI_EVENT=pull_request
export CI_OPERATION=validation
export CI_GRAPH_RUN=true
export CI_PHASE=build

node dependencies/packages/core/dependencyLoader/index.ts --exec luau.lute run ci/init.luau --stage build
bash ci/test.sh
