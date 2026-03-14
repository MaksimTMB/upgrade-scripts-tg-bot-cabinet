#!/bin/bash
set -e

BOT_DIR="/opt/remnawave-bot"
CONFIG_FILE="$BOT_DIR/update-bot.conf"

# ── Первый запуск: создаём конфиг интерактивно ───────────────────────────────
if [ ! -f "$CONFIG_FILE" ]; then
  echo "=== Первый запуск — настройка ==="
  echo ""

  read -p "Имя Docker volume для PostgreSQL [remnawave-bedolaga-telegram-bot_postgres_data]: " PG
  PG="${PG:-remnawave-bedolaga-telegram-bot_postgres_data}"

  read -p "Имя Docker volume для Redis [remnawave-bedolaga-telegram-bot_redis_data]: " RD
  RD="${RD:-remnawave-bedolaga-telegram-bot_redis_data}"

  read -p "Путь к логотипу (оставь пустым если не нужно) []: " LOGO
  read -p "DNS серверы через пробел (оставь пустым если не нужно) [8.8.8.8 1.1.1.1]: " DNS
  DNS="${DNS:-8.8.8.8 1.1.1.1}"

  cat > "$CONFIG_FILE" << EOF
POSTGRES_VOLUME_NAME="$PG"
REDIS_VOLUME_NAME="$RD"
LOGO_FILE="$LOGO"
DNS_SERVERS="$DNS"
EOF

  echo ""
  echo "Конфиг сохранён в $CONFIG_FILE"
  echo ""
fi

# ── Загружаем конфиг ─────────────────────────────────────────────────────────
source "$CONFIG_FILE"

cd "$BOT_DIR"

# ── 1. Получаем теги ──────────────────────────────────────────────────────────
echo "=== Fetching tags ==="
git fetch --tags
CURRENT=$(git describe --tags --exact-match 2>/dev/null || git tag | sort -V | tail -1)
LATEST=$(git tag | sort -V | tail -1)

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
git diff "${CURRENT}..${LATEST}" --name-only | grep "alembic" || echo "  (none)"
echo "--- docker-compose.yml changes:"
git diff "${CURRENT}..${LATEST}" -- docker-compose.yml | head -40 || echo "  (none)"

read -p "Continue with update to $LATEST? [y/N] " CONFIRM
[ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ] || { echo "Aborted."; exit 0; }

# ── 3. Переходим на новый тег ─────────────────────────────────────────────────
echo ""
echo "=== Checking out $LATEST ==="
git stash || true
git checkout "$LATEST"
git checkout "$LATEST" -- uv.lock

# ── 4. Патчим docker-compose.yml ─────────────────────────────────────────────
echo ""
echo "=== Patching docker-compose.yml ==="
export POSTGRES_VOLUME_NAME REDIS_VOLUME_NAME LOGO_FILE DNS_SERVERS
python3 << 'PYEOF'
import os

content = open('docker-compose.yml').read()

pg = os.environ.get('POSTGRES_VOLUME_NAME', '')
rd = os.environ.get('REDIS_VOLUME_NAME', '')
if pg and rd:
    old = 'volumes:\n  postgres_data:\n    driver: local\n  redis_data:\n    driver: local'
    new = f'volumes:\n  postgres_data:\n    external: true\n    name: {pg}\n  redis_data:\n    external: true\n    name: {rd}'
    if old in content:
        content = content.replace(old, new)
        print(f'  OK External volumes: {pg}, {rd}')

logo = os.environ.get('LOGO_FILE', '')
if logo:
    old_logo = '      - ./vpn_logo.png:/app/vpn_logo.png:ro'
    new_logo = f'      - {logo}:/app/vpn_logo.png:ro'
    if old_logo in content:
        content = content.replace(old_logo, new_logo)
        print(f'  OK Logo: {logo}')

dns = os.environ.get('DNS_SERVERS', '')
if dns and '    dns:' not in content:
    dns_lines = '\n'.join([f'      - {d}' for d in dns.split()])
    content = content.replace(
        "    ports:\n      - '${WEB_API_PORT:-8080}:8080'\n    networks:",
        f"    dns:\n{dns_lines}\n    ports:\n      - '${{WEB_API_PORT:-8080}}:8080'\n    networks:"
    )
    print(f'  OK DNS: {dns}')

open('docker-compose.yml', 'w').write(content)
print('docker-compose.yml OK')
PYEOF

# ── 5. Регенерируем uv.lock ───────────────────────────────────────────────────
echo ""
echo "=== Regenerating uv.lock ==="
docker run --rm -v "$(pwd):/app" -w /app python:3.13-slim sh -c "pip install uv -q && uv lock"

# ── 6. Собираем образ ─────────────────────────────────────────────────────────
echo ""
echo "=== Building image ==="
docker compose build --no-cache

# ── 7. Перезапускаем ─────────────────────────────────────────────────────────
echo ""
echo "=== Restarting services ==="
docker compose down
docker compose up -d

echo ""
echo "=== Done! Bot updated to $LATEST ==="
echo "=== Logs (Ctrl+C to exit): ==="
docker compose logs -f bot
