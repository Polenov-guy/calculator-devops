#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
(cd dist && sha256sum -c SHA256SUMS)
mkdir -p dist/data
printf 'Persistent SQLite directory\n' > dist/data/.keep
IMAGE=${1:-calculator:local}
docker build --platform linux/amd64 -t "$IMAGE" .
echo "Packaged $IMAGE"
