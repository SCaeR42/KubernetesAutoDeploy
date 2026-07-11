#!/usr/bin/env bash
# Применяет RBAC (rbac.yaml) и генерирует три отдельных kubeconfig-файла
# с разным уровнем доступа к локальному minikube-кластеру:
#   kubeconfig-read.yaml   - только просмотр (get/list/watch)
#   kubeconfig-write.yaml  - просмотр + создание/изменение/удаление/масштабирование
#   kubeconfig-admin.yaml  - полный доступ (копия текущего admin-конфига minikube)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="default"
CONTEXT="minikube"
TOKEN_DURATION="8760h"  # 1 год; при необходимости перегенерируйте с другим --duration

echo "==> Применяю RBAC-манифест..."
kubectl --context "$CONTEXT" apply -f "$SCRIPT_DIR/rbac.yaml"

echo "==> Достаю адрес API-сервера и CA сертификат кластера..."
CLUSTER_YAML="$(kubectl config view --minify --flatten --context "$CONTEXT")"
SERVER="$(echo "$CLUSTER_YAML" | grep 'server:' | head -1 | awk '{print $2}')"
CA_DATA="$(echo "$CLUSTER_YAML" | grep 'certificate-authority-data:' | head -1 | awk '{print $2}')"

generate_kubeconfig() {
    local role="$1" sa="$2"
    local out="$SCRIPT_DIR/kubeconfig-${role}.yaml"
    echo "==> Генерирую $out (ServiceAccount: $sa, namespace: $NAMESPACE)..."
    local token
    token="$(kubectl --context "$CONTEXT" -n "$NAMESPACE" create token "$sa" --duration="$TOKEN_DURATION")"
    cat > "$out" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: minikube
    cluster:
      server: ${SERVER}
      certificate-authority-data: ${CA_DATA}
contexts:
  - name: php-helloworld-${role}
    context:
      cluster: minikube
      namespace: ${NAMESPACE}
      user: php-helloworld-${role}
current-context: php-helloworld-${role}
users:
  - name: php-helloworld-${role}
    user:
      token: ${token}
EOF
    chmod 600 "$out"
}

generate_kubeconfig read  php-helloworld-read
generate_kubeconfig write php-helloworld-write

echo "==> Сохраняю kubeconfig-admin.yaml (полный доступ, копия текущего admin-конфига minikube)..."
kubectl config view --minify --flatten --context "$CONTEXT" > "$SCRIPT_DIR/kubeconfig-admin.yaml"
chmod 600 "$SCRIPT_DIR/kubeconfig-admin.yaml"

cat <<EOF

==> Готово. Три kubeconfig в $SCRIPT_DIR:
    kubeconfig-read.yaml   - только просмотр
    kubeconfig-write.yaml  - просмотр + изменение/удаление/масштабирование
    kubeconfig-admin.yaml  - полный доступ

Проверка:
  kubectl --kubeconfig $SCRIPT_DIR/kubeconfig-read.yaml  get pods
  kubectl --kubeconfig $SCRIPT_DIR/kubeconfig-read.yaml  delete pod <name>   # должно быть Forbidden
  kubectl --kubeconfig $SCRIPT_DIR/kubeconfig-write.yaml scale deployment php-helloworld --replicas=2
  kubectl --kubeconfig $SCRIPT_DIR/kubeconfig-admin.yaml get nodes
EOF
