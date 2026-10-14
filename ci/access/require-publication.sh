#!/usr/bin/env bash
# Execute the shared declarative policy before any publication operation.
lune run ci/access/require-publication.luau
