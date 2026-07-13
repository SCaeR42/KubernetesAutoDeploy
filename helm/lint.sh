#!/usr/bin/env bash
# Локальная проверка Helm-чарта: helm lint + рендер шаблонов + структурная
# валидация через текущий kubectl-контекст (client-side dry-run, кластер
# не меняется). Этот же скрипт используется в CI (.github/workflows/helm-lint.yml).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$SCRIPT_DIR/php-helloworld"

echo "==> helm lint..."
helm lint "$CHART_DIR" --strict

echo "==> helm template (рендер с дефолтными values)..."
helm template ci-check "$CHART_DIR" > /tmp/php-helloworld-rendered.yaml
echo "    OK, $(grep -c '^kind:' /tmp/php-helloworld-rendered.yaml) объект(ов) отрендерено."

echo "==> kubectl dry-run (client-side, без обращения к кластеру)..."
kubectl apply --dry-run=client -f /tmp/php-helloworld-rendered.yaml

echo "==> Всё ок."
