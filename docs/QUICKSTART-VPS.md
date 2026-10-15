# Быстрый запуск на VPS

## 1. Где арендовать

Проверено 15.10.2026 по официальным страницам:

| Провайдер | Конфигурация | Опубликованная цена | Ссылка |
|---|---|---|---|
| Selectel — основной вариант | VDS 2-4-50: 2 vCPU, 4 ГБ, 50 ГБ | 650 ₽/мес | https://selectel.ru/services/cloud/vps-vds/ |
| Beget — резервный | 2 ядра, 4 ГБ, 40 ГБ | 33 ₽/день | https://beget.com/ru/vps |

Это опубликованные тарифы, не итоговый расчёт заказа. Проверьте стоимость IPv4, наличие выбранного тарифа, требования регистрации, размер пополнения, трафик и дополнительные услуги перед оплатой. Подойдёт также сервер преподавателя с указанными ресурсами.

Выбрать чистую **Ubuntu Server 24.04 LTS, amd64**, rootful Docker; обычную VM с root/sudo, публичным IPv4. Тариф 4 ГБ выбран для всего мониторинга с запасом. Домен для сдачи не требуется. На IP используется HTTP, административные секреты по нему не передавать. Для HTTPS с доменом потребуется отдельная настройка reverse proxy; в этот комплект она не включена.

В файрволе провайдера открыть входящие TCP 22, 80, 3000. Для 22 нужны подключения и с вашего IP, и из GitHub-hosted runner (его адрес непостоянный). Практический вариант для учебной VM — 22 из интернета с SSH-ключом, после проверки key login отключить password login. Экспортеры и Prometheus наружу не открывать. Исходящий HTTPS/DNS разрешить.

## 2. Загрузить проект в GitHub

На своём компьютере распакуйте архив. Создайте пустой **публичный** GitHub repository `calculator-devops`, без автоматически создаваемого README. Из каталога проекта:

```bash
git init -b main
git add .
git commit -m "Add calculator with artifact-based CI/CD and monitoring"
git remote add origin https://github.com/YOUR_LOGIN/calculator-devops.git
git push -u origin main
```

Локальная авторизация GitHub должна быть настроена (например, GitHub CLI `gh auth login`). Если репозиторий уже создан иначе, используйте его URL.

Дождитесь jobs build/package. Deploy пока пропущен — так задумано. В GitHub → профиль → Packages → package этого repository → Package settings → Change visibility → Public. Проверить, что последний образ скачивается без docker login. Если публикация запрещена политикой организации, используйте личный repository или настройте permissions организации.

Из Actions скачайте artifact `image-reference` и запишите строку `ghcr.io/LOGIN/calculator-devops@sha256:...`. Из страницы commit скопируйте полный SHA. Они нужны для первого ручного проверочного деплоя.

## 3. Подготовить ключ для CI

На своём компьютере:

```bash
ssh-keygen -t ed25519 -f ./calculator_deploy -C calculator-ci -N ''
```

Файлы ключей держать вне проекта. Public key `calculator_deploy.pub` передать серверу, private key — только в GitHub Secret. Личный SSH-ключ, которым вы вошли как root, можно оставить отдельно.

## 4. Подготовить Ubuntu

Замените SERVER_IP и YOUR_LOGIN на реальные значения. Войти на сервер через выданный провайдером root/sudo доступ:

```bash
ssh root@SERVER_IP
apt-get update
apt-get install -y git
mkdir -p /root/calculator-setup
git clone https://github.com/YOUR_LOGIN/calculator-devops.git /root/calculator-setup/project
```

На своём компьютере передать public key:

```bash
scp calculator_deploy.pub root@SERVER_IP:/root/calculator_deploy.pub
```

На сервере:

```bash
cd /root/calculator-setup/project
DEPLOY_PUBLIC_KEY_FILE=/root/calculator_deploy.pub bash scripts/bootstrap-server.sh
```

Bootstrap устанавливает Docker/Compose из официального репозитория и создаёт deploy с доступом к Docker. Он предназначен для чистой Ubuntu; не запускайте на сервере с существующей конфигурацией Docker без проверки.

Из нового локального терминала проверить:

```bash
ssh -i ./calculator_deploy deploy@SERVER_IP 'docker info >/dev/null && docker compose version'
```

## 5. Первый проверочный deploy

Войти как deploy:

```bash
ssh -i ./calculator_deploy deploy@SERVER_IP
```

Далее **на сервере**, заменив YOUR_LOGIN:

```bash
cd /opt/calculator
git clone https://github.com/YOUR_LOGIN/calculator-devops.git releases/initial
cd releases/initial
bash scripts/init-env.sh
mv .env /opt/calculator/.env
export APP_HOME=/opt/calculator
bash scripts/preflight.sh
```

Preflight проверяет доступ к Docker, mounts cAdvisor, скачивает образы мониторинга и проверяет Prometheus config. При ошибке загрузки GHCR проверьте сеть провайдера и public visibility package. Не продолжайте до успеха.

Вставить digest и SHA **из одного и того же workflow run**:

```bash
APP_HOME=/opt/calculator bash scripts/deploy.sh \
  ghcr.io/YOUR_LOGIN/calculator-devops@sha256:PASTE_64_HEX_DIGEST \
  PASTE_FULL_COMMIT_SHA
```

После успеха проверить метрики (до минуты ожидания scrape):

```bash
bash scripts/verify-monitoring.sh
```

После успеха:

- http://SERVER_IP — калькулятор;
- http://SERVER_IP/version — SHA;
- http://SERVER_IP:3000/d/calculator — dashboard;
- http://SERVER_IP/metrics — метрики приложения.

Проверить адреса с вашего компьютера. Подождать 1–5 минут для накопления rate/increase. Открыть страницу несколько раз и выполнить вычисления. Проверить, что панели cAdvisor не пустые: это обязательная отдельная проверка совместимости Docker/cAdvisor.

## 6. Подключить автоматический deploy

Получить SSH host key. На своём компьютере:

```bash
ssh-keyscan -t ed25519 SERVER_IP > calculator_known_hosts
ssh-keygen -lf calculator_known_hosts
```

Сравнить fingerprint с выводом **в консоли провайдера / доверенной SSH-сессии**:

```bash
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

В GitHub Settings → Secrets and variables → Actions → Secrets:

| Secret | Значение |
|---|---|
| DEPLOY_HOST | IPv4 без http:// |
| DEPLOY_USER | deploy |
| DEPLOY_SSH_KEY | Полное содержимое calculator_deploy, включая BEGIN/END |
| DEPLOY_KNOWN_HOSTS | Полное содержимое calculator_known_hosts |

В Actions Variables: `DEPLOY_ENABLED=true`. Создать GitHub Environment `production`, если он не появился автоматически. Required reviewers не нужны для автоматической сдачи.

В Actions → Calculator CI-CD → Run workflow → main. Или сделать новый commit. Workflow скопирует исходный bundle в отдельный release directory, выполнит deploy и smoke test. Сервер ничего не компилирует.

## 7. Показать изменение и откат

Внести заметное изменение в `cmd/calculator/web/index.html` (например, заголовок) или реализовать новую операцию вместе с тестом. Commit/push → зелёный deploy → новый SHA и интерфейс на сервере.

Откат на сервере:

```bash
cd "$(cat /opt/calculator/.state/current-release)"
APP_HOME=/opt/calculator bash scripts/rollback.sh
```

Проверить старый SHA и сохранность истории. Для проверки автоматического отката можно в отдельном учебном commit намеренно изменить readiness так, чтобы он возвращал 503; deploy должен упасть и вернуть предыдущую рабочую версию. После демонстрации исправить commit и выполнить штатный deploy.

## 8. Сохранить результат и сдать

```bash
git tag v1.0.0
git push origin v1.0.0
```

Tag workflow создаст Release, но не обновит production (production обновляется из main). Проверить соответствие SHA тега развёрнутому SHA. Заполнить docs/report.md и acceptance.md реальными URL, run ID и результатами. Оставить VPS оплаченным до проверки. Перед удалением VPS скачать резервную копию и артефакты.

## Если не открывается

- SSH работает, HTTP нет: проверить provider firewall, `compose ps`, логи app, отсутствие другого процесса на порту 80.
- Permission denied в /data: проверить UID/GID volume. Новый volume получает права 10001 из image; старый произвольный volume может иметь другие права.
- Grafana пуста: открыть через SSH-туннель Prometheus /targets; проверить scrape jobs, ждать rate window, логи exporter.
- cAdvisor пуст: проверить rootful Docker, data-root, cgroup mounts и версию cAdvisor. preflight не заменяет проверку фактических метрик.
- GHCR unauthorized: package Public и правильный lower-case repository path.
- SSH CI host key verification failed: сравнить и обновить доверенный host key; не отключать StrictHostKeyChecking.

Доступ к Prometheus без публикации в интернет:

```bash
ssh -i ./calculator_deploy -L 9090:127.0.0.1:9090 deploy@SERVER_IP
```

Затем http://localhost:9090/targets и /alerts. Dashboard и datasource уже хранятся в Git; для изменения редактируйте JSON/YAML и публикуйте новый commit.
