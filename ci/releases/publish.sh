#!/usr/bin/env bash
set -euo pipefail
source ci/access/require-publication.sh
node ci/releases/cli.mjs publish
