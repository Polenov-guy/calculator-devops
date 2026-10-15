#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
need_env
exec 9>"$APP_HOME/.state/deploy.lock"; flock -w 300 9
previous=$(cat "$APP_HOME/.state/previous-release")
[[ -d $previous ]] || { echo 'Previous release directory missing'; exit 1; }
image=$(cat "$APP_HOME/.state/previous-image")
current=$(cat "$APP_HOME/.state/current-release")
current_image=$(cat "$APP_HOME/.deploy.env")
printf '%s\n' "$image" > "$APP_HOME/.deploy.env"
verify_previous() {
 compose_at "$previous" up -d --wait --wait-timeout 180 || return
 local port
 port=$(compose_at "$previous" port app 8080);port=${port##*:}
 bash "$previous/scripts/smoke-test.sh" "http://127.0.0.1:$port"
}
if ! verify_previous; then
 printf '%s\n' "$current_image" > "$APP_HOME/.deploy.env"
 compose_at "$current" up -d --wait --wait-timeout 180
 echo 'Rollback failed; restored current release' >&2; exit 1
fi
printf '%s\n' "$previous" > "$APP_HOME/.state/current-release"
printf '%s rollback %s\n' "$(date -u +%FT%TZ)" "$image" >> "$APP_HOME/.state/deployments.log"
echo 'Rollback complete'
