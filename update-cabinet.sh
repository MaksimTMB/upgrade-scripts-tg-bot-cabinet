#!/bin/bash
# update-cabinet.sh — обновление bedolaga-cabinet (фронт)
# Особенности /opt/bedolaga-cabinet:
#   - всё owned by root → git/docker через sudo + safe.directory
#   - локальных патчей compose нет, миграций нет
#   - ЕСТЬ локальный патч nginx.conf: 'listen [::]:80;' (IPv6 healthcheck-фикс).
#     git reset --hard / checkout его затирают, поэтому ниже nginx.conf
#     бэкапится (шаг 0) и идемпотентно восстанавливается после checkout
#     (шаг 3b), до сборки образа. Постоянное решение — мёрж upstream-PR
#     fix/nginx-ipv6-healthcheck в BEDOLAGA-DEV/bedolaga-cabinet.
set -e

CAB_DIR="/opt/bedolaga-cabinet"
SAFE_DIR_OPT="-c safe.directory=$CAB_DIR"
GIT="sudo git $SAFE_DIR_OPT -C $CAB_DIR"
DC="sudo docker compose"

cd "$CAB_DIR"

# ── 0. Бэкап compose + nginx.conf ────────────────────────────────────────────
BACKUP_DIR="/opt/backups/auto-$(date +%Y%m%d-%H%M%S)"
sudo mkdir -p "$BACKUP_DIR"
sudo cp docker-compose.yml "$BACKUP_DIR/cabinet-docker-compose.yml.before"
sudo cp nginx.conf "$BACKUP_DIR/cabinet-nginx.conf.before" 2>/dev/null || true
echo "Compose snapshot: $BACKUP_DIR/cabinet-docker-compose.yml.before"

# ── 1. Теги ───────────────────────────────────────────────────────────────────
echo "=== Fetching tags ==="
$GIT fetch --tags
CURRENT=$($GIT describe --tags --exact-match 2>/dev/null || $GIT tag | sort -V | tail -1)
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

# ── 2. Diff ───────────────────────────────────────────────────────────────────
echo ""
echo "=== Changes from $CURRENT to $LATEST ==="
echo "--- docker-compose.yml changes (upstream):"
$GIT diff "${CURRENT}..${LATEST}" -- docker-compose.yml | head -40 || echo "  (none)"

if [ -n "$AUTO_CONFIRM" ]; then
  echo "AUTO_CONFIRM set ($AUTO_CONFIRM) — continuing without prompt."
  CONFIRM="$AUTO_CONFIRM"
else
  read -p "Continue with update to $LATEST? [y/N] " CONFIRM
fi
[ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ] || { echo "Aborted."; exit 0; }

# ── 3. Точка отката + checkout ───────────────────────────────────────────────
echo ""
echo "=== Saving rollback point ==="
echo "$CURRENT" | sudo tee "$BACKUP_DIR/cabinet-rollback-tag.txt" >/dev/null

echo "=== Checking out $LATEST ==="
$GIT reset --hard HEAD
$GIT clean -fd
$GIT checkout "$LATEST"

# ── 3b. Восстановить кастомный IPv6-listen в nginx.conf ──────────────────────
# checkout вернул nginx.conf к upstream (только 'listen 80;'). Без 'listen
# [::]:80;' busybox-wget healthcheck бьётся в ::1 → cabinet_frontend
# (unhealthy). Возвращаем строку идемпотентно, сохраняя исходный отступ.
if grep -qE '^[[:space:]]*listen 80;' nginx.conf && ! grep -q 'listen \[::\]:80;' nginx.conf; then
  echo "=== Re-applying 'listen [::]:80;' to nginx.conf (IPv6 healthcheck fix) ==="
  sudo sed -i 's/\(^[[:space:]]*\)listen 80;/\1listen 80;\n\1listen [::]:80;/' nginx.conf
  grep -n 'listen' nginx.conf
else
  echo "nginx.conf: IPv6 listen уже есть или нет якоря 'listen 80;' — пропускаю."
fi

# ── 3c. Чистим docker-мусор перед сборкой ────────────────────────────────────
# Главная историческая причина "апдейт сломался" (16 мая 2026) — диск / забит
# на 100% build-кэшем от --no-cache ребилдов → контейнеры падали с
# 'No space left on device'. Чистим ТОЛЬКО reclaimable: build cache +
# dangling-слои. Запущенные контейнеры, тома и тегированные образы не трогаем.
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
  echo "Сборка прервана до того, как --no-cache добьёт диск. Освободи место и повтори."
  exit 1
fi

# ── 4. Сборка ─────────────────────────────────────────────────────────────────
echo ""
echo "=== Building image ==="
$DC build --no-cache

# ── 5. Перезапуск ─────────────────────────────────────────────────────────────
echo ""
echo "=== Restarting services ==="
$DC down
$DC up -d

echo ""
echo "=== Done! Cabinet updated $CURRENT → $LATEST ==="
echo "Rollback point: $BACKUP_DIR"
echo ""
echo "=== Tailing logs for 15s (Ctrl+C to exit early) ==="
timeout 15 $DC logs -f || true
echo ""
echo "=== Final state: ==="
$DC ps
