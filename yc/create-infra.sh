#!/usr/bin/env bash
# Создаёт всю облачную инфраструктуру под managed Kubernetes в Yandex Cloud:
# сеть, сервисный аккаунт, registry, кластер, группу узлов.
#
# ВНИМАНИЕ: создаёт РЕАЛЬНЫЕ платные ресурсы (ВМ узлов, диски, публичные IP,
# балансировщик появится позже при deploy.sh). Перед запуском убедитесь,
# что выбраны правильные cloud-id / folder-id (yc config list).
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
    read -r -p "Продолжить создание ресурсов в этом облаке/папке? [y/N] " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Отменено пользователем."
        exit 1
    fi
fi

echo "==> Создаю сеть..."
yc vpc network create --name "$YC_NETWORK_NAME" 2>/dev/null || echo "    Сеть уже существует, пропускаю."

echo "==> Создаю подсеть в зоне $YC_ZONE..."
yc vpc subnet create \
    --name "$YC_SUBNET_NAME" \
    --zone "$YC_ZONE" \
    --network-name "$YC_NETWORK_NAME" \
    --range "10.0.0.0/24" 2>/dev/null || echo "    Подсеть уже существует, пропускаю."

echo "==> Создаю сервисный аккаунт для кластера и узлов..."
yc iam service-account create --name "$YC_SA_NAME" 2>/dev/null || echo "    Сервисный аккаунт уже существует, пропускаю."

FOLDER_ID="$(yc config get folder-id)"
echo "==> Выдаю роли сервисному аккаунту (folder: $FOLDER_ID)..."
for role in k8s.clusters.agent vpc.publicAdmin load-balancer.admin container-registry.images.puller container-registry.images.pusher monitoring.editor; do
    yc resource-manager folder add-access-binding "$FOLDER_ID" \
        --role "$role" \
        --service-account-name "$YC_SA_NAME" >/dev/null
    echo "    + $role"
done

echo "==> Создаю Container Registry..."
if yc container registry get --name "$YC_REGISTRY_NAME" >/dev/null 2>&1; then
    echo "    Registry уже существует, пропускаю."
else
    yc container registry create --name "$YC_REGISTRY_NAME"
fi

echo "==> Создаю Managed Kubernetes кластер (зональный, это может занять несколько минут)..."
if yc managed-kubernetes cluster get --name "$YC_CLUSTER_NAME" >/dev/null 2>&1; then
    echo "    Кластер уже существует, пропускаю."
else
    yc managed-kubernetes cluster create \
        --name "$YC_CLUSTER_NAME" \
        --network-name "$YC_NETWORK_NAME" \
        --zone "$YC_ZONE" \
        --subnet-name "$YC_SUBNET_NAME" \
        --public-ip \
        --service-account-name "$YC_SA_NAME" \
        --node-service-account-name "$YC_SA_NAME" \
        --release-channel rapid
fi

echo "==> Создаю группу узлов ($YC_NODE_COUNT шт., это тоже займёт несколько минут)..."
if yc managed-kubernetes node-group get --name "$YC_NODE_GROUP_NAME" >/dev/null 2>&1; then
    echo "    Группа узлов уже существует, пропускаю."
else
    yc managed-kubernetes node-group create \
        --name "$YC_NODE_GROUP_NAME" \
        --cluster-name "$YC_CLUSTER_NAME" \
        --platform standard-v3 \
        --cores 2 \
        --memory 2 \
        --disk-type network-hdd \
        --disk-size 64 \
        --fixed-size "$YC_NODE_COUNT" \
        --location zone="$YC_ZONE" \
        --network-interface subnets="$YC_SUBNET_NAME",ipv4-address=nat
fi

echo "==> Получаю kubeconfig..."
yc managed-kubernetes cluster get-credentials "$YC_CLUSTER_NAME" --external --context-name "$YC_KUBECTL_CONTEXT" --force

echo
echo "==> Готово! Инфраструктура создана."
echo "    Проверить ноды: kubectl --context $YC_KUBECTL_CONTEXT get nodes"
echo "    Дальше: ./build-and-push.sh && ./deploy.sh"
