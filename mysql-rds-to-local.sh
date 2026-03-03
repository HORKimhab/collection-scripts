#!/bin/bash
set -euo pipefail

# =====================================================
# Purpose:
# Securely backup multiple AWS staging MySQL databases
# and restore them to local MySQL.
# - GTID-safe
# - Encrypted credentials (mysql_config_editor)
# - Progress via pv
# - Per-DB backup & restore
# =====================================================

# -----------------------------------------------------
# Load environment variables
# -----------------------------------------------------
set -a
source .env
set +a

# -----------------------------------------------------
# Global Config
# -----------------------------------------------------
STAGING_HOST="${STAGING_HOST:-your-host-mysql-db}"
STAGING_USER="${STAGING_USER_MYSQL:-input_staging_user_mysql}"

BACKUP_DIR="$HOME/staging_backups"
DATE=$(date +%F_%H-%M-%S)
LOGIN_PATH_STAGING="staging"
LOGIN_PATH_LOCAL="${LOGIN_PATH_LOCAL:-local}${DATE}"

# Local MySQL
LOCAL_USER="${LOCAL_USER_MYSQL:-root}"
MYSQL_HOST_LOCAL="${MYSQL_HOST_LOCAL:-localhost}"

# -----------------------------------------------------
# Databases to sync (STAGING → LOCAL)
# Format: "staging_db:local_db"
# -----------------------------------------------------

# -----------------------------------------------------
# Utilities
# -----------------------------------------------------
require_command() {
  command -v "$1" &>/dev/null || {
    echo "❌ Required command '$1' not found"
    exit 1
  }
}

ensure_login_path() {
  local LOGIN_PATH="$1"
  local HOST="$2"
  local USER="$3"

  while true; do
    if mysql --login-path="$LOGIN_PATH" -e "SELECT 1;" &>/dev/null; then
      echo "✅ Login-path '$LOGIN_PATH' is valid."
      break
    fi

    echo "❌ Login-path '$LOGIN_PATH' invalid or missing."
    echo "🔒 Please enter password for '$USER'."

    mysql_config_editor remove --login-path="$LOGIN_PATH" &>/dev/null || true
    mysql_config_editor set \
      --login-path="$LOGIN_PATH" \
      --host="$HOST" \
      --user="$USER" \
      --password

    echo "💡 Login-path '$LOGIN_PATH' updated. Retesting..."
    sleep 1
  done
}

# -----------------------------------------------------
# Preconditions
# -----------------------------------------------------
require_command pv
require_command mysql
require_command mysqldump
require_command gzip

mkdir -p "$BACKUP_DIR"

ensure_login_path "$LOGIN_PATH_STAGING" "$STAGING_HOST" "$STAGING_USER"
ensure_login_path "$LOGIN_PATH_LOCAL" "$MYSQL_HOST_LOCAL" "$LOCAL_USER"

# -----------------------------------------------------
# Backup & Restore Loop
# -----------------------------------------------------

# Example
# DATABASES=(
#   "db1:db1_local"
#   "db2:db2_local"
# )

# Convert env → array (single operation, no fork)
read -ra DATABASES <<< "$DATABASE_PAIRS"

KEEP_LAST=$(( ${#DATABASES[@]} / 2 ))
(( KEEP_LAST < 1 )) && KEEP_LAST=1

for DB_PAIR in "${DATABASES[@]}"; do
  [[ $DB_PAIR == *:* ]] || {
    echo "❌ Invalid DB pair: $DB_PAIR"
    exit 1
  }

  # IFS=":" read -r STAGING_DB LOCAL_DB <<< "$DB_PAIR"
  STAGING_DB=${DB_PAIR%%:*}
  LOCAL_DB=${DB_PAIR##*:}


  BACKUP_FILE="$BACKUP_DIR/${STAGING_DB}_${DATE}.sql.gz"

  echo ""
  echo "==================================================="
  echo "📦 Processing DB: $STAGING_DB → $LOCAL_DB"
  echo "==================================================="

  # -----------------------------
  # Backup
  # -----------------------------
  echo "📤 Backing up '$STAGING_DB'..."

  mysqldump --login-path="$LOGIN_PATH_STAGING" \
    --single-transaction \
    --routines \
    --triggers \
    --events \
    --set-gtid-purged=OFF \
    "$STAGING_DB" | pv | gzip > "$BACKUP_FILE"

  echo "✅ Backup saved: $BACKUP_FILE"

  # -----------------------------
  # Confirm destructive restore
  # -----------------------------
  read -p "⚠️ ERASE local DB '$LOCAL_DB' and restore? (y/N): " confirm
  [[ "$confirm" == "y" ]] || {
    echo "⏭ Skipping restore for '$LOCAL_DB'"
    continue
  }

  # -----------------------------
  # Drop & recreate local DB
  # -----------------------------
  echo "💥 Recreating local DB '$LOCAL_DB'..."

  mysql --login-path="$LOGIN_PATH_LOCAL" <<SQL
DROP DATABASE IF EXISTS \`$LOCAL_DB\`;
CREATE DATABASE \`$LOCAL_DB\`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
SQL

  # -----------------------------
  # Fast restore session
  # -----------------------------
  mysql --login-path="$LOGIN_PATH_LOCAL" "$LOCAL_DB" <<SQL
SET autocommit=0;
SET unique_checks=0;
SET foreign_key_checks=0;
SET sql_log_bin=0;
SQL

  # -----------------------------
  # Restore
  # -----------------------------
  echo "📥 Restoring '$LOCAL_DB'..."

  gunzip -c "$BACKUP_FILE" | pv | mysql --login-path="$LOGIN_PATH_LOCAL" "$LOCAL_DB"

  # -----------------------------
  # Restore defaults
  # -----------------------------
  mysql --login-path="$LOGIN_PATH_LOCAL" "$LOCAL_DB" <<SQL
COMMIT;
SET autocommit=1;
SET unique_checks=1;
SET foreign_key_checks=1;
SET sql_log_bin=1;
SQL

  echo "🎉 Restore completed for '$LOCAL_DB'"
done

# -----------------------------------------------------
# Cleanup old backups
# -----------------------------------------------------
echo "🧹 Cleaning up old backups (keeping last $KEEP_LAST)..."

cd "$BACKUP_DIR" || exit 1

mapfile -t backups < <(ls -1t *.sql.gz 2>/dev/null || true)

if (( ${#backups[@]} > KEEP_LAST )); then
    printf '%s\n' "${backups[@]:KEEP_LAST}" | xargs -r rm -f
    echo "✅ Old backups cleaned up."
else
    echo "ℹ️ No old backups to remove."
fi

