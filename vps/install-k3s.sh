#!/usr/bin/env bash
# Устанавливает k3s (лёгкий дистрибутив Kubernetes) на удалённой VPS по SSH,
# затем скачивает kubeconfig в отдельный файл vps/kubeconfig (не трогая
# основной ~/.kube/config).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/env.sh" ]]; then
    source "$SCRIPT_DIR/env.sh"
else
    source "$SCRIPT_DIR/env.sh.example"
fi

if [[ -z "$VPS_HOST" ]]; then
    echo "Заполните VPS_HOST в env.sh перед запуском." >&2
    exit 1
fi

SSH_OPTS=($(ssh_opts))

echo "==> Проверяю, установлен ли k3s на $VPS_HOST..."
if ssh "${SSH_OPTS[@]}" "${VPS_USER}@${VPS_HOST}" 'command -v k3s >/dev/null 2>&1'; then
    echo "    k3s уже установлен, пропускаю установку."
else
    echo "==> Устанавливаю k3s (это займёт 1-2 минуты)..."
    # По умолчанию k3s сам поднимает Traefik как Ingress-контроллер и
    # ServiceLB для Service:LoadBalancer - этим и пользуемся дальше.
    ssh "${SSH_OPTS[@]}" "${VPS_USER}@${VPS_HOST}" \
        'curl -sfL https://get.k3s.io | sh -'
    echo "    Готово. k3s запущен как systemd-сервис (systemctl status k3s)."
fi

echo "==> Жду готовности ноды..."
ssh "${SSH_OPTS[@]}" "${VPS_USER}@${VPS_HOST}" \
    'for i in $(seq 1 30); do sudo k3s kubectl get nodes 2>/dev/null | grep -q " Ready" && break; sleep 2; done'

echo "==> Скачиваю kubeconfig в $SCRIPT_DIR/kubeconfig..."
ssh "${SSH_OPTS[@]}" "${VPS_USER}@${VPS_HOST}" 'sudo cat /etc/rancher/k3s/k3s.yaml' > "$SCRIPT_DIR/kubeconfig"

# k3s.yaml по умолчанию содержит server: https://127.0.0.1:6443 и имена
# cluster/context/user "default" - подставляем реальный адрес VPS и
# переименовываем, чтобы не путать с другими контекстами (minikube, yc-*).
sed -i.bak \
    -e "s#https://127.0.0.1:6443#https://${VPS_HOST}:6443#" \
    -e "s/\bdefault\b/${VPS_KUBECTL_CONTEXT}/g" \
    "$SCRIPT_DIR/kubeconfig"
rm -f "$SCRIPT_DIR/kubeconfig.bak"
chmod 600 "$SCRIPT_DIR/kubeconfig"

echo
echo "==> Готово! Kubeconfig сохранён в vps/kubeconfig (в .gitignore, наружу не коммитится)."
echo "    Проверить: kubectl --kubeconfig $SCRIPT_DIR/kubeconfig get nodes"
echo "    Дальше: ./build-and-load.sh && ./deploy.sh"
