# Фактически выполненные проверки

Дата подготовки: 15.10.2026. Локальная версия: `local-20261015`.

| Проверка | Результат |
|---|---|
| Компилятор Go 1.26.9 linux-amd64 | Загружен, SHA256 проверен по официальному go.dev download metadata |
| go mod tidy / go.sum | Успех, зависимости разрешены |
| go vet ./... | Успех |
| Go tests: арифметика / overflow / ошибки | Успех |
| Go tests: HTTP API / JSON validation / изоляция сессий | Успех |
| Go tests: повторное открытие SQLite / readiness | Успех |
| Python tests: переходы deploy state с fake Docker | 4 теста, успех |
| Сборка CGO_ENABLED=0 linux/amd64 | Успех; бинарник в dist/calculator |
| HTTP smoke test собранного бинарника | Успех: readiness, version, 7×6=42, запись/чтение истории |
| 10 открытий страницы | Counter вырос до 10 |
| Online backup SQLite | VACUUM INTO, integrity_check=ok, записи сохранены |
| Перезапуск процесса приложения | История той же сессии сохранена |
| Shell syntax всех scripts/*.sh | Успех |
| JavaScript syntax | node --check, успех |
| Docker Compose config | Проверено standalone Docker Compose v2.39.4, успех |
| GitHub Actions workflow | actionlint 1.7.7, успех (без shellcheck) |
| Prometheus config и 2 alert rules | promtool 3.15.0 check config, успех |
| Alert unit tests: сервис доступен / недоступен | promtool test rules, успех |
| Все 19 PromQL expressions dashboard | promtool parser, успех |
| YAML/JSON parse | Успех |

## Что не выполнено

- Полный контейнерный запуск: в среде нет Docker Engine/daemon. Compose config проверен, а запуск, volume ownership и фактические exporter metrics должны проверяться в CI/VPS. Для этого включены scripts/integration-test.sh, preflight.sh и verify-monitoring.sh.
- Браузерная визуальная проверка: штатный browser download не дал корректного архива; отдельно загруженный Chromium не запустился в ограниченной среде (trace/breakpoint trap). Скриншоты не получены, UI не помечен визуально проверенным. В комплекте есть tests/browser.cjs для обычной среды с Playwright.
- Удалённый GitHub repository, Actions run, GHCR image и GitHub Release не созданы. Доступные GitHub capabilities не предоставляют создание нового repository; целевой существующий repository пользователь не задавал.
- Аренда, оплата, SSH-соединение с VPS, сетевой доступ к публичным URL, реальный deploy/rollback и reboot VPS не выполнялись по условию задачи.

Тесты deploy с fake Docker проверяют поведение shell-скрипта при успехе/сбое и восстановление release state. Они не заменяют проверку Docker Engine, SSH, registry и провайдерской сети.
