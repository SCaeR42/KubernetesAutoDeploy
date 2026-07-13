#!/usr/bin/env bash
# Удаляет ресурсы приложения из k3s-кластера. По умолчанию сам k3s и VPS
# не трогает - см. флаг --uninstall-k3s.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/env.sh" ]]; then
    source "$SCRIPT_DIR/env.sh"
else
    source "$SCRIPT_DIR/env.sh.example"
fi
KUBECONFIG_FILE="$SCRIPT_DIR/kubeconfig"

UNINSTALL_K3S=false
for arg in "$@"; do
    case "$arg" in
        --uninstall-k3s) UNINSTALL_K3S=true ;;
        -h|--help)
            cat <<EOF
Использование: ./destroy.sh [--uninstall-k3s]

  (без флагов)     удалить только Ingress/Service/Deployment приложения
  --uninstall-k3s  также полностью снести k3s с VPS (systemd-сервис,
                   все данные кластера) через встроенный k3s-uninstall.sh
EOF
            exit 0
            ;;
        *) echo "Неизвестный флаг: $arg" >&2; exit 1 ;;
    esac
done

if [[ -f "$KUBECONFIG_FILE" ]]; then
    echo "==> Удаляю ресурсы приложения..."
    kubectl --kubeconfig "$KUBECONFIG_FILE" delete -f "$SCRIPT_DIR/ingress.yaml" --ignore-not-found
    kubectl --kubeconfig "$KUBECONFIG_FILE" delete -f "$SCRIPT_DIR/service.yaml" --ignore-not-found
    kubectl --kubeconfig "$KUBECONFIG_FILE" delete -f "$SCRIPT_DIR/deployment.yaml" --ignore-not-found
else
    echo "    $KUBECONFIG_FILE не найден, пропускаю удаление k8s-ресурсов."
fi

if [[ "$UNINSTALL_K3S" = true ]]; then
    if [[ -z "$VPS_HOST" ]]; then
        echo "VPS_HOST не задан в env.sh, не могу подключиться для удаления k3s." >&2
        exit 1
    fi
    SSH_OPTS=($(ssh_opts))
    echo "==> Удаляю k3s с VPS ($VPS_HOST)..."
    ssh "${SSH_OPTS[@]}" "${VPS_USER}@${VPS_HOST}" \
        'command -v k3s-uninstall.sh >/dev/null 2>&1 && sudo k3s-uninstall.sh || echo "k3s-uninstall.sh не найден, k3s не установлен?"'
    rm -f "$KUBECONFIG_FILE"
fi

echo "==> Готово."
