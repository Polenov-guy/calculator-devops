#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
need_env
IMAGE=${1:?Usage: APP_HOME=/opt/calculator bash scripts/deploy.sh ghcr.io/owner/calculator@sha256:... EXPECTED_SHA}
EXPECTED=${2:?Expected application commit SHA required}
[[ $IMAGE =~ ^ghcr\.io/[a-z0-9._/-]+@sha256:[a-f0-9]{64}$ ]] || { echo 'An immutable GHCR digest is required' >&2; exit 1; }
mkdir -p "$APP_HOME/.state" "$APP_HOME/backups"
exec 9>"$APP_HOME/.state/deploy.lock"
flock -w 300 9
previous=$(cat "$APP_HOME/.state/current-release" 2>/dev/null || true)
previous_image=$(cat "$APP_HOME/.deploy.env" 2>/dev/null || true)
# Pull before modifying the active deployment.
docker pull "$IMAGE"
if [[ -n $previous && -d $previous ]] && [[ -n $(compose_at "$previous" ps -q app) ]]; then
 APP_HOME="$APP_HOME" bash "$previous/scripts/backup.sh"
fi
restore() {
 echo 'Deployment failed; restoring previous release' >&2
 if [[ -n $previous && -d $previous && -n $previous_image ]]; then
  printf '%s\n' "$previous_image" > "$APP_HOME/.deploy.env"
  compose_at "$previous" up -d --wait --wait-timeout 150 || { echo 'ROLLBACK FAILED: inspect Docker logs' >&2; return 1; }
  printf '%s\n' "$previous" > "$APP_HOME/.state/current-release"
 else
  # No previous release exists; retain diagnostics but stop the failed application.
  compose stop app || true
  echo 'First deployment failed; no previous release is available' >&2
 fi
}
failed() {
 local rc=$?
 trap - ERR
 compose logs --tail=100 app >&2 || true
 restore || true
 exit "$rc"
}
trap failed ERR
umask 077
printf 'APP_IMAGE=%s\n' "$IMAGE" > "$APP_HOME/.deploy.env.new"
mv "$APP_HOME/.deploy.env.new" "$APP_HOME/.deploy.env"
compose config -q
compose up -d --wait --wait-timeout 180
port=$(compose port app 8080); port=${port##*:}
bash "$ROOT/scripts/smoke-test.sh" "http://127.0.0.1:$port" "$EXPECTED"
bash "$ROOT/scripts/verify-monitoring.sh"
if [[ -n $previous ]]; then
 printf '%s\n' "$previous" > "$APP_HOME/.state/previous-release"
 printf '%s\n' "$previous_image" > "$APP_HOME/.state/previous-image"
fi
printf '%s\n' "$ROOT" > "$APP_HOME/.state/current-release"
printf '%s %s %s\n' "$(date -u +%FT%TZ)" "$EXPECTED" "$IMAGE" >> "$APP_HOME/.state/deployments.log"
trap - ERR
echo "Deployment successful: $EXPECTED"
