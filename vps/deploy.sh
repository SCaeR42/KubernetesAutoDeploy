#!/usr/bin/env bash
# Применяет манифесты (Deployment + Service + Ingress) в k3s-кластер на VPS.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/env.sh" ]]; then
    source "$SCRIPT_DIR/env.sh"
else
    source "$SCRIPT_DIR/env.sh.example"
fi
KUBECONFIG_FILE="$SCRIPT_DIR/kubeconfig"

if [[ ! -f "$KUBECONFIG_FILE" ]]; then
    echo "Не найден $KUBECONFIG_FILE. Сначала выполните ./install-k3s.sh" >&2
    exit 1
fi

KC=(--kubeconfig "$KUBECONFIG_FILE")

echo "==> Применяю манифесты..."
kubectl "${KC[@]}" apply -f "$SCRIPT_DIR/deployment.yaml"
kubectl "${KC[@]}" apply -f "$SCRIPT_DIR/service.yaml"
kubectl "${KC[@]}" apply -f "$SCRIPT_DIR/ingress.yaml"

echo "==> Жду готовности деплоймента..."
kubectl "${KC[@]}" rollout status deployment/php-helloworld --timeout=120s

echo "==> Поды:"
kubectl "${KC[@]}" get pods -o wide -l app=php-helloworld

echo
echo "==> Готово! Приложение доступно по адресу: http://${VPS_HOST}/"
echo "    (проверьте, что порт 80 открыт в firewall/security group VPS-провайдера)"
