#!/usr/bin/env bash
# Собирает образ php-helloworld внутри docker-демона minikube и разворачивает
# приложение в кластере (Deployment + Service). Запускать из Git Bash / bash.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR/app"
K8S_DIR="$SCRIPT_DIR/k8s"

echo "==> Проверяю статус minikube..."
if ! minikube status >/dev/null 2>&1; then
    echo "==> minikube не запущен, стартую (driver=docker)..."
    minikube start --driver=docker
else
    echo "    minikube уже запущен."
fi

echo "==> Переключаю docker на демон minikube..."
eval "$(minikube -p minikube docker-env)"

echo "==> Собираю образ php-helloworld:latest..."
docker build -t php-helloworld:latest "$APP_DIR"

echo "==> Применяю манифесты Kubernetes..."
kubectl apply -f "$K8S_DIR/deployment.yaml"
kubectl apply -f "$K8S_DIR/service.yaml"

echo "==> Жду готовности деплоймента..."
kubectl rollout status deployment/php-helloworld --timeout=120s

echo "==> Поды и ноды, на которых они работают:"
kubectl get pods -o wide -l app=php-helloworld

cat <<'EOF'

==> Готово! Приложение развёрнуто.

Чтобы открыть его в браузере, выполните в отдельном терминале (окно
должно оставаться открытым — так работает драйвер docker на Windows):

    minikube service php-helloworld-svc

Либо получить URL без открытия браузера:

    minikube service php-helloworld-svc --url

Для остановки и удаления примера используйте ./stop.sh
EOF
