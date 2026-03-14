#!/bin/bash
set -e

CAB_DIR="/opt/bedolaga-cabinet"
cd "$CAB_DIR"

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

# ── 2. Проверяем compose ──────────────────────────────────────────────────────
echo ""
echo "=== Changes from $CURRENT to $LATEST ==="
echo "--- docker-compose.yml changes:"
git diff "${CURRENT}..${LATEST}" -- docker-compose.yml | head -40 || echo "  (none)"

read -p "Continue with update to $LATEST? [y/N] " CONFIRM
[ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ] || { echo "Aborted."; exit 0; }

# ── 3. Переходим на новый тег ─────────────────────────────────────────────────
echo ""
echo "=== Checking out $LATEST ==="
# Сбрасываем локальные изменения (наши патчи package.json/i18n.ts больше не нужны)
git stash drop 2>/dev/null || true
git checkout -- . 2>/dev/null || true
git checkout "$LATEST"

# ── 4. Собираем образ ─────────────────────────────────────────────────────────
echo ""
echo "=== Building image ==="
docker compose build --no-cache

# ── 5. Перезапускаем ─────────────────────────────────────────────────────────
echo ""
echo "=== Restarting services ==="
docker compose down
docker compose up -d

echo ""
echo "=== Done! Cabinet updated to $LATEST ==="
echo "=== Logs (Ctrl+C to exit): ==="
docker compose logs -f
