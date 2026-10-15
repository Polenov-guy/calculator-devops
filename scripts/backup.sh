#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
need_env
mkdir -p "$APP_HOME/backups"
name="backup-$(date -u +%Y%m%dT%H%M%S)-$RANDOM.db"
container=$(compose ps -q app)
[[ -n $container ]] || { echo 'App container is not running' >&2; exit 1; }
compose exec -T app /calculator backup /data/.backup.db
docker cp "$container:/data/.backup.db" "$APP_HOME/backups/$name"
echo "Backup: $APP_HOME/backups/$name"
