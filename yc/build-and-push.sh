#!/usr/bin/env bash
# Собирает образ приложения (из ../app) и пушит его в Yandex Container Registry.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/env.sh" ]]; then
    source "$SCRIPT_DIR/env.sh"
else
    source "$SCRIPT_DIR/env.sh.example"
fi
APP_DIR="$SCRIPT_DIR/../app"

REGISTRY_ID="$(yc container registry get --name "$YC_REGISTRY_NAME" --format json | grep -o '"id": *"[^"]*"' | head -1 | cut -d'"' -f4)"
if [[ -z "$REGISTRY_ID" ]]; then
    echo "Не найден registry '$YC_REGISTRY_NAME'. Сначала выполните ./create-infra.sh" >&2
    exit 1
fi

FULL_IMAGE="cr.yandex/${REGISTRY_ID}/${IMAGE_NAME}:${IMAGE_TAG}"
echo "==> Целевой образ: $FULL_IMAGE"

echo "==> Настраиваю docker-аутентификацию для cr.yandex..."
yc container registry configure-docker

echo "==> Собираю образ..."
docker build -t "$FULL_IMAGE" "$APP_DIR"

echo "==> Пушу образ в registry..."
docker push "$FULL_IMAGE"

echo "$FULL_IMAGE" > "$SCRIPT_DIR/.last_image"
echo "==> Готово. Образ: $FULL_IMAGE (сохранён в yc/.last_image для deploy.sh)"
