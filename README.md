# Калькулятор: сборочный артефакт → Docker → VPS → мониторинг

Go 1.26.9, SQLite (pure Go), Docker Compose, GitHub Actions, GHCR, Prometheus, Grafana, Node Exporter, cAdvisor, Blackbox Exporter.

**Начните с [docs/QUICKSTART-VPS.md](docs/QUICKSTART-VPS.md).** Полная инструкция аренды, создания GitHub-репозитория, настройки SSH и первого деплоя находится там. Результаты доступных проверок — [docs/VALIDATION.md](docs/VALIDATION.md).

## Локальный запуск из исходников

Целевая среда полного стека — Linux amd64 с обычным rootful Docker, cgroup v2, `/var/lib/docker`, `/dev/disk`, `/dev/kmsg`. Для повторения преподавателем удобнее чистая Ubuntu 24.04 VM с 4 ГБ RAM. Docker Desktop поддерживает запуск калькулятора, но метрики Node Exporter относятся к его Linux VM, а настройки cAdvisor могут требовать изменений.

Нужны Docker Engine и Compose plugin, bash, curl, openssl, python3; Go локально необязателен: скрипты используют `Dockerfile.build`.

```bash
bash scripts/init-env.sh
# При занятых портах измените APP_PORT/GRAFANA_PORT в .env.
bash scripts/preflight.sh
bash scripts/start-local.sh
```

Калькулятор: http://localhost ; dashboard: http://localhost:3000/d/calculator .
Grafana доступна для чтения без логина. Форма входа отключена; dashboard provisioned из JSON, ручная настройка не нужна.

Если Go уже установлен:

```bash
bash scripts/test.sh
bash scripts/build.sh
bash scripts/package.sh calculator:local
docker compose up -d --wait
bash scripts/smoke-test.sh http://localhost
```

Только приложение без Docker, например для изменения интерфейса:

```bash
go mod download
DB_PATH=./data/calculator.db LISTEN_ADDR=127.0.0.1:8080 go run ./cmd/calculator
```

Открыть http://localhost:8080 . Сервер встраивает файлы `cmd/calculator/web/` при компиляции; после правок нужен повторный запуск/сборка.

## Что реализовано

- Серверные операции add/subtract/multiply/divide; отрицательные, дробные числа, проверка переполнения и деления на ноль.
- Интерфейс с клавиатурным вводом, запятой/точкой, переключением операции и историей.
- SQLite WAL, до 100 записей на сессию; при вычислениях удаляются записи старше 30 дней.
- Случайный HttpOnly SameSite cookie для изоляции истории браузеров. Это учебная анонимная сессия, не система аккаунтов.
- Health/readiness, версия сборки, Prometheus counters, graceful shutdown.
- Runtime image `FROM scratch`, UID/GID 10001, read-only root filesystem; запись только в data volume.
- Ограничения CPU/RAM, ротация логов, restart policy, постоянное имя Compose проекта.
- Сохранение бинарной сборки, публикация образа по SHA, деплой по digest, smoke test, backup и rollback.

## CI/CD

Pull request: тесты и сборка. Push в main: тесты → tar.gz с бинарником и SHA256 → upload artifact → отдельный package job скачивает **тот же** tar.gz → Docker build → интеграционный тест контейнера и сохранности SQLite → push GHCR → deploy (когда включён).

`Dockerfile` не компилирует исходники: он копирует сохранённый результат `dist/calculator`. `Dockerfile.build` задаёт локальную среду компиляции. Артефакты Actions хранятся 90 дней. Тег `v*` создаёт GitHub Release с бинарником, source bundle и image reference. Не удаляйте сдаваемый Release, workflow и GHCR image до проверки.

Для GHCR в workflow применяется GITHUB_TOKEN с packages:write. По умолчанию новый package может быть private: переключите его на Public до серверного деплоя. Теги образов содержат SHA, деплой получает immutable digest. Версии сторонних образов и actions зафиксированы тегами, но не digest/SHA: это не гарантия побитной воспроизводимости внешнего supply chain. go.sum фиксирует контрольные суммы Go-модулей.

## Мониторинг

Сбор каждые 15 секунд, retention Prometheus 15 дней или 3 ГБ. Данные сохраняются в именованных volumes. Dashboard UID `calculator`, часовой пояс Asia/Yekaterinburg.

- Node Exporter: использованный CPU, число ядер, RAM total/available/used, свободный и занятый диск.
- cAdvisor: CPU/RAM контейнера и лимиты 0.5 CPU / 256 MiB.
- Blackbox: HTTP-проверка `/readyz`; Prometheus up отдельно показывает успешность scrape.
- `calculator_page_views_total`: успешные GET `/`. Перезагрузка страницы — новое открытие; API, health, metrics и статика не учитываются. Это не уникальные посетители.
- `calculator_calculations_total{operation,status}`: поддерживаемые операции с результатом success/error. Некорректный JSON и неизвестная операция не включаются.
- `calculator_build_info{version}`: версия бинарника.

Посещения за скользящие 60 минут: `sum(increase(calculator_page_views_total[1h]))`. Counter сбрасывается после перезапуска приложения; Prometheus учитывает наблюдаемые reset. Выборки экстраполируются, поэтому increase может быть дробным и не является точным журналом посещений при сбоях между scrape. Данные появляются после нескольких scrape; CPU rate требует времени для окна.

Калькулятор публикует `/metrics` вместе с HTTP API; exporter endpoints не публикуются. Prometheus слушает только 127.0.0.1:9090. Grafana Viewer может выполнять read-only запросы через datasource: в этом учебном stack нет чувствительных данных. Административный пароль хранится только в .env; не используйте его через публичный HTTP. Для управления через API применяйте SSH-туннель или настройте HTTPS.

Blackbox на том же VPS проверяет сервис из Docker-сети, а не доступность VPS из интернета. Ссылки для сдачи проверьте через мобильный интернет.

Правила CalculatorUnavailable и HostMemoryLow видны в Prometheus /alerts; доставки уведомлений нет (Alertmanager не включён).

## Эксплуатация

На VPS текущий release path хранится в `/opt/calculator/.state/current-release`. Во всех ручных командах сначала:

```bash
cd "$(cat /opt/calculator/.state/current-release)"
export APP_HOME=/opt/calculator
```

Просмотр:

```bash
source scripts/common.sh
compose ps
compose logs --tail=100 app
```

Backup: `bash scripts/backup.sh`. Используется SQLite VACUUM INTO при работающем сервере, snapshot копируется в `/opt/calculator/backups`. Последний временный snapshot также остаётся в data volume; старые внешние backups удаляйте по необходимости. Backup на том же диске защищает от неудачного обновления, но не от потери VPS. Для надёжности скачайте backup на свой компьютер.

Rollback: `bash scripts/rollback.sh`. Возвращает предыдущие образ **и** Compose/monitoring config. Данные не откатываются; версия схемы БД в поставляемом приложении одна. Будущие миграции должны оставаться совместимыми. При неудачном первом deploy предыдущего релиза нет: приложение останавливается, логи сохраняются.

Нормальный deploy вызывает compose up, а не down. **Не применять `docker compose down -v` или prune volumes**: это удалит данные. Volumes переживают пересоздание контейнеров и reboot VPS; restart policy работает после запуска Docker.

Временное прерывание сервиса при пересоздании контейнера допустимо для задания; zero-downtime deployment не реализован.

## Файлы сдачи

- Dockerfile, Dockerfile.build, compose.yaml;
- scripts/build.sh, package.sh, deploy.sh, rollback.sh, bootstrap-server.sh;
- workflow `.github/workflows/ci-cd.yml`;
- monitoring/*, provisioned dashboard;
- docs/report.md, prompts.md, acceptance.md;
- GitHub repository, Actions run, GitHub Release, GHCR image;
- http://SERVER_IP и http://SERVER_IP:3000/d/calculator .

Публичные адреса, проверку после reboot, реальный автоматический deploy и rollback заполните после аренды VPS. Они не считаются выполненными этим архивом.

Числа вычисляются в IEEE 754 float64; возможна обычная погрешность двоичной арифметики (например, 0.1 + 0.2). Финансовая decimal-арифметика не реализована.

## Дополнительные проверки

```bash
# Собранный бинарник: HTTP, посещения, backup, перезапуск процесса.
bash scripts/test-binary.sh
# После серверного deploy: targets, HTTP probe, host/container metrics.
bash scripts/verify-monitoring.sh
```

Для UI-теста в отдельной рабочей копии с Node.js и запущенным калькулятором:

```bash
npm install --no-save playwright@1.51.1
npx playwright install --with-deps chromium
BASE_URL=http://localhost node tests/browser.cjs
```

Тест проверяет вычисление, десятичную запятую, сохранение истории после reload, ошибку деления на ноль, отсутствие горизонтального overflow на мобильном экране и JS errors; сохраняет два скриншота в docs/. В исходном комплекте скриншотов нет: браузер не запустился в среде подготовки.
