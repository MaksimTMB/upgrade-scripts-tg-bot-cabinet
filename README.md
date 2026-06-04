# 🤖 Upgrade Scripts — TG Bot & Cabinet

[![Release](https://img.shields.io/github/v/release/MaksimTMB/upgrade-scripts-tg-bot-cabinet?sort=semver)](https://github.com/MaksimTMB/upgrade-scripts-tg-bot-cabinet/releases)
[![Changelog](https://img.shields.io/badge/CHANGELOG-md-blue)](CHANGELOG.md)

Скрипты для обновления [remnawave-bedolaga-telegram-bot](https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot) и [bedolaga-cabinet](https://github.com/BEDOLAGA-DEV/bedolaga-cabinet) на продакшн сервере.

> **⚠ v2.0.0 breaking** — теперь скрипты обязательно запускать через `sudo`
> (репы в `/opt/` принадлежат root). См. [CHANGELOG.md](CHANGELOG.md).

---

## 📦 Состав

| Файл | Назначение |
|------|-----------|
| `update-bot.sh` | Обновление Telegram-бота |
| `update-cabinet.sh` | Обновление веб-кабинета |

---

## 🚀 Установка на сервер

```bash
cd /opt
git clone https://github.com/MaksimTMB/upgrade-scripts-tg-bot-cabinet.git upgrade-scripts
sudo cp upgrade-scripts/update-bot.sh /opt/remnawave-bot/update-bot.sh
sudo cp upgrade-scripts/update-cabinet.sh /opt/bedolaga-cabinet/update-cabinet.sh
sudo chmod +x /opt/remnawave-bot/update-bot.sh /opt/bedolaga-cabinet/update-cabinet.sh
```

---

## ▶️ Использование

```bash
# Обновить бот до последнего тега
cd /opt/remnawave-bot && sudo ./update-bot.sh

# Обновить бот до конкретного тега (двухходовка / возврат назад)
cd /opt/remnawave-bot && sudo ./update-bot.sh v3.55.0

# Без интерактивного y/N (для cron / автоматизации)
cd /opt/remnawave-bot && sudo AUTO_CONFIRM=y ./update-bot.sh

# Обновить кабинет
cd /opt/bedolaga-cabinet && sudo ./update-cabinet.sh
cd /opt/bedolaga-cabinet && sudo ./update-cabinet.sh v1.52.0   # конкретный тег
```

**Запускать из-под root / через sudo.** В `/opt/remnawave-bot` и `/opt/bedolaga-cabinet`
рабочие репозитории и compose принадлежат root — без sudo `git` упадёт с
"detected dubious ownership", а `docker compose` — с "permission denied on
docker.sock".

### Аргументы и переменные окружения

| | |
|--|--|
| `$1` | Целевой тег (опционально). По умолчанию — последний по `sort -V`. Если тег не найден локально — ошибка с подсказкой. |
| `AUTO_CONFIRM=y` | Пропустить интерактивное подтверждение `y/N`. Полезно через несколько SSH-прыжков, где TTY не пробрасывается. |

---

## ⚙️ Что делает update-bot.sh

1. Снимает снапшот текущего `docker-compose.yml` в `/opt/backups/auto-<TS>/` (на случай отката).
2. Получает теги с GitHub.
3. Выбирает целевую версию: `$1` или последний по `sort -V`.
4. Показывает список новых Alembic-миграций и upstream-изменений `docker-compose.yml`.
5. Подтверждение `y/N` (можно обойти через `AUTO_CONFIRM=y`).
6. Снимает локальные правки (`git reset --hard` + `git clean -fd -e locales -e locales/`) — кастомные `locales/` бэкапятся в `$BACKUP_DIR` перед сбросом.
7. `git checkout <tag>`, забирает `uv.lock` строго из тега.
8. **Идемпотентно** патчит `docker-compose.yml` (повторный запуск ничего не дублирует):
   - `postgres_data` / `redis_data` → `external: true, name: remnawave-bedolaga-telegram-bot_*`
   - `vpn_logo.png` → `freenet_logo.jpg`
   - добавляет `dns: 8.8.8.8 / 1.1.1.1` в сервис bot (если ещё нет)
9. Регенерирует `uv.lock` через `docker run python:3.13-slim`.
10. `docker compose build --no-cache` → `down` → `up -d`.
11. Хвост логов 20с и `docker compose ps`.

## ⚙️ Что делает update-cabinet.sh

1. Снапшот `docker-compose.yml` в `/opt/backups/auto-<TS>/`.
2. Получает теги, выбирает целевую версию.
3. Показывает diff `docker-compose.yml`.
4. Подтверждение `y/N` (или `AUTO_CONFIRM=y`).
5. `git reset --hard` + `git clean -fd` + `git checkout <tag>`.
6. `build --no-cache` → `down` → `up -d`.
7. Хвост логов 15с и `docker compose ps`.

---

## 🔒 Безопасность данных

- **External volumes** для бота (`postgres_data`, `redis_data`) — данные не пересоздаются и не удаляются при пересборке.
- Перед каждым запуском compose снапшотится в `/opt/backups/auto-<TS>/` — можно откатить вручную.
- **Авто-`pg_dump` БД бота ДО миграций (v2.2.0, шаг 3a).** После подтверждения, пока
  старый стек ещё поднят, скрипт снимает `pg_dump --clean --if-exists`, сжимает в
  `/opt/backups/auto-<TS>/bot-db-remnawave_bot.sql.gz` и проверяет, что дамп не пустой.
  Если postgres недоступен или дамп не снялся — апдейт прерывается ДО применения
  миграций. Закрывает класс рисков «разрушительная миграция / startup-чистка»
  (напр. дедуп подписок в боте v3.59.0). Ручной дамп больше не нужен.
- Если уже на последнем теге — скрипт завершается без действий.

---

## ⚠️ Предполётный чек-лист

1. **Свободное место на диске** — `df -h /`. Сборка нового образа бота забирает ~1 GB, кабинет ~100 MB, build-кэш Docker растёт быстро. Перед апдейтом полезно:
   ```bash
   sudo docker builder prune -af
   sudo docker image prune -af
   ```
2. **Бэкап БД** для бота снимается скриптом автоматически (шаг 3a) — отдельно делать не нужно.
3. Среди новых миграций бывают `UNIQUE`-индексы — могут упасть на боевых дубликатах. Просмотри `=== Alembic migrations ===` в выводе скрипта перед `y`.

---

## 🔄 Откат

```bash
# 1. Бот — на предыдущий тег
cd /opt/remnawave-bot && sudo ./update-bot.sh v3.55.0   # вернуть на 3.55

# 2. Если миграции уже прошли и нужен полный rollback БД — восстановить авто-дамп:
gunzip -c /opt/backups/auto-<TS>/bot-db-remnawave_bot.sql.gz \
  | sudo docker exec -i remnawave_bot_db psql -U remnawave_user -d remnawave_bot

# 3. Откатить compose-патч (если нужно)
sudo cp /opt/backups/auto-<TS>/bot-docker-compose.yml.before /opt/remnawave-bot/docker-compose.yml
```

---

## 🔄 Обновление самих скриптов

```bash
cd /opt/upgrade-scripts && sudo git pull
sudo cp update-bot.sh /opt/remnawave-bot/update-bot.sh
sudo cp update-cabinet.sh /opt/bedolaga-cabinet/update-cabinet.sh
sudo chmod +x /opt/remnawave-bot/update-bot.sh /opt/bedolaga-cabinet/update-cabinet.sh
```
