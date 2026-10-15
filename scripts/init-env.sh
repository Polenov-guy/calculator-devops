#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
if [[ -e .env ]]; then echo '.env already exists; leaving it unchanged'; exit 0; fi
umask 077
cp .env.example .env
password=$(openssl rand -hex 24)
sed -i "s/^GRAFANA_ADMIN_PASSWORD=$/GRAFANA_ADMIN_PASSWORD=$password/" .env
echo 'Created .env with a random Grafana administrator password. Public UI has Viewer access.'
