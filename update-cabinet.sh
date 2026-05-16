#!/bin/bash
# update-cabinet.sh — обновление bedolaga-cabinet (фронт)
# Особенности /opt/bedolaga-cabinet:
#   - всё owned by root → git/docker через sudo + safe.directory
#   - локальных патчей compose у нас нет (миграции тоже нет)
set -e

CAB_DIR="/opt/bedolaga-cabinet"
SAFE_DIR_OPT="-c safe.directory=$CAB_DIR"
GIT="sudo git $SAFE_DIR_OPT -C $CAB_DIR"
DC="sudo docker compose"

cd "$CAB_DIR"

# ── 0. Бэкап compose ─────────────────────────────────────────────────────────
BACKUP_DIR="/opt/backups/auto-$(date +%Y%m%d-%H%M%S)"
sudo mkdir -p "$BACKUP_DIR"
sudo cp docker-compose.yml "$BACKUP_DIR/cabinet-docker-compose.yml.before"
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
