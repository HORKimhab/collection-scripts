#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-.env}"
[[ -f "$ENV_FILE" ]] || { echo "Error: env file not found: $ENV_FILE"; exit 1; }

# Load .env
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# -------------------------
# Validate variables
# -------------------------
for v in SRC_HOST SRC_USER DST_HOST DST_USER SRC_DBS DST_DBS; do
  [[ -n "${!v:-}" ]] || { echo "Error: missing '$v' in $ENV_FILE"; exit 1; }
done

for cmd in mysql mysqldump pv; do
  command -v "$cmd" >/dev/null || { echo "Error: '$cmd' not installed"; exit 1; }
done

# -------------------------
# Helpers
# -------------------------
abbrev() {
  local s="$1" n=${#1}
  (( n <= 3 )) && printf '%s' "$s" || printf '%s...%s' "${s:0:3}" "${s:n-3:3}"
}

estimate_db_bytes() {
  local db="$1"
  MYSQL_PWD="$SRC_PASS" mysql \
    -h "$SRC_HOST" -u "$SRC_USER" --skip-column-names \
    -e "SELECT COALESCE(SUM(data_length+index_length),0)
        FROM information_schema.tables
        WHERE table_schema='${db}';" 2>/dev/null || echo 0
}

# -------------------------
# Masked display
# -------------------------
SRC_HOST_MASKED="$(abbrev "$SRC_HOST")"
DST_HOST_MASKED="$(abbrev "$DST_HOST")"
SRC_USER_MASKED="$(abbrev "$SRC_USER")"
DST_USER_MASKED="$(abbrev "$DST_USER")"

# -------------------------
# Parse DB lists
# -------------------------
IFS=',' read -r -a SRC_DBS_ARR <<< "$SRC_DBS"
IFS=',' read -r -a DST_DBS_ARR <<< "$DST_DBS"

[[ ${#SRC_DBS_ARR[@]} -eq ${#DST_DBS_ARR[@]} ]] || {
  echo "Error: SRC_DBS and DST_DBS count mismatch"; exit 1;
}

for i in "${!SRC_DBS_ARR[@]}"; do
  SRC_DBS_ARR[$i]="$(echo "${SRC_DBS_ARR[$i]}" | xargs)"
  DST_DBS_ARR[$i]="$(echo "${DST_DBS_ARR[$i]}" | xargs)"
done

# -------------------------
# Passwords
# -------------------------
if [[ -z "${SRC_PASS:-}" ]]; then
  read -rsp "Enter password for SOURCE (${SRC_USER_MASKED}@${SRC_HOST_MASKED}): " SRC_PASS; echo
fi

if [[ -z "${DST_PASS:-}" ]]; then
  read -rsp "Enter password for DESTINATION (${DST_USER_MASKED}@${DST_HOST_MASKED}): " DST_PASS; echo
fi

# =========================
# 🚀 MAIN COPY LOOP
# =========================
for i in "${!SRC_DBS_ARR[@]}"; do
  SRC_DB="${SRC_DBS_ARR[$i]}"
  DST_DB="${DST_DBS_ARR[$i]}"

  echo "========================================"
  echo "Copying: $SRC_DB  →  $DST_DB"
  echo "========================================"

  echo "Ensuring destination DB exists..."
  MYSQL_PWD="$DST_PASS" mysql \
    -h "$DST_HOST" -u "$DST_USER" \
    -e "CREATE DATABASE IF NOT EXISTS \`$DST_DB\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

  EST_BYTES="$(estimate_db_bytes "$SRC_DB")"

  echo "Streaming dump → restore..."

  MYSQL_PWD="$SRC_PASS" mysqldump \
    -h "$SRC_HOST" -u "$SRC_USER" \
    --single-transaction \
    --quick \
    --routines --triggers --events \
    --set-gtid-purged=OFF \
    --column-statistics=0 \
    --default-character-set=utf8mb4 \
    --extended-insert \
    --skip-add-locks \
    --skip-comments \
    --compression-algorithms=zstd \
    --net-buffer-length=1M \
    --max-allowed-packet=1G \
    "$SRC_DB" \
  | pv ${EST_BYTES:+-s "$EST_BYTES"} \
  | MYSQL_PWD="$DST_PASS" mysql \
      -h "$DST_HOST" -u "$DST_USER" \
      --default-character-set=utf8mb4 \
      "$DST_DB"

  echo "Done: $SRC_DB → $DST_DB"
  echo
done

echo "✅ All databases copied successfully."