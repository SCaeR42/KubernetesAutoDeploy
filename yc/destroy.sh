#!/usr/bin/env bash
# Полностью удаляет всё, что создали create-infra.sh / deploy.sh, чтобы не
# продолжало тарифицироваться: Service (и вместе с ним балансировщик),
# Deployment, группу узлов, кластер, registry, сервисный аккаунт, подсеть, сеть.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/env.sh" ]]; then
    source "$SCRIPT_DIR/env.sh"
else
    # env.sh в .gitignore (локальный файл) - в CI его нет, используем
    # закоммиченный env.sh.example с теми же (не секретными) значениями.
    source "$SCRIPT_DIR/env.sh.example"
fi

SKIP_CONFIRM=false
for arg in "$@"; do
    case "$arg" in
        -y|--yes) SKIP_CONFIRM=true ;;
        *) echo "Неизвестный флаг: $arg" >&2; exit 1 ;;
    esac
done

echo "==> Текущий контекст yc:"
yc config list

if [[ "$SKIP_CONFIRM" != true ]]; then
    read -r -p "Удалить ВСЮ инфраструктуру примера (кластер, ноды, LB, registry, сеть)? [y/N] " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Отменено пользователем."
        exit 1
    fi
fi

echo "==> Получаю доступ к кластеру (если он существует)..."
yc managed-kubernetes cluster get-credentials "$YC_CLUSTER_NAME" --external --context-name "$YC_KUBECTL_CONTEXT" --force 2>/dev/null \
    || echo "    Кластер не найден или уже удалён, пропускаю получение kubeconfig."

echo "==> Удаляю Service (важно сделать ДО удаления кластера — иначе балансировщик может остаться висеть)..."
kubectl --context "$YC_KUBECTL_CONTEXT" delete -f "$SCRIPT_DIR/service.yaml" --ignore-not-found || true

echo "==> Удаляю Deployment..."
kubectl --context "$YC_KUBECTL_CONTEXT" delete deployment php-helloworld --ignore-not-found || true

echo "==> Жду освобождения балансировщика..."
sleep 20

echo "==> Удаляю группу узлов..."
yc managed-kubernetes node-group delete --name "$YC_NODE_GROUP_NAME" 2>/dev/null || echo "    Уже удалена или не найдена."

echo "==> Удаляю кластер..."
yc managed-kubernetes cluster delete --name "$YC_CLUSTER_NAME" 2>/dev/null || echo "    Уже удалён или не найден."

echo "==> Удаляю образы из registry (registry нельзя удалить, пока он не пуст)..."
REGISTRY_ID="$(yc container registry get --name "$YC_REGISTRY_NAME" --format json 2>/dev/null | grep -o '"id": *"[^"]*"' | head -1 | cut -d'"' -f4)"
if [[ -n "$REGISTRY_ID" ]]; then
    IMAGE_IDS="$(yc container image list --registry-id "$REGISTRY_ID" --format json 2>/dev/null | grep -o '"id": *"[^"]*"' | cut -d'"' -f4)"
    for image_id in $IMAGE_IDS; do
        yc container image delete --id "$image_id" >/dev/null 2>&1 || true
    done
fi

echo "==> Удаляю registry..."
yc container registry delete --name "$YC_REGISTRY_NAME" 2>/dev/null || echo "    Уже удалён или не найден."

echo "==> Удаляю подсеть..."
yc vpc subnet delete --name "$YC_SUBNET_NAME" 2>/dev/null || echo "    Уже удалена или не найдена."

echo "==> Удаляю сеть..."
yc vpc network delete --name "$YC_NETWORK_NAME" 2>/dev/null || echo "    Уже удалена или не найдена."

FOLDER_ID="$(yc config get folder-id)"
echo "==> Отзываю роли и удаляю сервисный аккаунт..."
for role in k8s.clusters.agent k8s.editor vpc.publicAdmin load-balancer.admin container-registry.images.puller container-registry.images.pusher monitoring.editor; do
    yc resource-manager folder remove-access-binding "$FOLDER_ID" \
        --role "$role" \
        --service-account-name "$YC_SA_NAME" >/dev/null 2>&1 || true
done
yc iam service-account delete --name "$YC_SA_NAME" 2>/dev/null || echo "    Уже удалён или не найден."

rm -f "$SCRIPT_DIR/.last_image"

echo
echo "==> Готово. Проверьте в консоли Yandex Cloud, что платных ресурсов не осталось:"
echo "    https://console.yandex.cloud/"
