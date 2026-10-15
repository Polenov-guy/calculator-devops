# Калькулятор в Docker: CI/CD и мониторинг

Дата выполнения: 15 октября 2026 года. Сдаваемая версия исходников: **v1.0.0**, commit **8dca36873fb1797ff174d081375984daa14837b2**.

## 1. Ссылки для проверки

| Объект | Ссылка |
|---|---|
| Работающее приложение | http://89.232.176.61 |
| Grafana dashboard | http://89.232.176.61:3000/d/calculator |
| Метрики приложения | http://89.232.176.61/metrics |
| Readiness | http://89.232.176.61/readyz |
| Версия приложения | http://89.232.176.61/version |
| Репозиторий | https://github.com/Polenov-guy/calculator-devops |
| Зафиксированные исходники | https://github.com/Polenov-guy/calculator-devops/tree/v1.0.0 |
| Полный CI/CD после изменения интерфейса | https://github.com/Polenov-guy/calculator-devops/actions/runs/38738210665 |
| Повторный deploy после проверки rollback | https://github.com/Polenov-guy/calculator-devops/actions/runs/38739786234 |
| Сборка и публикация Release | https://github.com/Polenov-guy/calculator-devops/actions/runs/38741357113 |
| Release v1.0.0 | https://github.com/Polenov-guy/calculator-devops/releases/tag/v1.0.0 |
| Container package | https://github.com/users/Polenov-guy/packages/container/package/calculator-devops |

Grafana открыта для анонимного чтения с ролью Viewer. SSH и административные доступы для проверки интерфейса не требуются.

## 2. Приложение и сервер

Реализован калькулятор на Go со встроенными HTML/CSS/JavaScript. Доступны сложение, вычитание, умножение и деление, дробные и отрицательные числа, обработка некорректного ввода, деления на ноль и переполнения. Вычисления выполняются серверным API. История хранится в SQLite и изолирована по анонимному cookie браузера; на сессию сохраняются последние 100 записей.

Приложение развёрнуто в Cloud.ru Evolution на VM `vm-web-server`: Ubuntu Server 24.04 LTS amd64, 2 vCPU, 4 ГБ RAM, SSD 20 ГБ, публичный IPv4 89.232.176.61. Использованы Docker Engine и Compose plugin; на сервере подтверждена версия Docker Compose v5.6.0.

Открыты TCP 22 (SSH), 80 (приложение), 3000 (Grafana). Исходящий доступ разрешён для установки пакетов и скачивания образов. В дальнейшем деплой выполняется отдельным пользователем `deploy`, имеющим доступ к Docker, с отдельным SSH-ключом CI. Приватный ключ хранится в GitHub Secrets и не включён в исходники.

## 3. Путь от исходного кода до работающего контейнера

1. Исходники и инфраструктурная конфигурация сохраняются в GitHub.
2. GitHub Actions запускает тесты Go, проверки API/SQLite и тесты поведения deploy-скрипта.
3. Приложение компилируется под linux/amd64 с CGO_ENABLED=0. В бинарник встраиваются frontend и Git commit SHA.
4. В самостоятельный сборочный артефакт включаются бинарник `calculator`, `build-info.json`, файл SHA256SUMS и каталог данных. Артефакт сохраняется в GitHub Actions.
5. Следующий job скачивает сохранённую сборку, проверяет SHA256 и упаковывает именно её в Docker image. Runtime Dockerfile не компилирует исходники.
6. В CI запускается контейнерный интеграционный тест, включая сохранность SQLite volume при пересоздании контейнера, и проверяется конфигурация Prometheus.
7. Образ публикуется в GHCR с тегом commit SHA. Для сервера передаётся immutable image reference с digest.
8. Deploy job передаёт исходный bundle конфигурации в отдельный release directory на VPS и запускает `deploy.sh` через SSH.
9. Перед обновлением сохраняется предыдущий release и выполняется SQLite online backup. Compose скачивает и запускает образ.
10. После обновления проверяются readiness, ожидаемая версия, вычисление 7×6=42, чтение истории и наличие обязательных метрик мониторинга. При сбое deploy-скрипт пытается восстановить предыдущие образ и конфигурацию.

PR запускает тесты/сборку; push в main — весь CI/CD; тег v* — сборку, публикацию образа и GitHub Release. Deploy по тегу не выполняется.

## 4. Сдаваемые файлы

Все ссылки ниже закреплены на v1.0.0.

| Назначение | Файл |
|---|---|
| Runtime image | https://github.com/Polenov-guy/calculator-devops/blob/v1.0.0/Dockerfile |
| Среда локальной сборки | https://github.com/Polenov-guy/calculator-devops/blob/v1.0.0/Dockerfile.build |
| Контейнерный стек | https://github.com/Polenov-guy/calculator-devops/blob/v1.0.0/compose.yaml |
| CI/CD workflow | https://github.com/Polenov-guy/calculator-devops/blob/v1.0.0/.github/workflows/ci-cd.yml |
| Сборка | https://github.com/Polenov-guy/calculator-devops/blob/v1.0.0/scripts/build.sh |
| Упаковка сборки | https://github.com/Polenov-guy/calculator-devops/blob/v1.0.0/scripts/package.sh |
| Деплой | https://github.com/Polenov-guy/calculator-devops/blob/v1.0.0/scripts/deploy.sh |
| Откат | https://github.com/Polenov-guy/calculator-devops/blob/v1.0.0/scripts/rollback.sh |
| Резервное копирование | https://github.com/Polenov-guy/calculator-devops/blob/v1.0.0/scripts/backup.sh |
| Подготовка Ubuntu | https://github.com/Polenov-guy/calculator-devops/blob/v1.0.0/scripts/bootstrap-server.sh |
| Мониторинг | https://github.com/Polenov-guy/calculator-devops/tree/v1.0.0/monitoring |
| Переиспользуемые запросы к ИИ | https://github.com/Polenov-guy/calculator-devops/blob/v1.0.0/docs/prompts.md |

Сборка и конфигурация дополнительно сохранены в Release:

- https://github.com/Polenov-guy/calculator-devops/releases/download/v1.0.0/calculator-linux-amd64.tar.gz
- https://github.com/Polenov-guy/calculator-devops/releases/download/v1.0.0/deploy-bundle.tar.gz
- https://github.com/Polenov-guy/calculator-devops/releases/download/v1.0.0/image-reference.txt

SHA256 архива бинарной сборки по GitHub Release: `fc72aa30780af9a4f2294c20c158d362ae196ce571b2190be25c86de900ed642`.

Tag workflow собирает приложение повторно. Исходники Release и развёрнутой версии имеют одинаковый commit SHA, однако время сборки и digest образа в Release могут отличаться от образа последнего deploy из main. Фактический работающий image reference можно получить на VPS командой `docker inspect calculator-app-1 --format '{{.Config.Image}}'`.

## 5. Мониторинг и постоянное хранение

Использован стек Prometheus, Grafana, Node Exporter, cAdvisor и Blackbox Exporter. Prometheus опрашивает targets каждые 15 секунд. Dashboard и datasource Grafana автоматически создаются из файлов репозитория.

| Требование | Реализация |
|---|---|
| Использованные и доступные ресурсы | Node Exporter: CPU %, количество vCPU, RAM used/available/total, диск used/available |
| Ресурсы приложения | cAdvisor: CPU, RAM working set, ограничения CPU и RAM контейнера |
| Health check | `/healthz`, `/readyz`, Docker HEALTHCHECK, Blackbox HTTP probe, Prometheus up |
| Посещения за час | Counter calculator_page_views_total и запрос sum(increase(calculator_page_views_total[1h])) |
| Использование калькулятора | calculator_calculations_total по операциям и результату success/error |
| Версия | `/version` и calculator_build_info |

Посещение определено как GET главной страницы `/`; обновление страницы считается новым открытием. API, scrape метрик и health checks не включаются. Это число открытий, а не уникальных пользователей. PromQL increase экстраполирует выборки и может давать дробный результат; reset counter после рестарта учитывается по наблюдаемым значениям.

Именованные volumes сохраняют SQLite (`calculator_data`), TSDB (`prometheus_data`) и Grafana (`grafana_data`). Для Prometheus заданы retention 15 дней и ограничение 3 ГБ; Docker-логи ограничены ротацией. Restart policy — unless-stopped. Приложение работает с UID 10001 и read-only root filesystem, запись разрешена в volume /data.

## 6. Подтверждённые результаты

| Проверка | Полученный результат |
|---|---|
| Сборка и сохранение артефакта | GitHub Actions build/package завершились успешно |
| Полный автоматический deploy | Deploy job завершился успешно, приложение доступно по публичному IP |
| Изменение приложения | Заголовок изменён с «Всё сходится.» на «Калькулятор — версия 2»; после commit/push изменение появилось на сервере |
| Версия после изменения | 8dca36873fb1797ff174d081375984daa14837b2 |
| Ручной rollback | rollback.sh восстановил 88a451009260c0eb04e4b828fbf8ba48d631c90b; smoke test завершился PASS, Rollback complete |
| Возврат новой версии | Повторный workflow из main успешно восстановил 8dca368 |
| Перезагрузка VPS | После reboot все 6 контейнеров запустились автоматически; app и cAdvisor healthy |
| Smoke test после reboot | PASS readiness, version, calculation and session history; version=8dca36873fb1797ff174d081375984daa14837b2 |
| Мониторинг после reboot | PASS all monitoring targets and required host/container metrics |
| Сохранение пользовательских данных | Пользователь подтвердил сохранность прежней истории после reboot |
| Выпуск финальных артефактов | Release v1.0.0 опубликован github-actions, три подготовленных asset присутствуют |

Статусы workflow и assets проверены через GitHub API. Работа интерфейсов подтверждена скриншотами пользователя; server-side проверки и rollback — приведённым пользователем выводом команд. Прямое управление сервером из среды подготовки не выполнялось.

Механизм автоматического rollback при неудачном deploy реализован и проверен локальными тестами с fake Docker. Намеренно неисправный релиз на рабочий VPS не выкатывался; такой сценарий не заявляется как проверенный на сервере. Ручной откат на VPS проверен фактически.

## 7. Воспроизведение преподавателем

Для всего стека: чистая Ubuntu 24.04 amd64 VM, 2 vCPU, 4 ГБ RAM, диск от 20 ГБ с достаточным свободным местом; стандартный rootful Docker data-root /var/lib/docker и устройства /dev/kmsg, /dev/disk. Нужны доступ к GitHub/GHCR/Docker registry и свободные порты 80/3000.

```bash
# На чистой Ubuntu через пользователя с sudo:
sudo apt-get update
sudo apt-get install -y git

git clone --branch v1.0.0 --depth 1 https://github.com/Polenov-guy/calculator-devops.git
cd calculator-devops

sudo bash scripts/bootstrap-server.sh
sudo usermod -aG docker "$USER"
```

После выхода и нового входа в систему:

```bash
cd calculator-devops
bash scripts/init-env.sh
bash scripts/preflight.sh
bash scripts/start-local.sh
bash scripts/verify-monitoring.sh
```

`start-local.sh` выполняет тесты, сборку, упаковку, запуск Compose и smoke test. При отсутствии локального Go используется Dockerfile.build. Приложение доступно на http://SERVER_IP, Grafana на http://SERVER_IP:3000/d/calculator. Для проверки на локальной машине — localhost. При занятых портах изменить .env до запуска. Для проверки метрик после старта может потребоваться несколько scrape.

Для собственного CI/CD fork/копии нужны четыре Secrets: DEPLOY_HOST, DEPLOY_USER, DEPLOY_SSH_KEY, DEPLOY_KNOWN_HOSTS, и Repository variable DEPLOY_ENABLED=true. Пакет GHCR должен быть публичным либо серверу потребуется отдельная авторизация. Подробная настройка приведена в docs/QUICKSTART-VPS.md.

## 8. Повторяемые команды эксплуатации

На рабочем VPS под deploy:

```bash
cd "$(cat /opt/calculator/.state/current-release)"
export APP_HOME=/opt/calculator

bash scripts/smoke-test.sh http://127.0.0.1
bash scripts/verify-monitoring.sh
bash scripts/backup.sh
```

Откат:

```bash
APP_HOME=/opt/calculator bash scripts/rollback.sh
```

Для возврата актуального main повторно запустить Calculator CI-CD через workflow_dispatch. Не применять `docker compose down -v`: это удалит постоянные данные.

## 9. Переиспользуемый запрос и результат

> Реализуй веб-калькулятор на Go со встроенными HTML/CSS/JS, серверными вычислениями и историей по анонимным сессиям в SQLite. Подготовь тесты, Dockerfile для упаковки заранее собранного бинарника, Compose с постоянными volumes и мониторингом Prometheus/Grafana/Node Exporter/cAdvisor/Blackbox. Настрой CI/CD: тесты и сборка → сохранение бинарного артефакта → скачивание того же артефакта отдельным job → Docker image → GHCR → SSH deploy по digest на Ubuntu 24.04 amd64. Добавь readiness/version checks, smoke test, backup и rollback. Dashboard должен показывать потребляемые и доступные ресурсы, health и открытия страницы за последний час. Дай воспроизводимые скрипты запуска для преподавателя. Отдели фактически проверенные результаты от реализованных, но непроверенных сценариев.

Полученный результат: работающий калькулятор и мониторинг по публичным адресам, GitHub-репозиторий, успешный автоматический CI/CD, сохранённые сборочные артефакты и Release v1.0.0. Проверены изменение приложения, ручной rollback, восстановление актуальной версии и запуск с сохранением истории после reboot VPS.

## 10. Эксплуатационные ограничения

Один VPS; обновление контейнера допускает короткий перерыв. В базовой конфигурации HTTP по IP. Backup автоматически сохраняется на том же сервере, поэтому для защиты от потери VM его необходимо скачать отдельно. Blackbox проверяет readiness из сети VPS, а не внешнюю доступность облачной инфраструктуры. Доставка alert-уведомлений не настроена. Версии сторонних actions/images зафиксированы тегами, не SHA/digest. Вычисления используют float64. Сервер необходимо оставить работающим и оплаченным до проверки преподавателем.

Этот отчёт фиксирует завершённые серверные этапы и дополняет первоначальные шаблоны report.md/acceptance.md/VALIDATION.md в теге v1.0.0, подготовленные до аренды VPS.
