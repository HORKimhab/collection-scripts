#!/bin/bash

set -a
source .env
set +a

# Purpose: Securely backup AWS staging MySQL and restore to local MySQL
# Fully automated, GTID-safe, encrypted password storage
# Progress shown via pv
# Local DB is replaced with staging DB

# Load environment variables
# export $(grep -v '^#' .env | xargs)

🧪 Debug-friendly version
# set -o allexport
# source .env
# set +o allexport

# --- Config ---
STAGING_HOST="${STAGING_HOST:-your-host-mysql-db}"
STAGING_USER="ctdb1"
STAGING_DB="ebdb_staging"
BACKUP_DIR="$HOME/staging_backups"
DATE=$(date +%F_%H-%M-%S)
BACKUP_FILE="$BACKUP_DIR/staging_backup_$DATE.sql.gz"
LOGIN_PATH="staging"
KEEP_LAST=5   # Keep last 5 backups

# Local MySQL settings
LOCAL_DB="camboticket_local"
LOCAL_USER="root"
LOCAL_LOGIN_PATH="local"   # Optional login path for local MySQL

# --- Step 0: Ensure pv is installed ---
if ! command -v pv &>/dev/null; then
    echo "❌ pv command not found. Please install pv (brew install pv / apt install pv)"
    exit 1
fi

while true; do
    if mysql --login-path="$LOGIN_PATH" -e "SELECT 1;" &>/dev/null; then
        echo "✅ Login-path staging '$LOGIN_PATH' is valid."
        break
    fi

    echo "❌ Login-path staging '$LOGIN_PATH' invalid or missing."
    echo "🔒 Please enter local MySQL password."

    mysql_config_editor remove --login-path="$LOGIN_PATH" &>/dev/null || true

    mysql_config_editor set \
        --login-path="$LOGIN_PATH" \
        --host=$STAGING_HOST \
        --user=$STAGING_USER \
        --password
    echo "💡 Login-path staging updated. Retesting..."
    sleep 1
done

# --- Step 1: Setup encrypted login for staging if not exists ---
if ! mysql_config_editor print --login-path=$LOGIN_PATH &>/dev/null; then
    echo "🔒 Setting up secure login for staging DB ($STAGING_DB)..."
    mysql_config_editor set --login-path=$LOGIN_PATH \
        --host=$STAGING_HOST \
        --user=$STAGING_USER \
        --password
    echo "✅ Secure login-path '$LOGIN_PATH' configured."
else
    echo "🔑 Login-path '$LOGIN_PATH' already exists, using stored credentials."
fi

# --- Step 2: Create backup directory if missing ---
mkdir -p "$BACKUP_DIR"

# --- Step 3: Backup staging DB securely with progress ---
echo "📦 Backing up staging DB ($STAGING_DB) to $BACKUP_FILE ..."
if mysqldump --login-path=$LOGIN_PATH \
             --single-transaction \
             --routines \
             --triggers \
             --events \
             --set-gtid-purged=OFF \
             "$STAGING_DB" | pv | gzip > "$BACKUP_FILE"; then
    echo "✅ Backup completed successfully!"
    echo "📁 Backup file: $BACKUP_FILE"
else
    echo "❌ Backup failed!"
    exit 1
fi

# =====================================================
# Step 4: FAST & SAFE restore backup to local MySQL
# =====================================================

echo "🔄 Restoring backup to local DB ($LOCAL_DB)"

# -----------------------------------------------------
# 1. Ensure valid local login-path
# -----------------------------------------------------
while true; do
    if mysql --login-path="$LOCAL_LOGIN_PATH" -e "SELECT 1;" &>/dev/null; then
        echo "✅ Login-path '$LOCAL_LOGIN_PATH' is valid."
        break
    fi

    echo "❌ Login-path '$LOCAL_LOGIN_PATH' invalid or missing."
    echo "🔒 Please enter local MySQL password."

    mysql_config_editor remove --login-path="$LOCAL_LOGIN_PATH" &>/dev/null || true

    mysql_config_editor set \
        --login-path="$LOCAL_LOGIN_PATH" \
        --user="$LOCAL_USER" \
        --password

    echo "💡 Login-path updated. Retesting..."
    sleep 1
done

# -----------------------------------------------------
# 2. Safety confirmation (destructive)
# -----------------------------------------------------
read -p "⚠️ This will ERASE local DB '$LOCAL_DB'. Continue? (y/N): " confirm
[[ "$confirm" == "y" ]] || { echo "❌ Restore cancelled."; exit 1; }

# -----------------------------------------------------
# 3. Drop & recreate local DB (idempotent)
# -----------------------------------------------------
echo "💥 Dropping & recreating local DB '$LOCAL_DB'..."

mysql --login-path="$LOCAL_LOGIN_PATH" <<SQL
DROP DATABASE IF EXISTS \`$LOCAL_DB\`;
CREATE DATABASE \`$LOCAL_DB\`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
SQL

echo "✅ Local DB '$LOCAL_DB' ready."

# -----------------------------------------------------
# 4. Prepare fast & safe restore session
# -----------------------------------------------------
mysql --login-path="$LOCAL_LOGIN_PATH" "$LOCAL_DB" <<SQL
SET autocommit=0;
SET unique_checks=0;
SET foreign_key_checks=0;
SET sql_log_bin=0;
SQL

# -----------------------------------------------------
# 5. Restore with progress
# -----------------------------------------------------
echo "📥 Importing backup data..."
if gunzip -c "$BACKUP_FILE" | pv | mysql --login-path="$LOCAL_LOGIN_PATH" "$LOCAL_DB"; then
    echo "✅ Data import completed successfully."
else
    echo "❌ Restore failed!"
    exit 1
fi

# -----------------------------------------------------
# 6. Restore safe defaults
# -----------------------------------------------------
mysql --login-path="$LOCAL_LOGIN_PATH" "$LOCAL_DB" <<SQL
COMMIT;
SET autocommit=1;
SET unique_checks=1;
SET foreign_key_checks=1;
SET sql_log_bin=1;
SQL

echo "🎉 Fast & safe restore completed!"

# -----------------------------------------------------
# Step 5: Cleanup old backups
# -----------------------------------------------------
echo "🧹 Cleaning up old backups (keeping last $KEEP_LAST)..."
cd "$BACKUP_DIR" || exit 1
ls -1t staging_backup_*.sql.gz | tail -n +$((KEEP_LAST + 1)) | xargs -r rm -f
echo "✅ Old backups cleaned up."

echo "🚀 Staging DB successfully synced to local!"

