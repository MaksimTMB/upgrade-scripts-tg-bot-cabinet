#!/bin/bash
# update-bot.sh — обновление remnawave-bedolaga-telegram-bot
# Особенности /opt/remnawave-bot:
#   - всё owned by root → git/docker через sudo + safe.directory
#   - docker-compose.yml у нас локально пропатчен (external volumes,
#     freenet_logo, DNS) — патч идемпотентен, повторный запуск его не дублирует
set -e

BOT_DIR="/opt/remnawave-bot"
SAFE_DIR_OPT="-c safe.directory=$BOT_DIR"
GIT="sudo git $SAFE_DIR_OPT -C $BOT_DIR"
DC="sudo docker compose"

cd "$BOT_DIR"

# ── 0. Бэкап compose перед любыми операциями ─────────────────────────────────
BACKUP_DIR="/opt/backups/auto-$(date +%Y%m%d-%H%M%S)"
sudo mkdir -p "$BACKUP_DIR"
sudo cp docker-compose.yml "$BACKUP_DIR/bot-docker-compose.yml.before"
echo "Compose snapshot: $BACKUP_DIR/bot-docker-compose.yml.before"

# ── 1. Получаем теги ──────────────────────────────────────────────────────────
echo "=== Fetching tags ==="
$GIT fetch --tags
CURRENT=$($GIT describe --tags --exact-match 2>/dev/null || $GIT tag | sort -V | tail -1)
# Целевой тег: $1 (если задан) или последний доступный
if [ -n "$1" ]; then
  LATEST="$1"
  if ! $GIT tag | grep -qx "$LATEST"; then
    echo "ERROR: tag '$LATEST' not found. Available: $($GIT tag | sort -V | tail -5)"
    exit 1
  fi
else
  LATEST=$($GIT tag | sort -V | tail -1)
fi

echo "Current: $CURRENT"
echo "Latest:  $LATEST"

if [ "$CURRENT" = "$LATEST" ]; then
  echo "Already on latest version $LATEST, nothing to do."
  exit 0
fi

# ── 2. Проверяем миграции и compose ──────────────────────────────────────────
echo ""
echo "=== Changes from $CURRENT to $LATEST ==="
echo "--- Alembic migrations:"
$GIT diff "${CURRENT}..${LATEST}" --name-only | grep "alembic" || echo "  (none)"
echo "--- docker-compose.yml changes (upstream):"
$GIT diff "${CURRENT}..${LATEST}" -- docker-compose.yml | head -40 || echo "  (none)"

if [ -n "$AUTO_CONFIRM" ]; then
  echo "AUTO_CONFIRM set ($AUTO_CONFIRM) — continuing without prompt."
  CONFIRM="$AUTO_CONFIRM"
else
  read -p "Continue with update to $LATEST? [y/N] " CONFIRM
fi
[ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ] || { echo "Aborted."; exit 0; }

# ── 3. Сохраняем точку отката и переходим на новый тег ───────────────────────
echo ""
echo "=== Saving rollback point ==="
echo "$CURRENT" | sudo tee "$BACKUP_DIR/bot-rollback-tag.txt" >/dev/null

echo "=== Checking out $LATEST ==="
# locales/ — кастомные переводы, не в апстриме (whitelisted в .gitignore).
# Бэкапим перед сбросом, потом возвращаем на место.
if [ -d "$BOT_DIR/locales" ]; then
  sudo cp -a "$BOT_DIR/locales" "$BACKUP_DIR/locales"
  echo "  locales/ snapshot → $BACKUP_DIR/locales"
fi
# Скидываем локальные правки (compose, uv.lock и пр.) — потом перепатчим
$GIT reset --hard HEAD
$GIT clean -fd -e locales -e locales/
$GIT checkout "$LATEST"

# uv.lock берём строго из тега
$GIT checkout "$LATEST" -- uv.lock

# ── 4. Идемпотентный патч docker-compose.yml ─────────────────────────────────
echo ""
echo "=== Patching docker-compose.yml (idempotent) ==="
sudo python3 - <<'PYEOF'
import re
path = '/opt/remnawave-bot/docker-compose.yml'
content = open(path).read()
changed = False

# (1) External volumes ----------------------------------------------------
# Цель: блок `volumes:\n  postgres_data:\n    ...` →
#       postgres_data: external + name=remnawave-bedolaga-telegram-bot_postgres_data
#       redis_data: external + name=remnawave-bedolaga-telegram-bot_redis_data
def patch_external(name, c):
    pattern = re.compile(
        rf'(  {name}:\n)(    driver: local\n)',
    )
    if pattern.search(c) and f'name: remnawave-bedolaga-telegram-bot_{name}' not in c:
        c = pattern.sub(
            rf'\1    external: true\n    name: remnawave-bedolaga-telegram-bot_{name}\n',
            c, count=1)
        return c, True
    return c, False

for v in ('postgres_data', 'redis_data'):
    content, ch = patch_external(v, content)
    if ch:
        print(f'  [+] {v}: external=true')
        changed = True
    else:
        print(f'  [=] {v}: already external (or block not found)')

# (2) Logo ----------------------------------------------------------------
if './vpn_logo.png:/app/vpn_logo.png:ro' in content and './freenet_logo.jpg:/app/vpn_logo.png:ro' not in content:
    content = content.replace(
        './vpn_logo.png:/app/vpn_logo.png:ro',
        './freenet_logo.jpg:/app/vpn_logo.png:ro')
    print('  [+] logo: vpn_logo.png → freenet_logo.jpg')
    changed = True
else:
    print('  [=] logo: already freenet_logo.jpg (or no mount)')

# (3) DNS -----------------------------------------------------------------
# Старый патч встраивал dns: перед "ports:" сервиса bot. Делаем то же,
# но только если в файле НЕТ ни одного `    dns:`.
if re.search(r'^\s{4}dns:', content, re.MULTILINE) is None:
    # Находим блок сервиса bot и вставляем dns перед его ports:
    new_content, n = re.subn(
        r"(\n    ports:\n      - ['\"]?\$\{WEB_API_PORT:-8080\}:8080)",
        r"\n    dns:\n      - 8.8.8.8\n      - 1.1.1.1\1",
        content, count=1)
    if n == 1:
        content = new_content
        print('  [+] dns: added 8.8.8.8/1.1.1.1 to bot service')
        changed = True
    else:
        print('  [!] dns: anchor "ports: ${WEB_API_PORT}:8080" not found — skipped')
else:
    print('  [=] dns: already present')

if changed:
    open(path, 'w').write(content)
    print('docker-compose.yml UPDATED')
else:
    print('docker-compose.yml unchanged')
PYEOF

# ── 5. Sanity-проверка патча ──────────────────────────────────────────────────
echo ""
echo "--- Verification:"
sudo grep -E "external: true|freenet_logo|dns:" "$BOT_DIR/docker-compose.yml" \
  || { echo "ERROR: patch verification failed!"; exit 1; }

# ── 6. Регенерируем uv.lock ───────────────────────────────────────────────────
echo ""
echo "=== Regenerating uv.lock ==="
sudo docker run --rm -v "$BOT_DIR:/app" -w /app python:3.13-slim sh -c "pip install uv -q && uv lock"

# ── 6b. Чистим docker-мусор перед сборкой ────────────────────────────────────
# Главная историческая причина "апдейт сломался" (16 мая 2026) — диск / забит
# на 100% build-кэшем от --no-cache ребилдов (10+ GB) → postgres падал с
# 'No space left on device', стек оставался полу-обновлённым. Чистим ТОЛЬКО
# reclaimable: build cache + dangling-слои. Запущенные контейнеры, тома и
# тегированные образы не трогаем.
echo ""
echo "=== Freeing disk: docker build cache + dangling images ==="
df -h / | tail -1
sudo docker builder prune -af || true
sudo docker image prune -f || true
echo "After prune:"
df -h / | tail -1
AVAIL_KB=$(df --output=avail / | tail -1 | tr -d ' ')
if [ -n "$AVAIL_KB" ] && [ "$AVAIL_KB" -lt 3145728 ]; then
  echo "ERROR: < 3 GB свободно на / после чистки ($((AVAIL_KB/1024)) MB)."
  echo "Сборка прервана до того, как --no-cache добьёт диск (postgres упал бы с"
  echo "'No space left'). Освободи место (docker system df) и повтори."
  exit 1
fi

# ── 7. Собираем образ ─────────────────────────────────────────────────────────
echo ""
echo "=== Building image ==="
$DC build --no-cache

# ── 8. Перезапускаем ─────────────────────────────────────────────────────────
echo ""
echo "=== Restarting services ==="
$DC down
$DC up -d

echo ""
echo "=== Done! Bot updated $CURRENT → $LATEST ==="
echo "Rollback point: $BACKUP_DIR"
echo ""
echo "=== Tailing logs for 20s (Ctrl+C to exit early) ==="
timeout 20 $DC logs -f bot || true
echo ""
echo "=== Final health: ==="
$DC ps
