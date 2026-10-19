#!/usr/bin/env bash
# Execute the shared declarative policy before any publication operation.
bash .github/integration/run.sh security/access/require-publication.luau
