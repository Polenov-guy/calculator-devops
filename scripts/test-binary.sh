#!/usr/bin/env bash
# Actual Linux binary integration test without Docker.
source "$(dirname "$0")/common.sh"
work=$(mktemp -d)
BINARY="$ROOT/dist/calculator"
PORT=${TEST_PORT:-19080}
app_pid=''
cleanup(){ [[ -z $app_pid ]] || kill "$app_pid" 2>/dev/null || true; rm -rf "$work"; }
trap cleanup EXIT
start(){ DB_PATH="$work/live.db" LISTEN_ADDR="127.0.0.1:$PORT" "$BINARY" > "$work/app.log" 2>&1 & app_pid=$!; }
wait_ready(){ for i in $(seq 1 30);do if curl -fsS "http://127.0.0.1:$PORT/readyz" >/dev/null 2>&1;then return;fi;sleep 1;done;cat "$work/app.log";return 1; }
start;wait_ready
bash scripts/smoke-test.sh "http://127.0.0.1:$PORT"
curl -fsS -c "$work/cookies" -H 'Content-Type: application/json' -d '{"a":8,"b":9,"operation":"multiply"}' "http://127.0.0.1:$PORT/api/calculate" > /dev/null
for i in $(seq 1 10);do curl -fsS "http://127.0.0.1:$PORT/" >/dev/null;done
curl -fsS "http://127.0.0.1:$PORT/metrics" | python3 -c 'import sys; assert "calculator_page_views_total 10\n" in sys.stdin.read()'
DB_PATH="$work/live.db" "$BINARY" backup "$work/snapshot.db"
python3 - "$work/snapshot.db" <<'PY'
import sqlite3,sys
with sqlite3.connect(sys.argv[1]) as db:
 assert db.execute('pragma integrity_check').fetchone()[0]=='ok'
 assert db.execute('select count(*) from calculations').fetchone()[0]==2
PY
kill "$app_pid";wait "$app_pid";app_pid=''
start;wait_ready
curl -fsS -b "$work/cookies" "http://127.0.0.1:$PORT/api/history" | python3 -c 'import json,sys; assert json.load(sys.stdin)[0]["result"]==72'
echo 'PASS binary HTTP, ten page views, online SQLite backup and history after process restart'
