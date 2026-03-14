# 🤖 Upgrade Scripts — TG Bot & Cabinet

Скрипты для обновления [remnawave-bedolaga-telegram-bot](https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot) и [bedolaga-cabinet](https://github.com/BEDOLAGA-DEV/bedolaga-cabinet) на продакшн сервере FreeNet.

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
git clone https://github.com/MaksimTMB/upgrade-scripts-tg-bot-cabinet.git
cp upgrade-scripts-tg-bot-cabinet/update-bot.sh /opt/remnawave-bot/update-bot.sh
cp upgrade-scripts-tg-bot-cabinet/update-cabinet.sh /opt/bedolaga-cabinet/update-cabinet.sh
chmod +x /opt/remnawave-bot/update-bot.sh /opt/bedolaga-cabinet/update-cabinet.sh
```

---

## ▶️ Использование

```bash
# Обновить бот
cd /opt/remnawave-bot && ./update-bot.sh

# Обновить кабинет
cd /opt/bedolaga-cabinet && ./update-cabinet.sh
```

---

## ⚙️ Что делает update-bot.sh

1. Получает актуальные теги с GitHub
2. Показывает текущую и новую версию
3. Выводит список новых миграций и изменений в `docker-compose.yml`
4. Спрашивает подтверждение `y/N`
5. Делает `git checkout` на новый тег
6. Берёт `uv.lock` строго из тега (без конфликтов)
7. Автоматически патчит `docker-compose.yml`:
   - External volumes (`remnawave-bedolaga-telegram-bot_postgres_data` / `redis_data`)
   - Логотип (`freenet_logo.jpg → /app/vpn_logo.png`)
   - DNS (`8.8.8.8`, `1.1.1.1`)
8. Регенерирует `uv.lock`
9. Собирает образ (`docker compose build --no-cache`)
10. Перезапускает сервисы и показывает логи

## ⚙️ Что делает update-cabinet.sh

1. Получает актуальные теги с GitHub
2. Показывает текущую и новую версию
3. Спрашивает подтверждение `y/N`
4. Сбрасывает локальные изменения и делает `git checkout` на новый тег
5. Собирает образ (`docker compose build --no-cache`)
6. Перезапускает сервисы и показывает логи

---

## 🔒 Особенности

- Скрипты **не трогают данные** — volumes с БД и Redis объявлены как `external`
- При обновлении бота все кастомные настройки `docker-compose.yml` применяются автоматически
- Если версия уже актуальна — скрипт завершается без действий
