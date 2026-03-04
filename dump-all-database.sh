#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------
# Load environment variables
# -----------------------------------------------------
set -a
source .env
set +a

HOST="${1:-${DUMP_DB_HOST:-}}"
PORT="${2:-${DUMP_DB_PORT:-3306}}"
USER="${3:-${DUMP_DB_USER:-user_mysql_root}}"

# -----------------------------------------------------
# Prompt for missing values
# -----------------------------------------------------
if [ -z "${HOST:-}" ]; then
  read -rp "Enter MySQL host: " HOST
fi

if [ -z "${PORT:-}" ]; then
  read -rp "Enter MySQL port [3306]: " PORT
  PORT="${PORT:-3306}"
fi

if [ -z "${USER:-}" ]; then
  read -rp "Enter MySQL user: " USER
fi

# -----------------------------------------------------
# Prompt for password (hidden)
# -----------------------------------------------------
read -rsp "Enter MySQL password: " MYSQL_PASSWORD
echo

# -----------------------------------------------------
# Ensure temp files are private
# -----------------------------------------------------
umask 077
TMP_CNF=$(mktemp)
cat > "$TMP_CNF" <<EOF
[client]
user=$USER
password=$MYSQL_PASSWORD
host=$HOST
port=$PORT
EOF

# Ensure cleanup on exit or Ctrl+C
cleanup() {
    rm -f "$TMP_CNF"
}
trap cleanup EXIT

# -----------------------------------------------------
# Output file
# -----------------------------------------------------
OUT="/tmp/mysql-backup-$(date +%F-%H%M%S).sql"

# -----------------------------------------------------
# Run mysqldump with optional pv and optional gzip
# -----------------------------------------------------
DUMP_CMD=(mysqldump --defaults-extra-file="$TMP_CNF" \
  --all-databases \
  --routines --events --triggers \
  --single-transaction \
  --set-gtid-purged=OFF)

if command -v pv >/dev/null 2>&1; then
  echo "Using pv for progress..."
  "${DUMP_CMD[@]}" | pv | gzip > "${OUT}.gz"
  echo "Backup saved to ${OUT}.gz"
else
  echo "pv not found, running without progress..."
  "${DUMP_CMD[@]}" | gzip > "${OUT}.gz"
  echo "Backup saved to ${OUT}.gz"
fi