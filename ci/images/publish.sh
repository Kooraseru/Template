#!/usr/bin/env bash
set -euo pipefail
source ci/access/require-publication.sh

docker load --input build/images/image.tar
repository="$(printf '%s' "$GITHUB_REPOSITORY" | tr '[:upper:]' '[:lower:]')"
target="ghcr.io/$repository/ci-$IMAGE_NAME:$GITHUB_SHA"
docker tag "template-ci/$IMAGE_NAME:generated" "$target"
printf '%s' "$GH_TOKEN" | docker login ghcr.io --username "$GITHUB_ACTOR" --password-stdin
trap 'docker logout ghcr.io' EXIT
docker push "$target"
