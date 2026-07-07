# Развёртывание того же приложения в Yandex Managed Service for Kubernetes

Это тот же PHP Hello World, что и в [../k8s](../k8s), но адаптированный
под managed-кластер Yandex Cloud вместо локального minikube. Отличия
из-за перехода в облако:

| | Локально (minikube) | Yandex Managed Kubernetes |
|---|---|---|
| Образ | собирается в docker-демоне minikube, никуда не публикуется | нужен реестр — **Yandex Container Registry**, образ пушится туда |
| Доступ снаружи | `Service: NodePort` + `minikube service` (туннель) | `Service: LoadBalancer` — Yandex сам создаёт настоящий сетевой балансировщик с публичным IP |
| Ноды | одна вирт. нода minikube | реальные ВМ (Compute Instances) в группе узлов, `NODE_NAME` в приложении покажет их имена |
| Аутентификация в реестр | не нужна | нужен сервисный аккаунт с ролью `container-registry.images.puller` на группе узлов |
| Deployment/Service манифесты | `k8s/*.yaml` | `yc/*.yaml` (то же самое + `image` и `type: LoadBalancer`) |

Код приложения (`app/index.php`) не меняется вообще — Downward API
(`POD_NAME`, `NODE_NAME` и т.д.) работает одинаково в любом соответствующем
спецификации Kubernetes.

## Что уже проверено в этом окружении

- `yc` CLI установлен и авторизован (`yc config list` показывает
  `cloud-id` и `folder-id`).
- В облаке пока **нет** ни одного registry, кластера или сети — всё будет
  создаваться с нуля.

## Файлы

```
yc/
├── env.sh              # общие переменные (имена ресурсов, зона, кол-во нод)
├── create-infra.sh      # сеть, сервисный аккаунт, registry, кластер, node-group
├── build-and-push.sh    # docker build + push образа в Yandex Container Registry
├── deploy.sh            # kubectl apply манифестов + ожидание внешнего IP
├── destroy.sh           # полное удаление всех созданных ресурсов
├── deployment.yaml       # Deployment (плейсхолдер __IMAGE__ подставляется deploy.sh)
└── service.yaml          # Service типа LoadBalancer
```

## Порядок действий

1. Проверить/поправить имена и зону в [env.sh](env.sh) (по умолчанию всё
   в `ru-central1-b`, 3 узла).

2. Создать инфраструктуру (сеть, сервисный аккаунт, registry, кластер,
   группу узлов). Кластер создаётся ~5-10 минут, группа узлов — ещё
   несколько минут:

   ```bash
   cd yc
   ./create-infra.sh
   ```

   Скрипт спросит подтверждение перед созданием ресурсов и покажет,
   в каком облаке/папке (`cloud-id`/`folder-id`) он будет работать.

3. Собрать и запушить образ в Yandex Container Registry:

   ```bash
   ./build-and-push.sh
   ```

4. Задеплоить в кластер и дождаться внешнего IP балансировщика:

   ```bash
   ./deploy.sh
   ```

   В конце скрипт выведет `http://<external-ip>` — откройте в браузере,
   обновите страницу несколько раз и посмотрите, как меняется `POD_NAME`
   и `NODE_NAME` между тремя реальными нодами.

5. Когда закончите — обязательно снести ресурсы, чтобы не платить за
   простаивающий кластер/балансировщик/диски:

   ```bash
   ./destroy.sh
   ```

## Про стоимость

Managed Kubernetes в Yandex Cloud тарифицируется по:
- **control plane** (мастер) — зональный кластер обычно дешевле/бесплатен
  по сравнению с региональным, но тарификация может меняться, проверяйте
  актуальные цены в консоли/прайсе Yandex Cloud;
- **ВМ узлов** (Compute Instances) — в этом примере 3 узла by default,
  можно уменьшить `YC_NODE_COUNT=1` в `env.sh` для минимизации расходов;
- **диски** узлов;
- **публичные IP** узлов и балансировщика;
- **сетевой балансировщик** (Network Load Balancer), который создаётся
  автоматически при `Service: LoadBalancer`.

Для тестового прогона рекомендуется:
- выставить `YC_NODE_COUNT=1` в `env.sh`, если важна только демонстрация
  механики, а не распределение по нодам;
- не забыть выполнить `destroy.sh` сразу после эксперимента.

## Ручной вариант (без скриптов), если нужно понимать каждую команду

```bash
# 1. Сеть
yc vpc network create --name php-helloworld-network
yc vpc subnet create --name php-helloworld-subnet-b --zone ru-central1-b \
    --network-name php-helloworld-network --range 10.0.0.0/24

# 2. Сервисный аккаунт с нужными ролями
yc iam service-account create --name php-helloworld-k8s-sa
yc resource-manager folder add-access-binding <folder-id> \
    --role k8s.clusters.agent --service-account-name php-helloworld-k8s-sa
yc resource-manager folder add-access-binding <folder-id> \
    --role vpc.publicAdmin --service-account-name php-helloworld-k8s-sa
yc resource-manager folder add-access-binding <folder-id> \
    --role load-balancer.admin --service-account-name php-helloworld-k8s-sa
yc resource-manager folder add-access-binding <folder-id> \
    --role container-registry.images.puller --service-account-name php-helloworld-k8s-sa

# 3. Registry и образ
yc container registry create --name php-helloworld-registry
yc container registry configure-docker
docker build -t cr.yandex/<registry-id>/php-helloworld:latest ../app
docker push cr.yandex/<registry-id>/php-helloworld:latest

# 4. Кластер и группа узлов
yc managed-kubernetes cluster create \
    --name php-helloworld-cluster --network-name php-helloworld-network \
    --zone ru-central1-b --subnet-name php-helloworld-subnet-b --public-ip \
    --service-account-name php-helloworld-k8s-sa \
    --node-service-account-name php-helloworld-k8s-sa --release-channel rapid

yc managed-kubernetes node-group create \
    --name php-helloworld-nodes --cluster-name php-helloworld-cluster \
    --platform standard-v3 --cores 2 --memory 2 \
    --disk-type network-hdd --disk-size 64 --fixed-size 3 \
    --location zone=ru-central1-b \
    --network-interface subnets=php-helloworld-subnet-b,ipv4-address=nat

# 5. kubectl + деплой
yc managed-kubernetes cluster get-credentials php-helloworld-cluster \
    --external --context-name yc-php-helloworld
kubectl config use-context yc-php-helloworld

sed 's|__IMAGE__|cr.yandex/<registry-id>/php-helloworld:latest|' deployment.yaml | kubectl apply -f -
kubectl apply -f service.yaml
kubectl get svc php-helloworld-svc -w   # дождаться EXTERNAL-IP
```

## Возможные доработки

- **Ingress** вместо `LoadBalancer` на каждый Service — если сервисов
  станет несколько, дешевле держать один балансировщик перед
  ingress-nginx.
- **HPA** (`kubectl autoscale deployment php-helloworld ...`) — на managed
  кластере есть настоящая нагрузка/метрики, есть смысл добавить
  автомасштабирование, в отличие от локального minikube.
- **Регистр секретов** — если образ приватный и nodeless pull не настроен,
  альтернативой сервисному аккаунту на группе узлов может быть
  `imagePullSecrets` с Docker-конфигом от `yc container registry
  configure-docker`.
