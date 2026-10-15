#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
bash scripts/init-env.sh
bash scripts/test.sh
bash scripts/build.sh
bash scripts/package.sh calculator:local
compose up -d --wait --wait-timeout 180
port=$(compose port app 8080);port=${port##*:}
bash scripts/smoke-test.sh "http://127.0.0.1:$port"
echo "Calculator: http://localhost:$port ; Grafana: http://localhost:3000/d/calculator"
