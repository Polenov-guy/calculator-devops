#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID == 0 ]] || { echo 'Run with sudo bash scripts/bootstrap-server.sh'; exit 1; }
source /etc/os-release
[[ $ID == ubuntu && $VERSION_ID == 24.04 && $(dpkg --print-architecture) == amd64 ]] || { echo 'Requires clean Ubuntu 24.04 amd64'; exit 1; }
apt-get update
apt-get install -y ca-certificates curl gnupg openssl python3 util-linux git
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
cat > /etc/apt/sources.list.d/docker.sources <<'SOURCES'
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
SOURCES
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
id deploy >/dev/null 2>&1 || useradd -m -s /bin/bash deploy
usermod -aG docker deploy
install -d -o deploy -g deploy -m 0750 /opt/calculator /opt/calculator/releases /opt/calculator/backups /opt/calculator/.state
install -d -o deploy -g deploy -m 0700 /home/deploy/.ssh
if [[ -n ${DEPLOY_PUBLIC_KEY_FILE:-} ]]; then
 [[ -f $DEPLOY_PUBLIC_KEY_FILE ]] || { echo 'Public key file not found'; exit 1; }
 touch /home/deploy/.ssh/authorized_keys
 key=$(cat "$DEPLOY_PUBLIC_KEY_FILE")
 grep -qxF "$key" /home/deploy/.ssh/authorized_keys || printf '%s\n' "$key" >> /home/deploy/.ssh/authorized_keys
 chown deploy:deploy /home/deploy/.ssh/authorized_keys
 chmod 0600 /home/deploy/.ssh/authorized_keys
fi
docker run --rm hello-world
docker compose version
echo 'Bootstrap complete. Add deploy SSH key, then open a NEW SSH session as deploy.'
echo 'Provider firewall: allow TCP 22, 80, 3000; keep monitoring ports private.'
