# PHP Hello World на Kubernetes

Простое PHP-приложение для Kubernetes: страница Hello World, которая
дополнительно выводит параметры сервера — имя пода, IP пода, имя ноды,
namespace, версию PHP и т.д. Удобно, чтобы наглядно видеть, на какой
ноде/поде обрабатывается конкретный запрос (особенно при масштабировании
через несколько реплик).

Код приложения один и тот же ([app/index.php](app/index.php),
[app/Dockerfile](app/Dockerfile)) — различаются только манифесты
Kubernetes и способ доставки образа, в зависимости от того, где
разворачиваете кластер.

## Структура проекта

```
KubernetesYcAutoCreate/
├── app/
│   ├── index.php        # PHP-страница с Hello World и данными о поде/ноде
│   └── Dockerfile        # образ на базе php:8.3-apache
├── k8s/                  # вариант 1: локальный кластер (minikube)
│   ├── deployment.yaml
│   ├── service.yaml       # Service типа NodePort
│   └── README.md          # подробная инструкция
├── yc/                   # вариант 2: Yandex Managed Service for Kubernetes
│   ├── deployment.yaml
│   ├── service.yaml       # Service типа LoadBalancer
│   ├── env.sh / create-infra.sh / build-and-push.sh / deploy.sh / destroy.sh
│   └── README.md          # подробная инструкция
├── vps/                  # вариант 3: обычная VPS + k3s
│   ├── deployment.yaml
│   ├── service.yaml       # Service ClusterIP
│   ├── ingress.yaml        # Ingress через встроенный Traefik
│   ├── env.sh / install-k3s.sh / build-and-load.sh / deploy.sh / destroy.sh
│   └── README.md          # подробная инструкция
├── start.sh               # быстрый запуск локального варианта
├── stop.sh                # остановка локального варианта
└── README.md               # этот файл
```

## Доступные варианты развёртывания

| Вариант | Где выполняется | Доступ снаружи | Инструкция |
|---|---|---|---|
| **Локально** | minikube (docker-драйвер) на вашей машине | `Service: NodePort` + туннель `minikube service` | [k8s/README.md](k8s/README.md) |
| **Облако (managed)** | Yandex Managed Service for Kubernetes (реальные ВМ-ноды) | `Service: LoadBalancer` — настоящий внешний IP | [yc/README.md](yc/README.md) |
| **Своя VPS** | k3s (lightweight k8s) на одной обычной VPS | `Ingress` через встроенный Traefik | [vps/README.md](vps/README.md) |

Быстрый старт локального варианта одной командой из корня проекта:

```bash
./start.sh   # поднимет minikube, соберёт образ, задеплоит
./stop.sh    # уберёт за собой
```

Подробности, шаги вручную, отладка и объяснение механики (Downward API
и т.д.) — в README каждого варианта по ссылкам выше. Для облачного
варианта отдельно расписаны нюансы стоимости и полная очистка ресурсов.

> Варианты **k8s/** и **yc/** проверены вживую (реально разворачивались и
> тестировались). Вариант **vps/** пока не проверен end-to-end — под рукой
> не было реальной VPS; см. предупреждение в [vps/README.md](vps/README.md).
