#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
need_env
[[ $(uname -m) == x86_64 ]] || { echo 'This distribution targets amd64'; exit 1; }
for cmd in docker python3 curl flock; do command -v "$cmd" >/dev/null || { echo "Missing $cmd"; exit 1; }; done
docker info >/dev/null
docker compose version
compose config -q
[[ -e /dev/kmsg ]] || { echo 'Missing /dev/kmsg required by this cAdvisor configuration'; exit 1; }
[[ -d /var/lib/docker && -d /dev/disk ]] || { echo 'Standard Docker data-root /var/lib/docker and /dev/disk required'; exit 1; }
[[ $(docker info --format '{{.DockerRootDir}}') == /var/lib/docker ]] || { echo 'Non-default Docker data-root; adjust cAdvisor mounts'; exit 1; }
echo 'Pulling monitoring images to verify registry access and tags…'
compose pull prometheus grafana node-exporter cadvisor blackbox
compose run --rm --no-deps --entrypoint promtool prometheus check config /etc/prometheus/prometheus.yml
echo 'Preflight passed'
