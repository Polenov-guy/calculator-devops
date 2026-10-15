#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
VERSION=${VERSION:-$(git rev-parse HEAD 2>/dev/null || echo local)}
BUILT_AT=${BUILT_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}
export VERSION BUILT_AT
mkdir -p dist
if ! command -v go >/dev/null; then
 docker build -f Dockerfile.build -t calculator-builder:1.26.9 .
 docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e GOCACHE=/tmp/go-cache -e VERSION -e BUILT_AT -v "$ROOT/dist:/src/dist" calculator-builder:1.26.9 scripts/build.sh
 exit
fi
mkdir -p dist/data
printf 'Persistent SQLite directory\n' > dist/data/.keep
[[ $VERSION =~ ^[a-zA-Z0-9._-]+$ ]] || { echo 'Invalid version'; exit 1; }
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -buildvcs=false -trimpath -ldflags "-s -w -X main.version=$VERSION -X main.builtAt=$BUILT_AT" -o dist/calculator ./cmd/calculator
printf '{"version":"%s","built_at":"%s","platform":"linux/amd64"}\n' "$VERSION" "$BUILT_AT" > dist/build-info.json
(cd dist && sha256sum calculator build-info.json > SHA256SUMS)
echo "Built $VERSION"
