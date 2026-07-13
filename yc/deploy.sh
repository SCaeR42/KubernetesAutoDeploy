#!/usr/bin/env bash
# Подставляет актуальный образ из YCR в deployment.yaml и применяет манифесты
# в кластер Yandex Managed Kubernetes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/env.sh" ]]; then
    source "$SCRIPT_DIR/env.sh"
else
    source "$SCRIPT_DIR/env.sh.example"
fi

if [[ ! -f "$SCRIPT_DIR/.last_image" ]]; then
    echo "Не найден yc/.last_image. Сначала выполните ./build-and-push.sh" >&2
    exit 1
fi
FULL_IMAGE="$(cat "$SCRIPT_DIR/.last_image")"

echo "==> Переключаю kubectl на контекст $YC_KUBECTL_CONTEXT..."
kubectl config use-context "$YC_KUBECTL_CONTEXT"

echo "==> Применяю манифесты (образ: $FULL_IMAGE)..."
sed "s|__IMAGE__|${FULL_IMAGE}|" "$SCRIPT_DIR/deployment.yaml" | kubectl apply -f -
kubectl apply -f "$SCRIPT_DIR/service.yaml"

echo "==> Жду готовности деплоймента..."
kubectl rollout status deployment/php-helloworld --timeout=180s

echo "==> Поды и ноды (реальные ВМ в Yandex Cloud):"
kubectl get pods -o wide -l app=php-helloworld

echo "==> Жду внешний IP балансировщика (может занять 1-3 минуты)..."
for i in $(seq 1 30); do
    EXTERNAL_IP="$(kubectl get svc php-helloworld-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
    if [[ -n "$EXTERNAL_IP" ]]; then
        break
    fi
    sleep 10
done

if [[ -n "${EXTERNAL_IP:-}" ]]; then
    echo
    echo "==> Готово! Приложение доступно по адресу: http://$EXTERNAL_IP"
else
    echo
    echo "==> Внешний IP пока не выдан. Проверьте позже: kubectl get svc php-helloworld-svc"
fi
