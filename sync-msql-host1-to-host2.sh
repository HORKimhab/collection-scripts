#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-.env}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: env file not found: $ENV_FILE"
  exit 1
fi

# Load .env (trusted file)
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

for v in SRC_HOST SRC_USER DST_HOST DST_USER SRC_DBS DST_DBS; do
  if [[ -z "${!v:-}" ]]; then
    echo "Error: missing required variable '$v' in $ENV_FILE"
    exit 1
  fi
done

for cmd in mysql mysqldump pv; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Error: '$cmd' is not installed."
    exit 1
  }
done

abbrev() {
  local s="$1"
  local n=${#s}
  if (( n <= 3 )); then
    printf '%s' "$s"
  else
    printf '%s...%s' "${s:0:3}" "${s:n-3:3}"
  fi
}

SRC_HOST_MASKED="$(abbrev "$SRC_HOST")"
DST_HOST_MASKED="$(abbrev "$DST_HOST")"
SRC_USER_MASKED="$(abbrev "$SRC_USER")"
DST_USER_MASKED="$(abbrev "$DST_USER")"

IFS=',' read -r -a SRC_DBS_ARR <<< "$SRC_DBS"
IFS=',' read -r -a DST_DBS_ARR <<< "$DST_DBS"

# Trim spaces around DB names
for i in "${!SRC_DBS_ARR[@]}"; do SRC_DBS_ARR[$i]="$(echo "${SRC_DBS_ARR[$i]}" | xargs)"; done
for i in "${!DST_DBS_ARR[@]}"; do DST_DBS_ARR[$i]="$(echo "${DST_DBS_ARR[$i]}" | xargs)"; done

if [[ ${#SRC_DBS_ARR[@]} -ne ${#DST_DBS_ARR[@]} ]]; then
  echo "Error: SRC_DBS and DST_DBS must have same number of items."
  exit 1
fi

if [[ -z "${SRC_PASS:-}" ]]; then
  read -rsp "Enter password for SOURCE (${SRC_USER_MASKED}@${SRC_HOST_MASKED}): " SRC_PASS
  echo ""
fi

if [[ -z "${DST_PASS:-}" ]]; then
  read -rsp"Enter password for DESTINATION (${DST_USER_MASKED}@${DST_HOST_MASKED}): " DST_PASS
  echo ""
fi

estimate_db_bytes() {
  local db="$1"
  MYSQL_PWD="$SRC_PASS" mysql \
    -h "$SRC_HOST" -u "$SRC_USER" --skip-column-names \
    -e "SELECT COALESCE(SUM(data_length + index_length),0)
        FROM information_schema.tables
        WHERE table_schema='${db}';" 2>/dev/null || echo 0
}

for i in "${!SRC_DBS_ARR[@]}"; do
  SRC_DB="${SRC_DBS_ARR[$i]}"
  DST_DB="${DST_DBS_ARR[$i]}"
  DUMP_FILE="/tmp/${SRC_DB}_to_${DST_DB}_dump.sql"

  echo "========================================"
  echo "Copying: $SRC_DB -> $DST_DB"
  echo "========================================"

  EST_BYTES="$(estimate_db_bytes "$SRC_DB")"

  echo "Step 1: Dumping '$SRC_DB'..."
  if [[ "$EST_BYTES" =~ ^[0-9]+$ ]] && [[ "$EST_BYTES" -gt 0 ]]; then
    MYSQL_PWD="$SRC_PASS" mysqldump \
      -h "$SRC_HOST" -u "$SRC_USER" \
      --single-transaction --quick \
      --routines --triggers --events \
      --set-gtid-purged=OFF --column-statistics=0 \
      --default-character-set=utf8mb4 \
      "$SRC_DB" | pv -s "$EST_BYTES" > "$DUMP_FILE"
  else
    MYSQL_PWD="$SRC_PASS" mysqldump \
      -h "$SRC_HOST" -u "$SRC_USER" \
      --single-transaction --quick \
      --routines --triggers --events \
      --set-gtid-purged=OFF --column-statistics=0 \
      --default-character-set=utf8mb4 \
      "$SRC_DB" | pv > "$DUMP_FILE"
  fi

  echo "Step 2: Ensuring destination DB '$DST_DB' exists..."
  MYSQL_PWD="$DST_PASS" mysql \
    -h "$DST_HOST" -u "$DST_USER" \
    -e "CREATE DATABASE IF NOT EXISTS \`$DST_DB\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

  echo "Step 3: Restoring '$DST_DB'..."
  DUMP_BYTES="$(wc -c < "$DUMP_FILE")"
  pv -s "$DUMP_BYTES" "$DUMP_FILE" | MYSQL_PWD="$DST_PASS" mysql \
    -h "$DST_HOST" -u "$DST_USER" \
    --default-character-set=utf8mb4 \
    "$DST_DB"

  rm -f "$DUMP_FILE"
  echo "Done: $SRC_DB -> $DST_DB"
  echo ""
done

echo "All databases copied successfully."
