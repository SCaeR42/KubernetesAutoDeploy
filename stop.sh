#!/usr/bin/env bash
# Удаляет ресурсы примера (Service + Deployment) из кластера.
# По умолчанию сам minikube и образ не трогает — см. флаги ниже.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$SCRIPT_DIR/k8s"

STOP_MINIKUBE=false
REMOVE_IMAGE=false

for arg in "$@"; do
    case "$arg" in
        --minikube) STOP_MINIKUBE=true ;;
        --image)    REMOVE_IMAGE=true ;;
        --all)      STOP_MINIKUBE=true; REMOVE_IMAGE=true ;;
        -h|--help)
            cat <<EOF
Использование: ./stop.sh [--image] [--minikube] [--all]

  (без флагов)  удалить только Service и Deployment приложения
  --image       также удалить собранный образ php-helloworld:latest
                (образ хранится в docker-демоне minikube, для его удаления
                нужно переключение через docker-env)
  --minikube    также остановить сам minikube (minikube stop)
  --all         эквивалент --image --minikube
EOF
            exit 0
            ;;
        *) echo "Неизвестный флаг: $arg" >&2; exit 1 ;;
    esac
done

echo "==> Удаляю ресурсы приложения из кластера..."
kubectl delete -f "$K8S_DIR/service.yaml" --ignore-not-found
kubectl delete -f "$K8S_DIR/deployment.yaml" --ignore-not-found

if [ "$REMOVE_IMAGE" = true ]; then
    echo "==> Удаляю образ php-helloworld:latest из docker-демона minikube..."
    eval "$(minikube -p minikube docker-env)"
    docker rmi php-helloworld:latest || true
fi

if [ "$STOP_MINIKUBE" = true ]; then
    echo "==> Останавливаю minikube..."
    minikube stop
fi

echo "==> Готово."
