# Helm-chart + CI/CD (GitHub Actions) для Yandex Managed Kubernetes

Четвёртый способ развернуть то же приложение — через Helm-chart и три
GitHub Actions workflow, которые собирают образ, пушат в Yandex
Container Registry и деплоят через `helm upgrade --install` в кластер
[yc/](../yc) (Yandex Managed Service for Kubernetes).

**Ничего не запускается автоматически на push.** Создание/удаление
инфраструктуры и сам деплой в облако — намеренно только ручные действия
(кнопка «Run workflow» в GitHub), кроме линта чарта, который безопасен
и не трогает никакие облачные ресурсы.

> **Важно:** чарт и `helm lint` я проверил вживую (см. ниже), а вот сами
> GitHub Actions workflow (`deploy.yml`, `infra.yml`) **не были прогнаны
> по-настоящему** — нужны реальные GitHub Secrets и ручной запуск в
> GitHub UI, которых у меня в этой сессии нет. Синтаксис YAML проверен,
> структура стандартна для yc CLI + Helm, но перед первым реальным
> использованием пройдите оба вручную и проверьте логи.

## Что уже проверено вживую

- `helm lint helm/php-helloworld --strict` — проходит.
- `helm template` — рендерит корректный Deployment + Service.
- `helm install --dry-run` против реального API minikube — успешно.
- **Полная установка чарта** в minikube (`helm install`, 2 реплики,
  `ClusterIP`) — поды поднялись, `port-forward` + `curl` подтвердили,
  что страница отдаёт корректные `POD_NAME`/`NODE_NAME`. Тестовый релиз
  затем удалён (`helm uninstall`).

## Структура

```
helm/
├── php-helloworld/
│   ├── Chart.yaml
│   ├── values.yaml            # дефолты под yc/ (LoadBalancer, registry cr.yandex/...)
│   ├── .helmignore
│   └── templates/
│       ├── _helpers.tpl
│       ├── deployment.yaml     # параметризованный Deployment (Downward API как в других вариантах)
│       ├── service.yaml
│       └── NOTES.txt
├── lint.sh                     # helm lint + template + kubectl dry-run (для локальной разработки)
└── README.md                    # этот файл

.github/workflows/
├── helm-lint.yml                # lint чарта на PR/push - без секретов, безопасно для форков
├── infra.yml                     # РУЧНОЙ create/destroy облачной инфраструктуры (yc/)
└── deploy.yml                    # РУЧНОЙ build + push в YCR + helm upgrade --install
```

## Локальная проверка (без CI)

```bash
./helm/lint.sh
```

Делает то же самое, что и job `lint` в CI: `helm lint --strict`, рендер
шаблонов, структурная проверка через ваш текущий `kubectl`-контекст
(client-side, кластер не меняется).

Установить на локальный minikube для проверки (как я и тестировал):

```bash
helm install php-helloworld helm/php-helloworld \
  --set image.repository=php-helloworld \
  --set image.tag=latest \
  --set image.pullPolicy=Never \
  --set service.type=ClusterIP

kubectl port-forward svc/php-helloworld-svc 8080:80
# затем открыть http://localhost:8080

helm uninstall php-helloworld
```

## GitHub Actions: три workflow

### `helm-lint.yml` — проверка чарта (автоматический)

Единственный из трёх, который срабатывает сам. Триггеры: `pull_request`
и `push` с изменениями в `helm/**`, плюс ручной запуск. Не требует
секретов — безопасно запускается и для PR из форков. Шаги: `helm lint
--strict` → `helm template` → валидация манифестов через
[kubeconform](https://github.com/yannh/kubeconform) (статическая
проверка схемы Kubernetes, без обращения к какому-либо кластеру).

Этот же workflow переиспользуется как job внутри `deploy.yml`
(`workflow_call`), так что деплой не запустится, если чарт не прошёл линт.

### `infra.yml` — создание/удаление инфраструктуры (только вручную)

Обёртка над [yc/create-infra.sh](../yc/create-infra.sh) и
[yc/destroy.sh](../yc/destroy.sh) (оба теперь поддерживают флаг `-y`/`--yes`
для неинтерактивного запуска из CI). Запускается **только** из вкладки
**Actions → Yandex Cloud infrastructure (manual) → Run workflow**, где
нужно выбрать действие `create` или `destroy` из выпадающего списка.

Никогда не триггерится на push/PR — создание, а тем более удаление,
реальных платных облачных ресурсов (ВМ, диски, балансировщик, кластер)
должно быть осознанным решением человека, а не побочным эффектом коммита.

### `deploy.yml` — сборка образа + деплой через Helm (только вручную)

Тоже только `workflow_dispatch` — запускается вручную из **Actions →
Build and deploy to Yandex Managed Kubernetes → Run workflow**. Три
последовательных job:

1. **lint** — переиспользует `helm-lint.yml`.
2. **build-and-push** — собирает `app/` в Docker-образ, пушит в Yandex
   Container Registry с тегом `<12 символов git sha>`.
3. **deploy** — получает kubeconfig кластера через `yc managed-kubernetes
   cluster get-credentials` и выполняет `helm upgrade --install`.

Предполагает, что инфраструктура уже создана через `infra.yml` (или
локально через `yc/create-infra.sh`) — сам ничего не провижинит.

## Чек-лист: что нужно для первого ручного запуска

### 1. GitHub Secrets

Настраиваются в репозитории: **Settings → Secrets and variables →
Actions → New repository secret**.

| Secret | Используется в | Значение | Секретно? |
|---|---|---|---|
| `YC_CLOUD_ID` | `infra.yml`, `deploy.yml` | ID облака, `yc config get cloud-id` | нет, но храните как secret для порядка |
| `YC_FOLDER_ID` | `infra.yml`, `deploy.yml` | ID каталога, `yc config get folder-id` | нет |
| `YC_SA_JSON_CREDENTIALS` | `deploy.yml` | JSON-ключ узко-скоуп­нутого SA (см. пункт 2) | **да** |
| `YC_SA_JSON_CREDENTIALS_INFRA` | `infra.yml` | JSON-ключ широко-привилегированного SA (см. пункт 3) | **да** |

Имена кластера (`php-helloworld-cluster`) и реестра
(`php-helloworld-registry`) секретами не являются — заданы прямо в `env:`
в самих workflow-файлах и должны совпадать со значениями в
[yc/env.sh](../yc/env.sh). Если ресурсы не переименовывали — трогать не нужно.

> `yc/env.sh` в `.gitignore` (это локальный файл), поэтому в свежем
> checkout на раннере GitHub Actions его нет. Все скрипты в `yc/` и `vps/`
> при отсутствии `env.sh` сами подставляют закоммиченный
> [env.sh.example](../yc/env.sh.example) с теми же (не секретными)
> значениями — никаких дополнительных действий не требуется.

### 2. `YC_SA_JSON_CREDENTIALS` — для деплоя (узкие права)

Тот же `php-helloworld-k8s-sa`, что создаёт `yc/create-infra.sh` — умеет
только читать kubeconfig кластера, пушить/тянуть образы и управлять
ресурсами внутри namespace `default` (`k8s.clusters.agent`,
`k8s.cluster-api.editor`, `container-registry.images.puller/pusher`).
Роль `k8s.cluster-api.editor` — именно та, что даёт Kubernetes RBAC
уровня `edit` (group `yc:editor`) внутри кластера; без неё `helm
upgrade` падает с `forbidden: cannot list secrets` (Helm хранит
состояние релизов как Secret) — это не то же самое, что похожая по
названию роль `k8s.editor` (та лишь про управление самим кластером/
node-group через yc API, а не про права внутри Kubernetes).
Именно этим ключом пользуется `deploy.yml` при обычном деплое — сознательно
низкие привилегии, чтобы утечка этого секрета не давала прав что-либо
создавать/удалять в облаке.

```bash
yc iam key create \
  --service-account-name php-helloworld-k8s-sa \
  --output key.json
```

### 3. `YC_SA_JSON_CREDENTIALS_INFRA` — для infra.yml (широкие права)

**Отдельный** сервисный аккаунт с более широкими правами — `infra.yml`
создаёт/удаляет сеть, IAM-биндинги, registry и сам кластер, а этого
`php-helloworld-k8s-sa` делать не умеет и не должен (принцип наименьших
привилегий: секрет, который гоняется на каждый обычный деплой, не должен
уметь удалить весь кластер).

```bash
yc iam service-account create --name php-helloworld-ci-bootstrap

yc resource-manager folder add-access-binding "$(yc config get folder-id)" \
  --role admin \
  --service-account-name php-helloworld-ci-bootstrap

yc iam key create \
  --service-account-name php-helloworld-ci-bootstrap \
  --output key-infra.json
```

Роль `admin` на весь folder — это много; если хотите уже, можно
попробовать `editor` + `resource-manager.admin` (нужен именно для
`add-access-binding`/`remove-access-binding` внутри `create-infra.sh`/
`destroy.sh`), но это не проверялось — при нехватке прав `yc` сообщит,
какого конкретно доступа не хватает.

Оба JSON-ключа (`key.json`, `key-infra.json`) создавайте и копируйте **в
своём терминале** (не через ассистента — приватные ключи не должны
попадать в чат/логи), затем удаляйте локально:

```bash
rm key.json key-infra.json
```

### 4. Итоговая последовательность

1. Создать `php-helloworld-ci-bootstrap` с ролью `admin` на folder и его ключ → секрет `YC_SA_JSON_CREDENTIALS_INFRA`.
2. Добавить `YC_CLOUD_ID`, `YC_FOLDER_ID` в секреты (не меняются от шага к шагу).
3. **Actions → Yandex Cloud infrastructure (manual) → Run workflow → action: create** — поднимет сеть/SA/registry/кластер/node-group.
4. Создать ключ `php-helloworld-k8s-sa` (уже создан шагом 3) → секрет `YC_SA_JSON_CREDENTIALS`.
5. **Actions → Build and deploy to Yandex Managed Kubernetes → Run workflow** — lint → build&push → deploy.
6. Когда закончите — **Actions → Yandex Cloud infrastructure (manual) → Run workflow → action: destroy**, чтобы не платить за простаивающий кластер.
