#!/usr/bin/env bash
set -euo pipefail
source security/access/require-publication.sh
bash .github/integration/run.sh publication/releases/publish.luau
