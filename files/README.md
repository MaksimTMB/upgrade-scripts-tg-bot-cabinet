# 🤖 Upgrade Scripts — TG Bot & Cabinet

Скрипты для обновления [remnawave-bedolaga-telegram-bot](https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot) и [bedolaga-cabinet](https://github.com/BEDOLAGA-DEV/bedolaga-cabinet) на продакшн сервере.

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
cp upgrade-scripts/update-bot.sh /opt/remnawave-bot/update-bot.sh
cp upgrade-scripts/update-cabinet.sh /opt/bedolaga-cabinet/update-cabinet.sh
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

При **первом запуске** `update-bot.sh` задаст несколько вопросов и сохранит конфиг в `update-bot.conf`. При последующих запусках конфиг подхватывается автоматически.

Чтобы сбросить настройки и пройти настройку заново:
```bash
rm /opt/remnawave-bot/update-bot.conf
./update-bot.sh
```

---

## 🔄 Обновление самих скриптов

```bash
cd /opt/upgrade-scripts && git pull
cp update-bot.sh /opt/remnawave-bot/update-bot.sh
cp update-cabinet.sh /opt/bedolaga-cabinet/update-cabinet.sh
chmod +x /opt/remnawave-bot/update-bot.sh /opt/bedolaga-cabinet/update-cabinet.sh
```

---

## ⚙️ Что делает update-bot.sh

1. При первом запуске спрашивает настройки и сохраняет в `update-bot.conf`
2. Получает актуальные теги с GitHub
3. Показывает текущую и новую версию
4. Выводит список новых миграций и изменений в `docker-compose.yml`
5. Спрашивает подтверждение `y/N`
6. Делает `git checkout` на новый тег
7. Берёт `uv.lock` строго из тега (без конфликтов)
8. Применяет патчи `docker-compose.yml` из конфига (volumes, логотип, DNS)
9. Регенерирует `uv.lock`
10. Собирает образ (`docker compose build --no-cache`)
11. Перезапускает сервисы и показывает логи

## ⚙️ Что делает update-cabinet.sh

1. Получает актуальные теги с GitHub
2. Показывает текущую и новую версию
3. Спрашивает подтверждение `y/N`
4. Сбрасывает локальные изменения и делает `git checkout` на новый тег
5. Собирает образ (`docker compose build --no-cache`)
6. Перезапускает сервисы и показывает логи

---

## 🔒 Особенности

- Скрипты **не трогают данные** — external volumes защищены
- `update-bot.conf` создаётся локально и не попадает в git
- Если версия уже актуальна — скрипт завершается без действий
