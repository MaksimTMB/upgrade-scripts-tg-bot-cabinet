#!/bin/bash
set -e

BOT_DIR="/opt/remnawave-bot"
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

# uv.lock берём строго из тега — никаких конфликтов
git checkout "$LATEST" -- uv.lock

# ── 4. Фиксим docker-compose.yml ─────────────────────────────────────────────
echo ""
echo "=== Patching docker-compose.yml ==="
python3 -c "
content = open('docker-compose.yml').read()

# External volumes
content = content.replace(
    'volumes:\n  postgres_data:\n    driver: local\n  redis_data:\n    driver: local',
    'volumes:\n  postgres_data:\n    external: true\n    name: remnawave-bedolaga-telegram-bot_postgres_data\n  redis_data:\n    external: true\n    name: remnawave-bedolaga-telegram-bot_redis_data'
)

# Логотип
content = content.replace(
    '      - ./vpn_logo.png:/app/vpn_logo.png:ro',
    '      - ./freenet_logo.jpg:/app/vpn_logo.png:ro'
)

# DNS (добавляем только если ещё нет)
if '    dns:' not in content:
    content = content.replace(
        \"    ports:\n      - '\${WEB_API_PORT:-8080}:8080'\n    networks:\",
        \"    dns:\n      - 8.8.8.8\n      - 1.1.1.1\n    ports:\n      - '\${WEB_API_PORT:-8080}:8080'\n    networks:\"
    )

open('docker-compose.yml', 'w').write(content)
print('docker-compose.yml patched OK')
"

# ── 5. Проверяем патч ─────────────────────────────────────────────────────────
echo "--- Verification:"
grep -E "external: true|freenet_logo|dns:" docker-compose.yml || echo "WARNING: patch may have failed!"

# ── 6. Регенерируем uv.lock ───────────────────────────────────────────────────
echo ""
echo "=== Regenerating uv.lock ==="
docker run --rm -v "$(pwd):/app" -w /app python:3.13-slim sh -c "pip install uv -q && uv lock"

# ── 7. Собираем образ ─────────────────────────────────────────────────────────
echo ""
echo "=== Building image ==="
docker compose build --no-cache

# ── 8. Перезапускаем ─────────────────────────────────────────────────────────
echo ""
echo "=== Restarting services ==="
docker compose down
docker compose up -d

echo ""
echo "=== Done! Bot updated to $LATEST ==="
echo "=== Logs (Ctrl+C to exit): ==="
docker compose logs -f bot
