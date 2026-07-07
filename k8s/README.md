# Локальный запуск: PHP Hello World на minikube (docker-драйвер)

Инструкция по развёртыванию простого PHP-приложения в локальном кластере
Kubernetes, поднятом через minikube (драйвер docker). Приложение выводит
Hello World, а также параметры сервера: имя пода, IP пода, имя ноды,
namespace, версию PHP и т.д. — удобно, чтобы наглядно видеть, на какой
ноде/поде обрабатывается конкретный запрос.

Манифесты этого варианта лежат прямо в этой папке (`deployment.yaml`,
`service.yaml`), приложение и Dockerfile — в [../app](../app), скрипты
запуска/остановки — в корне проекта.

## Быстрый старт (скрипты)

Вместо ручных шагов ниже можно воспользоваться готовыми скриптами из
корня проекта (запускать в Git Bash):

```bash
cd ..
./start.sh   # поднимет minikube (если не запущен), соберёт образ и задеплоит
./stop.sh    # удалит Service и Deployment примера из кластера
```

Флаги `stop.sh`:

```bash
./stop.sh --image      # + удалить собранный образ php-helloworld:latest
./stop.sh --minikube   # + остановить сам minikube
./stop.sh --all        # оба варианта сразу
```

Дальше в README — те же шаги вручную, для понимания, что происходит "под капотом".

## Предварительные требования

Проверено, что на машине уже установлены и работают:

- Docker Desktop
- minikube (`minikube status` -> Running)
- kubectl

Проверить состояние кластера:

```bash
minikube status
kubectl get nodes
```

Если кластер не запущен:

```bash
minikube start --driver=docker
```

Для наглядности "на какой ноде работает под" можно поднять кластер с
несколькими нодами (по умолчанию у minikube 1 нода-контрол-плейн, которая
одновременно и воркер):

```bash
minikube start --driver=docker --nodes=3
```

Это создаст 3 виртуальные ноды (`minikube`, `minikube-m02`, `minikube-m03`),
и под приложением будут раскиданы по разным нодам — Deployment с 3
репликами хорошо это продемонстрирует.

## Шаг 1. Собрать Docker-образ внутри minikube

minikube использует свой собственный Docker-демон, отдельный от локального
Docker Desktop. Чтобы кластер видел собранный образ без публикации в
registry, нужно указать shell на docker-демон minikube:

**PowerShell:**
```powershell
& minikube -p minikube docker-env | Invoke-Expression
```

**Bash/Git Bash:**
```bash
eval $(minikube -p minikube docker-env)
```

После этого все последующие команды `docker build` в этом терминале будут
собирать образ прямо внутри minikube.

Собрать образ:

```bash
cd ../app
docker build -t php-helloworld:latest .
cd ../k8s
```

Проверить, что образ появился внутри minikube:

```bash
docker images | grep php-helloworld
```

> Важно: команду `docker-env` нужно выполнять в каждой новой сессии
> терминала перед сборкой образа. Если открыли новый терминал — повторите
> шаг 1.

## Шаг 2. Применить манифесты Kubernetes

```bash
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```

Проверить, что поды поднялись и разъехались по нодам:

```bash
kubectl get pods -o wide
```

В колонке `NODE` будет видно, на какой ноде работает каждый под.

## Шаг 3. Открыть приложение в браузере

Самый простой способ — попросить minikube открыть сервис:

```bash
minikube service php-helloworld-svc
```

Эта команда сама откроет браузер по правильному адресу.

> **Важно (Windows + драйвер docker):** на Windows с драйвером `docker`
> minikube-нода — это отдельный Docker-контейнер, и `http://<minikube ip>:30080`
> **не будет доступен напрямую с хоста** (curl вернёт "connection refused").
> Команда `minikube service php-helloworld-svc` в этом случае откроет
> локальный туннель вида `http://127.0.0.1:PORT` и должна оставаться
> запущенной в терминале, пока вы пользуетесь приложением — именно
> так это и было проверено при подготовке этой инструкции. Если нужен
> только URL без открытия браузера:
> ```bash
> minikube service php-helloworld-svc --url
> ```

## Шаг 4. Убедиться, что под работает на разных нодах

Обновите страницу в браузере несколько раз (или сделайте несколько
запросов curl) — Service балансирует запросы между репликами пода,
которые могут находиться на разных нодах. В таблице на странице будет
меняться `Имя пода` и `Нода`.

```bash
# сначала в отдельном терминале держите открытым:
#   minikube service php-helloworld-svc --url
# и подставьте выданный URL ниже
for i in 1 2 3 4 5; do curl -s http://127.0.0.1:<PORT> | grep -A1 "POD_NAME\|NODE_NAME"; done
```

Также можно посмотреть распределение подов по нодам напрямую:

```bash
kubectl get pods -o=custom-columns=POD:.metadata.name,NODE:.spec.nodeName
```

## Полезные команды для отладки

```bash
# Логи конкретного пода
kubectl logs <pod-name>

# Логи всех подов деплоймента
kubectl logs -l app=php-helloworld --all-containers

# Зайти внутрь пода
kubectl exec -it <pod-name> -- sh

# Информация о поде (события, статус, нода)
kubectl describe pod <pod-name>

# Масштабировать количество реплик
kubectl scale deployment php-helloworld --replicas=5

# Дашборд Kubernetes (визуально)
minikube dashboard
```

## Как это устроено (кратко)

- **Downward API** (`deployment.yaml`, секция `env` → `valueFrom.fieldRef`)
  прокидывает в контейнер переменные окружения `POD_NAME`, `POD_IP`,
  `NODE_NAME`, `POD_NAMESPACE` из метаданных самого пода — без него PHP
  не знал бы, на какой ноде он выполняется.
- **index.php** читает эти переменные через `getenv()` и выводит вместе
  с другими стандартными параметрами PHP/сервера.
- **Service (NodePort)** открывает доступ к приложению снаружи кластера
  на порту `30080` и балансирует трафик между всеми репликами пода.
- **imagePullPolicy: Never** говорит Kubernetes не пытаться скачать образ
  из внешнего registry, а взять уже собранный локально (внутри minikube).

## Удаление

```bash
kubectl delete -f service.yaml
kubectl delete -f deployment.yaml
# при необходимости полностью остановить кластер:
minikube stop
```

## Переход в облако

Тот же код приложения можно развернуть в managed-кластере Yandex Cloud
(реальные ВМ-ноды, настоящий внешний балансировщик вместо туннеля
minikube) — см. [../yc/README.md](../yc/README.md).
