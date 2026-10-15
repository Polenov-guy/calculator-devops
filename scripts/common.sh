#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
APP_HOME=${APP_HOME:-$ROOT}
cd "$ROOT"
compose_at() {
 local dir=$1; shift
 local args=(--project-directory "$dir" -f "$dir/compose.yaml" --env-file "$APP_HOME/.env")
 [[ ! -f "$APP_HOME/.deploy.env" ]] || args+=(--env-file "$APP_HOME/.deploy.env")
 docker compose "${args[@]}" "$@"
}
compose() { compose_at "$ROOT" "$@"; }
need_env() { [[ -f "$APP_HOME/.env" ]] || { echo 'Run bash scripts/init-env.sh' >&2; exit 1; }; }
