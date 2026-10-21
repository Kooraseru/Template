#!/bin/sh
set -eu
# Package choices come from catalogue.json; this adapter only executes the
# distribution's package manager.
if command -v apk >/dev/null 2>&1; then
    apk add --no-cache "$@"
elif command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends "$@"
    apt-get clean
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y "$@"
    dnf clean all
elif command -v pacman >/dev/null 2>&1; then
    pacman -Syu --noconfirm --needed "$@"
    pacman -Scc --noconfirm
else
    echo "Unsupported package manager" >&2
    exit 1
fi
