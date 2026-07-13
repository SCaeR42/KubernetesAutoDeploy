#!/usr/bin/env bash
# Копирует ../app на VPS, собирает образ через Docker прямо на сервере и
# загружает его в containerd, которым управляет k3s - без внешнего registry.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/env.sh" ]]; then
    source "$SCRIPT_DIR/env.sh"
else
    source "$SCRIPT_DIR/env.sh.example"
fi
APP_DIR="$SCRIPT_DIR/../app"

if [[ -z "$VPS_HOST" ]]; then
    echo "Заполните VPS_HOST в env.sh перед запуском." >&2
    exit 1
fi

SSH_OPTS=($(ssh_opts))
SCP_OPTS=($(ssh_opts))
REMOTE_DIR="/tmp/php-helloworld-app"

echo "==> Проверяю наличие Docker на VPS..."
if ! ssh "${SSH_OPTS[@]}" "${VPS_USER}@${VPS_HOST}" 'command -v docker >/dev/null 2>&1'; then
    echo "==> Docker не найден, устанавливаю..."
    ssh "${SSH_OPTS[@]}" "${VPS_USER}@${VPS_HOST}" 'curl -sfL https://get.docker.com | sh -'
fi

echo "==> Копирую app/ на VPS ($REMOTE_DIR)..."
ssh "${SSH_OPTS[@]}" "${VPS_USER}@${VPS_HOST}" "rm -rf $REMOTE_DIR && mkdir -p $REMOTE_DIR"
scp "${SCP_OPTS[@]}" -r "$APP_DIR"/* "${VPS_USER}@${VPS_HOST}:${REMOTE_DIR}/"

echo "==> Собираю образ ${IMAGE_NAME}:${IMAGE_TAG} на VPS..."
ssh "${SSH_OPTS[@]}" "${VPS_USER}@${VPS_HOST}" \
    "sudo docker build -t ${IMAGE_NAME}:${IMAGE_TAG} $REMOTE_DIR"

echo "==> Импортирую образ в containerd k3s (без registry)..."
ssh "${SSH_OPTS[@]}" "${VPS_USER}@${VPS_HOST}" \
    "sudo docker save ${IMAGE_NAME}:${IMAGE_TAG} | sudo k3s ctr images import -"

echo "==> Готово. Образ ${IMAGE_NAME}:${IMAGE_TAG} доступен для подов в k3s."
