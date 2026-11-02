#!/usr/bin/env bash

set -euo pipefail

# Delegate Git's credential protocol to the authenticated GitHub CLI.
exec gh auth git-credential "$@"
