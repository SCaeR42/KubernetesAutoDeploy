# Развёртывание того же приложения на обычной VPS через k3s

Третий вариант того же PHP Hello World — на любой обычной VPS (Timeweb,
Selectel, Hetzner, DigitalOcean, любой другой провайдер с root-доступом по
SSH), без managed Kubernetes и без облачного балансировщика. Кластер —
однонодовый [k3s](https://k3s.io/) прямо на самом сервере.

> **Важно:** в отличие от [k8s/](../k8s) (проверено вживую на этой машине)
> и [yc/](../yc) (проверено вживую в реальном облаке), этот вариант
> **не был прогнан end-to-end** в текущей сессии — под рукой не было
> реальной VPS для теста. Скрипты написаны по стандартным практикам k3s,
> но перед боевым использованием стоит внимательно пройти шаги руками и
> свериться с выводом каждой команды (особенно шаг 3, про имя импортированного
> образа — см. предупреждение там).

## Чем отличается от других вариантов

| | Локально (minikube) | Yandex Managed K8s | VPS + k3s |
|---|---|---|---|
| Кластер | вирт. нода minikube | реальные ВМ, управляемые Yandex Cloud | k3s (упрощённый k8s) на вашей единственной VPS |
| Control plane | эмулируется minikube | полностью managed, вы не видите/не платите отдельно за мастер | пoднимаете и обслуживаете сами (это тот же процесс k3s) |
| Образ | собирается в docker minikube | пушится в Yandex Container Registry | собирается Docker'ом прямо на VPS и импортируется в containerd k3s - без registry |
| Доступ снаружи | `NodePort` + туннель `minikube service` | `LoadBalancer` - настоящий облачный балансировщик | `Ingress` через встроенный в k3s Traefik, слушающий 80/443 на самой VPS |
| Стоимость | бесплатно (свой ПК) | почасовая аренда ВМ+LB+диски+IP в Yandex Cloud | вы уже платите за саму VPS, k3s поверх - бесплатен |

Код приложения не меняется — [app/index.php](../app/index.php) и
[app/Dockerfile](../app/Dockerfile) те же самые.

## Файлы

```
vps/
├── env.sh              # VPS_HOST, VPS_USER, SSH-ключ и т.д. - заполнить перед стартом
├── install-k3s.sh       # ставит k3s на VPS по SSH, скачивает kubeconfig
├── build-and-load.sh    # копирует app/ на VPS, собирает образ, грузит в containerd k3s
├── deploy.sh            # kubectl apply манифестов
├── destroy.sh           # удаление ресурсов (и опционально самого k3s)
├── deployment.yaml       # Deployment (Downward API, imagePullPolicy: Never)
├── service.yaml          # Service ClusterIP
└── ingress.yaml          # Ingress через встроенный Traefik
```

## Предварительные требования

- VPS с Ubuntu/Debian (или другим systemd-дистрибутивом), root-доступ по SSH.
- Открытые порты в firewall/security group провайдера: **22** (SSH),
  **80** и **443** (HTTP/HTTPS через Traefik), **6443** (Kubernetes API,
  если планируете управлять кластером с локальной машины - можно закрыть
  снаружи и оставить только localhost/VPN, если управляете только по SSH).
- Локально: `ssh`, `scp`, `kubectl`.

## Порядок действий

1. Заполните [env.sh](env.sh) — как минимум `VPS_HOST` (IP или домен) и,
   если нужно, `VPS_SSH_KEY`.

2. Установить k3s на VPS и получить kubeconfig:

   ```bash
   cd vps
   ./install-k3s.sh
   ```

   Скрипт идемпотентен — если k3s уже стоит, установку пропустит.
   Kubeconfig сохраняется в `vps/kubeconfig` (не коммитится, см.
   `.gitignore`), отдельно от вашего основного `~/.kube/config`.

   Проверить:
   ```bash
   kubectl --kubeconfig kubeconfig get nodes
   ```

3. Собрать образ на VPS и загрузить его в containerd k3s (без внешнего registry):

   ```bash
   ./build-and-load.sh
   ```

   **После этого шага обязательно проверьте точное имя образа**, под которым
   его увидел containerd:

   ```bash
   ssh <user>@<vps-host> 'sudo k3s ctr images list | grep php-helloworld'
   ```

   Обычно это `docker.io/library/php-helloworld:latest` (containerd
   нормализует непомеченные registry-именем образы так же, как Docker Hub).
   Если это так — поправьте `image:` в [deployment.yaml](deployment.yaml)
   на именно эту строку перед следующим шагом (по умолчанию там указано
   короткое `php-helloworld:latest` — может не совпасть).

4. Задеплоить:

   ```bash
   ./deploy.sh
   ```

   В конце скрипт выведет `http://<VPS_HOST>/` — откройте в браузере.
   Обновите страницу несколько раз: поды могут отличаться (`POD_NAME`),
   но `NODE_NAME` всегда будет один и тот же — здесь всего одна нода
   (сама VPS), в отличие от локального/облачного вариантов с несколькими
   нодами.

5. Удаление:

   ```bash
   ./destroy.sh                  # только ресурсы приложения
   ./destroy.sh --uninstall-k3s  # + полностью снести k3s с VPS
   ```

## Диагностика

```bash
# Статус самого k3s на сервере
ssh <user>@<vps-host> 'sudo systemctl status k3s'

# Логи k3s
ssh <user>@<vps-host> 'sudo journalctl -u k3s -f'

# Поды/события через локальный kubeconfig
kubectl --kubeconfig kubeconfig get pods -o wide
kubectl --kubeconfig kubeconfig describe pod <pod-name>

# Статус Ingress/Traefik
kubectl --kubeconfig kubeconfig get ingress
kubectl --kubeconfig kubeconfig -n kube-system get pods -l app.kubernetes.io/name=traefik
```

Если `http://<VPS_HOST>/` не отвечает — почти всегда одна из двух причин:
1. Порт 80 закрыт в firewall провайдера (проверьте security group/файрвол
   в панели VPS, а не только `ufw`/`iptables` на самом сервере).
2. Образ не найден подами (`ImagePullBackOff`/`ErrImageNeverPull`) — см.
   пункт про сверку имени образа в шаге 3.

## Многонодовый k3s (опционально)

Если нужно несколько нод, как в примерах с 3 репликами в других вариантах,
k3s это тоже умеет: на первой VPS `curl -sfL https://get.k3s.io | sh -`
поднимает master, а на дополнительных серверах присоединяетесь агентом:

```bash
# на новой VPS-ноде
curl -sfL https://get.k3s.io | K3S_URL=https://<master-ip>:6443 \
    K3S_TOKEN=<токен из /var/lib/rancher/k3s/server/node-token на мастере> sh -
```

Этот сценарий не автоматизирован в `install-k3s.sh` (он ставит только
одну ноду).
