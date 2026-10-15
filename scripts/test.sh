#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
if ! command -v go >/dev/null; then
 docker build -f Dockerfile.build -t calculator-builder:1.26.9 .
 docker run --rm calculator-builder:1.26.9 scripts/test.sh
 exit
fi
python3 -m unittest discover -s tests -v
go vet ./...
go test -count=1 -v ./...
