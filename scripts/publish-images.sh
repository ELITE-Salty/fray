#!/bin/sh
# Run from any directory. Existing Docker credentials are used; never put tokens here.
set -eu
cd "$(dirname "$0")/.."
registry=${FRAY_REGISTRY:-10.6.2.49:3000/elitesalty}
revision=$(git rev-parse HEAD)
tag=${1:-$(git rev-parse --short=12 HEAD)}
case "$tag" in ''|*[!a-zA-Z0-9_.-]*|[-.]*) echo 'Invalid image tag.' >&2; exit 1;; esac
if test -n "$(git status --porcelain)"; then
    echo 'Commit source changes first so image revision labels identify the exact source.' >&2
    exit 1
fi
# Build every image before publishing any of them.
for component in api web db monitoring; do
    docker build --platform linux/amd64 \
        --label "org.opencontainers.image.revision=$revision" \
        -f "infra/docker/Dockerfile.$component" \
        -t "$registry/fray-$component:$tag" .
done
for component in api web db monitoring; do
    docker push "$registry/fray-$component:$tag"
done
# Update the convenience channel only after all versioned pushes succeeded.
for component in api web db monitoring; do
    docker tag "$registry/fray-$component:$tag" "$registry/fray-$component:release"
    docker push "$registry/fray-$component:release"
done
printf '\nPublished all four images. Set FRAY_IMAGE_TAG=%s in Portainer.\n' "$tag"
