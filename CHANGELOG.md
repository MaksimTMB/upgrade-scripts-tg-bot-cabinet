# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.2.0] — 2026-06-04

### Added

- **`update-bot.sh`: авто-`pg_dump` БД ДО применения миграций (шаг 3a).** После
  подтверждения апдейта, пока старый стек ещё поднят и БД на старой схеме, скрипт
  снимает `pg_dump --clean --if-exists` из контейнера `remnawave_bot_db`, сжимает в
  `/opt/backups/auto-<TS>/bot-db-remnawave_bot.sql.gz` и проверяет, что дамп не
  пустой (>1 KB). Если postgres не запущен или `pg_dump` упал — апдейт **прерывается
  ДО** checkout/build/up, чтобы миграции не применились без точки отката.
  - Мотивация: бот `v3.59.0` принёс фоновый startup-сервис дедупа тарифных
    подписок (`subscription_dedup_service`), удаляющий строки из БД, — класс
    изменений, который compose-снапшот не покрывает. На текущем проде он сработал
    вхолостую (0 дублей), но впредь любой такой апдейт получает дамп для отката в
    одну команду:
    `gunzip -c <dump> | sudo docker exec -i remnawave_bot_db psql -U remnawave_user -d remnawave_bot`.
  - Путь дампа печатается в финальной сводке рядом с `Rollback point`.

### Notes

- Дамп берётся после интерактивного `y/N` (или `AUTO_CONFIRM`), поэтому отказ от
  апдейта не плодит лишних дампов. Свежая установка без запущенного
  `remnawave_bot_db` не падает — снапшот пропускается с предупреждением.
- `update-cabinet.sh` не трогали: у кабинета нет БД/миграций.

## [2.1.0] — 2026-06-01

Закрывает два рецидива, из-за которых апдейт «не работал», — теперь команды
`sudo update-bot` / `sudo update-cabinet` самодостаточны и не требуют ручных
действий до/после.

### Fixed

- **`update-cabinet.sh`: кастомный `listen [::]:80;` в `nginx.conf` больше не
  теряется.** Раньше `git reset --hard` / `checkout` затирали IPv6-listen на
  каждом апдейте → `cabinet_frontend` уходил в `(unhealthy)` (busybox-wget
  healthcheck бьётся в `::1`). Теперь скрипт бэкапит `nginx.conf` (шаг 0) и
  идемпотентно ре-инжектит строку после checkout, до сборки образа
  (шаг 3b, `sed` с сохранением отступа, guard по `grep`).

### Added

- **Авто-чистка диска перед `--no-cache` сборкой в обоих скриптах** (шаг 6b
  бота / 3c кабинета). Главная историческая причина падений 16 мая 2026 —
  диск `/` забит build-кэшем (10+ GB) → postgres `No space left on device`,
  стек полу-обновлён. Теперь перед сборкой: `docker builder prune -af` +
  `docker image prune -f` (только reclaimable: build cache + dangling-слои;
  запущенные контейнеры, тома и тегированные образы не трогаются). Если после
  чистки на `/` < 3 GB — скрипт аккуратно прерывается ДО сборки с понятным
  сообщением, а не роняет стек на полпути.

### Notes

- Деплой на 192.168.1.63: единственная точка запуска — симлинки
  `/usr/local/bin/update-bot` и `update-cabinet` → этот каталог. Устаревшая
  per-repo копия `/opt/remnawave-bot/update-bot.sh` удалена (2026-06-01).
- Идеальное решение для nginx.conf — мёрж PR `fix/nginx-ipv6-healthcheck` в
  `BEDOLAGA-DEV/bedolaga-cabinet`; до тех пор self-heal в скрипте делает его
  необязательным.

## [2.0.0] — 2026-05-16

Первый версионированный релиз. Скрипты переписаны так, чтобы пережили
реальные сценарии деплоя на 192.168.1.63, где `/opt/remnawave-bot` и
`/opt/bedolaga-cabinet` принадлежат `root`.

### ⚠ BREAKING CHANGES

- Скрипты теперь нужно запускать под **sudo** (или из-под root). Старый
  вызов `./update-bot.sh` без `sudo` падает на `git`/`docker` с
  `detected dubious ownership` и `permission denied on docker.sock`.
  Если у тебя был старый workflow — поправь cron/runbook на `sudo ./...`.
- Целевой тег теперь передаётся первым позиционным аргументом
  (`./update-bot.sh v3.55.0`). Если ранее в обвязке использовался
  какой-то нестандартный позиционный аргумент — он будет считаться тегом.
- Удалён интерактивный first-run wizard и файл `update-bot.conf`
  (фактически не использовался в реальной установке на проде).

### Added

- `update-bot.sh $1` / `update-cabinet.sh $1` — целевой тег. Полезно для
  пошагового апдейта (`v3.54 → v3.55 → v3.56`) и для отката (`v3.55.0`).
- `AUTO_CONFIRM=y` — пропуск интерактивного `y/N` для случаев, когда TTY
  не пробрасывается (несколько SSH-хопов, cron).
- Снапшот `docker-compose.yml` в `/opt/backups/auto-<TS>/` перед каждым
  запуском. Файл `<...>-rollback-tag.txt` хранит исходный тег для отката.
- Бэкап `locales/` (кастомные переводы вне апстрима) перед `git clean`.
- `.github/workflows/release.yml` — auto-release на пуш тега `v*` через
  `softprops/action-gh-release`. CI прогоняет shellcheck.

### Changed

- **Идемпотентный** compose-патч в `update-bot.sh`:
  - `postgres_data` / `redis_data` → `external: true, name: remnawave-bedolaga-telegram-bot_*`
  - `vpn_logo.png` → `freenet_logo.jpg`
  - `dns: 8.8.8.8 / 1.1.1.1` в сервис `bot`
  Повторный запуск ничего не дублирует — проверено байт-в-байт против
  prod-compose'а v3.56.0 и pristine upstream'а.
- Все `git`/`docker compose` вызовы — через `sudo` с
  `-c safe.directory=...`. Без этого они валились с
  `fatal: detected dubious ownership in repository at '/opt/remnawave-bot'`
  и `permission denied while trying to connect to the docker API`.
- `git clean -fd -e locales -e locales/` — не сметает кастомные переводы.
- `git checkout` теперь предваряется `git reset --hard HEAD` + `git clean
  -fd` (вместо `git stash` без TTY).
- Логи после `up -d` ограничены `timeout 20s` (bot) / `15s` (cabinet),
  чтобы скрипт не висел в `logs -f` бесконечно.
- README полностью переписан: предполётный чек-лист с `df -h /`, секции
  про sudo / AUTO_CONFIRM / tag-аргумент / бэкап БД / откат.

### Removed

- `files/` и `files.zip` — артефакты предыдущих экспериментов,
  больше не нужны.
- Интерактивный first-run wizard, файл `update-bot.conf`.

### Fixed

- **Главная причина падения "ошибки апдейта"** на проде 16 мая 2026
  оказалась не в скрипте, а в окружении (диск `/` забит на 100%
  docker-build-кэшем) — но скрипт усилен предполётным чек-листом в
  README, чтобы это ловилось раньше.

### Notes

Протестировано на 192.168.1.63 (16 мая 2026):
бот `v3.54.0 → v3.55.0 → v3.56.0`, кабинет `v1.51.0 → v1.53.0`.
Все контейнеры пришли в `healthy`.
