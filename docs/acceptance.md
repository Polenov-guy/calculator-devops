# Приёмка

| Проверка | Результат / доказательство |
|---|---|
| Go unit/API/storage tests | См. VALIDATION.md |
| Сборка Linux amd64 и SHA256 | См. VALIDATION.md |
| Локальный HTTP smoke test | См. VALIDATION.md |
| Browser UI | См. VALIDATION.md |
| Полный Docker Compose | Заполнить после запуска Docker/CI |
| cAdvisor CPU/RAM и лимиты | Заполнить после VPS |
| Node Exporter total/available/used | Заполнить после VPS |
| Health при остановке приложения | Заполнить после VPS |
| Открытия страницы за час | Заполнить после VPS |
| Автодеплой после push | Ссылка на Actions run: … |
| Изменение приложения видно | Старый SHA: … / новый SHA: … |
| Автоматический откат плохого релиза | Actions run и восстановленный SHA: … |
| Ручной rollback | Восстановленный SHA: … |
| История после пересоздания app | Заполнить после VPS |
| Метрики после перезапуска Prometheus | Заполнить после VPS |
| Автовосстановление после reboot VPS | Заполнить после VPS |
| Запуск преподавателем по README | Заполнить |

Команды на VPS из текущего release, `export APP_HOME=/opt/calculator; source scripts/common.sh`:

```bash
compose stop app
# Подождать 30–60 секунд: HTTP probe станет 0, графики недоступности сохранятся.
compose start app
compose up -d --force-recreate app
# История того же браузера должна сохраниться.
compose restart prometheus grafana
# Исторические данные и dashboard должны сохраниться.
```

Не выполняйте `down -v`. До reboot сохраните SSH-доступ и оплаченное время VPS. После reboot проверьте реальные публичные URLs с другого устройства.
