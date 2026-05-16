# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
