#!/usr/bin/env bash
# CI-only test: isolated volume; never touches Compose or production volumes.
source "$(dirname "$0")/common.sh"
IMAGE=${1:-calculator:local}
name="calculator-ci-$RANDOM"
volume="$name-data"
cleanup(){ docker rm -f "$name" >/dev/null 2>&1 || true; docker volume rm "$volume" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker volume create "$volume" >/dev/null
run(){ docker run -d --name "$name" -p 127.0.0.1:18080:8080 -v "$volume:/data" "$IMAGE" >/dev/null; }
wait_ready(){ for i in $(seq 1 40);do if curl -fsS http://127.0.0.1:18080/readyz >/dev/null;then return;fi;sleep 1;done;docker logs "$name";return 1; }
run;wait_ready
curl -fsS -c /tmp/calculator-ci-cookies -H 'Content-Type: application/json' -d '{"a":8,"b":9,"operation":"multiply"}' http://127.0.0.1:18080/api/calculate | python3 -c 'import json,sys; assert json.load(sys.stdin)["result"]==72'
docker rm -f "$name" >/dev/null
run;wait_ready
curl -fsS -b /tmp/calculator-ci-cookies http://127.0.0.1:18080/api/history | python3 -c 'import json,sys; assert json.load(sys.stdin)[0]["result"]==72'
bash scripts/smoke-test.sh http://127.0.0.1:18080
echo 'PASS container restart and persistent SQLite volume'
