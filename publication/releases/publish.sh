#!/usr/bin/env bash
set -euo pipefail
source security/access/require-publication.sh
node publication/releases/cli.mjs publish
