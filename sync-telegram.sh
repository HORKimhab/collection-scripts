#!/usr/bin/env bash

# Strict mode without `-e` so a single message failure does not abort the full range.
set -uo pipefail

# -----------------------------
# Usage / Help
# -----------------------------
usage() {
  cat <<'HELP'
Usage:
  bash sync-telegram.sh [options]

Description:
  Download media from a source Telegram channel message range using tdl (user
  session / MTProto), split files >1.95GB, upload to TELEGRAM_CHAT_ID via the
  local Bot API server, and keep idempotent state.

  Download layer : tdl (iyear/tdl Docker image) — personal MTProto session,
                   works on any channel your account can read.
  Upload layer   : telegram-bot-api (aiogram/telegram-bot-api Docker image) —
                   sends files to TELEGRAM_CHAT_ID.

Options:
  -d, --dir <path>               Working / download folder (default: sync-telegram)
  --state-file <path>            Custom state file path
  --source-chat-id <ref>         Source chat ref (numeric ID or web URL)
  --d-from <ref>                 Start message ref (numeric ID or t.me URL)
  --d-end <ref>                  End message ref (numeric ID or t.me URL, inclusive)
  --split-max-bytes <bytes>      Split threshold in bytes (default: 1950000000)
  -h, --help                     Show this help

Environment variables (all may be set in .env):
  TELEGRAM_BOT_TOKEN              (required) Bot token for uploads
  TELEGRAM_CHAT_ID                (required) Destination chat/channel ID
  TELEGRAM_FALLBACK_API_BASE_URL  (required) Local Bot API base URL, e.g. http://127.0.0.1:8081

  TDL_COMPOSE_FILE   Path to docker-compose file (default: docker-compose.telegram-bot-api.yml)
  TDL_NS             tdl session namespace (default: tgsync)
  TDL_THREADS        tdl download threads (default: 4)
  TDL_DOWNLOAD_DIR   Host path mounted into tdl container as /downloads (default: SYNC_DIR)
  TDL_SOURCE_CHAT    Override source chat ref specifically for tdl export/dl

  TELEGRAM_SOURCE_CHAT_ID   Source channel (default: https://web.telegram.org/a/#-1002482766032)
  TELEGRAM_DFROM            Start message  (default: https://t.me/UdemyPieFiles/3710)
  TELEGRAM_DEND             End message    (default: https://t.me/UdemyPieFiles/3804)
  TELEGRAM_SPLIT_MAX_BYTES  Split threshold (default: 1950000000)
  TELEGRAM_SEND_DELAY_SEC   Delay between sends in seconds (default: 1)
  TELEGRAM_MAX_RETRIES      Max retries per operation (default: 3)
  TELEGRAM_RETRY_BASE_SEC   Base backoff seconds (default: 2)
  SYNC_MOVE_TO_TRASH        Move local files to trash after send: true/false (default: true)
  TRASH_DIR                 Trash directory (default: $HOME/.Trash)
  TELEGRAM_LOG_ERRORS       Enable error logging: true/false (default: true)
  TELEGRAM_ERROR_LOG_FILE   Error log path (default: <script_dir>/telegram-sync-error.log)
HELP
}

# -----------------------------
# Generic helpers
# -----------------------------

# Load `.env` if present so users can configure without exporting manually.
load_env_file() {
  if [[ -f ".env" ]]; then
    # shellcheck disable=SC1091
    set -a
    source ".env"
    set +a
  fi
}

# Convert to positive integer or fallback.
to_positive_int_or_default() {
  local value="$1"
  local fallback="$2"
  if [[ "$value" =~ ^[0-9]+$ ]] && [[ "$value" -gt 0 ]]; then
    printf '%s' "$value"
  else
    printf '%s' "$fallback"
  fi
}

# Convert to boolean string or fallback.
to_bool_or_default() {
  local value="$1"
  local fallback="$2"
  local lower
  lower="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    true|1|yes|y)  printf 'true'  ;;
    false|0|no|n)  printf 'false' ;;
    *)             printf '%s' "$fallback" ;;
  esac
}

# Build Telegram bot API base path from server URL + token.
build_bot_api_url() {
  local base_url="$1"
  local token="$2"
  while [[ "$base_url" == */ ]]; do base_url="${base_url%/}"; done
  printf '%s/bot%s' "$base_url" "$token"
}

# Return SHA256 for a file; supports macOS and Linux.
sha256_file() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    echo "Missing hash tool: install shasum or sha256sum" >&2
    return 1
  fi
}

# Return SHA256 for a text input; supports macOS and Linux.
sha256_text() {
  local text="$1"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$text" | shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$text" | sha256sum | awk '{print $1}'
  else
    echo "Missing hash tool: install shasum or sha256sum" >&2
    return 1
  fi
}

# Get file size in bytes on both macOS/Linux.
file_size_bytes() {
  local file="$1"
  if stat -f '%z' "$file" >/dev/null 2>&1; then
    stat -f '%z' "$file"
  else
    stat -c '%s' "$file"
  fi
}

# Read message ID from numeric value or URL suffix.
parse_message_id_ref() {
  local ref="$1"
  local cleaned="$ref"
  if [[ "$ref" =~ ^[0-9]+$ ]]; then
    printf '%s' "$ref"; return 0
  fi
  cleaned="${cleaned%%\?*}"
  cleaned="${cleaned%%\#*}"
  while [[ "$cleaned" == */ ]]; do
    cleaned="${cleaned%/}"
  done
  if [[ "$cleaned" =~ /([0-9]+)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"; return 0
  fi
  printf ''
}

# Read source chat ID from raw numeric ID or web URL.
parse_source_chat_id_ref() {
  local ref="$1"
  local cleaned="$ref"

  if [[ "$ref" =~ ^-?[0-9]+$ ]]; then
    printf '%s' "$ref"; return 0
  fi
  if [[ "$ref" =~ ^@[A-Za-z][A-Za-z0-9_]{3,}$ ]]; then
    printf '%s' "$ref"; return 0
  fi
  if [[ "$ref" =~ ^[A-Za-z][A-Za-z0-9_]{3,}$ ]]; then
    printf '@%s' "$ref"; return 0
  fi
  if [[ "$ref" =~ \#(-?[0-9]+)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"; return 0
  fi

  cleaned="${cleaned%%\?*}"
  cleaned="${cleaned%%\#*}"
  while [[ "$cleaned" == */ ]]; do
    cleaned="${cleaned%/}"
  done

  # t.me/c/<id> chat format (private supergroup/channel links)
  if [[ "$cleaned" =~ /c/([0-9]+)(/[0-9]+)?$ ]]; then
    printf '%s%s' '-100' "${BASH_REMATCH[1]}"; return 0
  fi
  if [[ "$cleaned" =~ /(-?[0-9]+)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"; return 0
  fi
  if [[ "$cleaned" =~ /([A-Za-z][A-Za-z0-9_]{3,})$ ]]; then
    printf '@%s' "${BASH_REMATCH[1]}"; return 0
  fi
  printf ''
}

# Parse public t.me username from message/channel refs.
parse_tme_username_ref() {
  local ref="$1"
  local cleaned="$ref"
  cleaned="${cleaned%%\?*}"
  cleaned="${cleaned%%\#*}"

  if [[ "$cleaned" =~ t\.me/([A-Za-z][A-Za-z0-9_]{3,})($|/) ]]; then
    if [[ "${BASH_REMATCH[1]}" != "c" ]]; then
      printf '%s' "${BASH_REMATCH[1]}"
      return 0
    fi
  fi
  printf ''
}

# Replace problematic characters for local file naming.
sanitize_filename() {
  local name="$1"
  name="${name//\//_}"
  name="${name//$'\n'/_}"
  name="${name//$'\r'/_}"
  name="${name//:/_}"
  name="${name//\?/_}"
  name="${name//\*/_}"
  name="${name//\"/_}"
  name="${name//</_}"
  name="${name//>/_}"
  name="${name//|/_}"
  printf '%s' "$name"
}

# -----------------------------
# Logging / cleanup
# -----------------------------

log_message() {
  local level="$1"
  local message="$2"
  [[ "$LOG_ERRORS" != "true" ]] && return 0
  printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$message" >> "$ERROR_LOG_FILE"
}

move_to_trash() {
  local file="$1"
  local base target
  [[ ! -e "$file" ]] && return 0
  mkdir -p "$TRASH_DIR" 2>/dev/null || { echo "Warning: cannot access trash dir: $TRASH_DIR" >&2; return 1; }
  base="$(basename "$file")"
  target="$TRASH_DIR/$base"
  [[ -e "$target" ]] && target="$TRASH_DIR/${base}.$(date +%Y%m%d-%H%M%S)"
  mv -- "$file" "$target" 2>/dev/null || { echo "Warning: failed moving to trash: $file" >&2; return 1; }
  return 0
}

# -----------------------------
# State handling
# -----------------------------

declare -A STATE_INDEX=()

state_load() {
  local line=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    STATE_INDEX["$line"]=1
  done < "$STATE_FILE"
}

state_has() {
  local key="$1"
  [[ -n "${STATE_INDEX[$key]+x}" ]]
}

state_add() {
  local key="$1"
  state_has "$key" && return 0
  printf '%s\n' "$key" >> "$STATE_FILE"
  STATE_INDEX["$key"]=1
}

# -----------------------------
# Telegram Bot API helpers (upload only)
# -----------------------------

API_LAST_RESPONSE=""

read_retry_after_seconds() {
  local response="$1"
  jq -r '.parameters.retry_after // empty' <<<"$response" 2>/dev/null | head -n 1
}

telegram_api_post_json() {
  local method="$1"
  local payload="$2"
  local label="$3"
  local attempt=1
  local response="" curl_exit=1 retry_after="" sleep_sec=0 compact_response=""

  while [[ $attempt -le $MAX_RETRIES ]]; do
    response="$(curl -sS -X POST "${TELEGRAM_API_URL}/${method}" \
      -H "Content-Type: application/json" \
      -d "$payload" 2>&1)"
    curl_exit=$?
    compact_response="${response//$'\n'/ }"
    compact_response="${compact_response//$'\r'/ }"

    if [[ $curl_exit -eq 0 ]] && jq -e '.ok == true' >/dev/null 2>&1 <<<"$response"; then
      API_LAST_RESPONSE="$response"
      return 0
    fi

    log_message "WARN" "attempt=${attempt}/${MAX_RETRIES} method=${method} label=${label} curl_exit=${curl_exit} response=${compact_response}"
    retry_after="$(read_retry_after_seconds "$response")"
    sleep_sec="${retry_after:-$((RETRY_BASE_SEC * attempt))}"
    [[ $attempt -lt $MAX_RETRIES ]] && sleep "$sleep_sec"
    attempt=$((attempt + 1))
  done

  API_LAST_RESPONSE="$response"
  return 1
}

# Send one file part/document with retries.
telegram_send_document() {
  local file_path="$1"
  local caption="$2"
  local upload_name="$3"
  local label="$4"
  local attempt=1
  local response="" curl_exit=1 retry_after="" sleep_sec=0 compact_response=""

  if [[ ! -r "$file_path" ]]; then
    echo "Upload file is not readable: $label" >&2
    log_message "ERROR" "upload_not_readable label=${label}"
    return 1
  fi

  while [[ $attempt -le $MAX_RETRIES ]]; do
    response="$(curl -sS -X POST "${TELEGRAM_API_URL}/sendDocument" \
      -F "chat_id=${CHAT_ID}" \
      -F "caption=${caption}" \
      -F "document=@${file_path};filename=${upload_name}" 2>&1)"
    curl_exit=$?
    compact_response="${response//$'\n'/ }"
    compact_response="${compact_response//$'\r'/ }"

    if [[ $curl_exit -eq 0 ]] && jq -e '.ok == true' >/dev/null 2>&1 <<<"$response"; then
      sleep "$SEND_DELAY_SEC"
      return 0
    fi

    if [[ $curl_exit -eq 26 ]]; then
      echo "Cannot read file for upload: $label" >&2
      log_message "ERROR" "upload_read_error_26 label=${label}"
      break
    fi

    log_message "WARN" "attempt=${attempt}/${MAX_RETRIES} send label=${label} curl_exit=${curl_exit} response=${compact_response}"
    retry_after="$(read_retry_after_seconds "$response")"
    sleep_sec="${retry_after:-$((RETRY_BASE_SEC * attempt))}"
    if [[ $attempt -lt $MAX_RETRIES ]]; then
      echo "Retry send (${attempt}/${MAX_RETRIES}) after ${sleep_sec}s: $label" >&2
      sleep "$sleep_sec"
    fi
    attempt=$((attempt + 1))
  done

  echo "Telegram send failed: $label" >&2
  log_message "ERROR" "final_send_failed label=${label} response=${compact_response}"
  return 1
}

# -----------------------------
# tdl download layer
# -----------------------------

# Run tdl inside running Docker service via docker compose exec.
# Ensures the tdl container stays alive and can auto-restart.
tdl_run() {
  # Start (or keep) tdl service before executing commands in it.
  if ! docker compose -f "$TDL_COMPOSE_FILE" up -d tdl >/dev/null 2>&1; then
    echo "Failed to start tdl service from compose file: ${TDL_COMPOSE_FILE}" >&2
    return 1
  fi

  docker compose \
    -f "$TDL_COMPOSE_FILE" \
    exec -T \
    -e TDL_NS="$TDL_NS" \
    tdl tdl "$@"
}

# Download a range of messages from SOURCE_CHAT_ID using tdl.
# Files land in SYNC_DIR (mounted as /downloads inside the container).
# Returns 0 if tdl exited successfully; non-zero otherwise.
tdl_download_range() {
  local from_id="$1"
  local to_id="$2"
  local exit_code=0
  local export_file_host=""
  local export_file_container=""
  local export_basename=""
  local chat_ref=""
  local export_chat_label=""
  local try_refs=()
  local last_error_code=1
  local export_success="false"

  echo "tdl: downloading messages ${from_id}–${to_id} from ${TDL_SOURCE_CHAT} ..." 
  log_message "INFO" "tdl_download_start from=${from_id} to=${to_id} chat=${TDL_SOURCE_CHAT}"

  try_refs+=("${TDL_SOURCE_CHAT}")
  if [[ "${SOURCE_CHAT_ID}" != "${TDL_SOURCE_CHAT}" ]]; then
    try_refs+=("${SOURCE_CHAT_ID}")
  fi
  if [[ "${SOURCE_CHAT_REF}" != "${TDL_SOURCE_CHAT}" && "${SOURCE_CHAT_REF}" != "${SOURCE_CHAT_ID}" ]]; then
    try_refs+=("${SOURCE_CHAT_REF}")
  fi

  # Step 1: export message metadata (ID range) to JSON.
  # Try multiple source chat refs for better compatibility across public/private chats.
  for chat_ref in "${try_refs[@]}"; do
    export_chat_label="$(sanitize_filename "$chat_ref")"
    export_basename=".tdl-export-${export_chat_label}-${from_id}-${to_id}.json"
    export_file_host="${SYNC_DIR}/${export_basename}"
    export_file_container="/downloads/${export_basename}"
    rm -f -- "$export_file_host"

    exit_code=0
    tdl_run chat export \
      -c "${chat_ref}" \
      -T id \
      -i "${from_id},${to_id}" \
      --all \
      -o "${export_file_container}" \
      || exit_code=$?

    if [[ $exit_code -eq 0 && -s "$export_file_host" ]]; then
      export_success="true"
      log_message "INFO" "tdl_export_ok chat_ref=${chat_ref} from=${from_id} to=${to_id}"
      break
    fi

    last_error_code="$exit_code"
    log_message "WARN" "tdl_export_try_failed chat_ref=${chat_ref} from=${from_id} to=${to_id} exit=${exit_code}"
  done

  if [[ "$export_success" != "true" ]]; then
    echo "tdl: export failed for range ${from_id}–${to_id} (exit ${last_error_code})" >&2
    log_message "ERROR" "tdl_export_failed from=${from_id} to=${to_id} exit=${last_error_code} tried=${try_refs[*]}"
    return 1
  fi

  # Step 2: download from exported JSON.
  # tdl dl flags:
  #   -f FILE        : message export JSON
  #   -d DIR         : output directory
  #   -t N           : threads per task
  #   --continue     : resume interrupted downloads
  tdl_run dl \
    -f "${export_file_container}" \
    -d /downloads \
    -t "${TDL_THREADS}" \
    --continue \
    || exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    echo "tdl: download exited with code ${exit_code} for range ${from_id}–${to_id}" >&2
    log_message "ERROR" "tdl_download_failed from=${from_id} to=${to_id} exit=${exit_code}"
    return 1
  fi

  log_message "INFO" "tdl_download_ok from=${from_id} to=${to_id}"
  return 0
}

# Locate the file downloaded by tdl for a specific message ID.
# tdl names files as: <message_id>-<original_filename>  (zero-padded or not)
# Falls back to any file whose name starts with the message ID.
find_tdl_file_for_message() {
  local message_id="$1"
  local found=""

  shopt -s nullglob
  # tdl typically writes: <msg_id>-<name>  or  <msg_id>_<name>
  local candidates=("${SYNC_DIR}/${message_id}"-* "${SYNC_DIR}/${message_id}_"*)
  shopt -u nullglob

  for f in "${candidates[@]}"; do
    # Skip split part artifacts left from previous runs.
    [[ "$f" == *.part.* ]] && continue
    # Skip directories.
    [[ -d "$f" ]] && continue
    # Take the first real file match.
    if [[ -f "$f" && -s "$f" ]]; then
      found="$f"
      break
    fi
  done

  printf '%s' "$found"
}

# -----------------------------
# Split / send / cleanup helpers
# -----------------------------

collect_files_to_send() {
  local file_path="$1"
  local size=0 split_prefix="" parts=()

  size="$(file_size_bytes "$file_path")" || return 1

  if [[ "$size" -le "$SPLIT_SIZE_BYTES" ]]; then
    printf '%s\n' "$file_path"
    return 0
  fi

  split_prefix="${file_path}.part."

  shopt -s nullglob
  parts=("${split_prefix}"*)
  shopt -u nullglob

  if [[ ${#parts[@]} -eq 0 ]]; then
    echo "Splitting (> ${SPLIT_SIZE_BYTES} bytes): $(basename "$file_path")" >&2
    if ! split -b "$SPLIT_SIZE_BYTES" -d -a 4 -- "$file_path" "$split_prefix"; then
      echo "Failed split for: $file_path" >&2
      return 1
    fi
    shopt -s nullglob
    parts=("${split_prefix}"*)
    shopt -u nullglob
  fi

  [[ ${#parts[@]} -eq 0 ]] && return 1
  printf '%s\n' "${parts[@]}"
}

send_file_with_split_state() {
  local message_id="$1"
  local source_file="$2"
  local files_to_send=() total=0 idx=1
  local item="" item_hash="" part_state_key="" caption=""

  mapfile -t files_to_send < <(collect_files_to_send "$source_file") || return 1
  total="${#files_to_send[@]}"
  [[ "$total" -eq 0 ]] && return 1

  for item in "${files_to_send[@]}"; do
    item_hash="$(sha256_file "$item")" || return 1
    part_state_key="channel|${SOURCE_CHAT_ID}|${message_id}|part|${idx}/${total}|${item_hash}|sent"

    if state_has "$part_state_key"; then
      idx=$((idx + 1))
      continue
    fi

    caption="Source Chat: ${SOURCE_CHAT_ID}
Source Message ID: ${message_id}
Part: ${idx}/${total}
File: $(basename "$source_file")
Time: $(date '+%Y-%m-%d %H:%M:%S')"

    if ! telegram_send_document "$item" "$caption" "$(basename "$item")" "$item"; then
      return 1
    fi

    state_add "$part_state_key"
    idx=$((idx + 1))
  done

  return 0
}

cleanup_message_artifacts() {
  local message_id="$1"
  local path=""

  shopt -s nullglob
  # Match both msg-<id>-* (legacy) and <id>-* / <id>_* (tdl naming).
  for path in \
    "${SYNC_DIR}/msg-${message_id}-"* \
    "${SYNC_DIR}/${message_id}-"* \
    "${SYNC_DIR}/${message_id}_"*; do
    if [[ "$MOVE_TO_TRASH" == "true" ]]; then
      move_to_trash "$path" || true
    else
      rm -f -- "$path"
    fi
  done
  shopt -u nullglob
}

# -----------------------------
# Core per-message workflow
# -----------------------------

# Process one already-downloaded message:
# locate tdl file → split if needed → send → persist state → cleanup.
process_downloaded_message() {
  local message_id="$1"
  local local_file=""
  local safe_name="" file_hash=""

  local sent_key="channel|${SOURCE_CHAT_ID}|${message_id}|sent"

  # Already fully sent in a previous run.
  if state_has "$sent_key"; then
    cleanup_message_artifacts "$message_id"
    skip_count=$((skip_count + 1))
    return 0
  fi

  # Locate the file tdl wrote for this message ID.
  local_file="$(find_tdl_file_for_message "$message_id")"

  if [[ -z "$local_file" ]]; then
    # tdl may have skipped this message (no media, deleted, etc.).
    local no_media_key="channel|${SOURCE_CHAT_ID}|${message_id}|no_media"
    state_add "$no_media_key"
    skip_count=$((skip_count + 1))
    return 0
  fi

  # Derive stable unique id from file content hash (first 16 chars).
  file_hash="$(sha256_file "$local_file" | cut -c1-16)" || {
    echo "Hash failed for: ${local_file}" >&2
    fail_count=$((fail_count + 1))
    return 1
  }

  local download_key="channel|${SOURCE_CHAT_ID}|${message_id}|downloaded|${file_hash}"
  # Mark as downloaded (tdl already did the work).
  state_add "$download_key"

  # Send file (or parts), then mark message as sent.
  if send_file_with_split_state "$message_id" "$local_file"; then
    state_add "$sent_key"
    printf -- "- %s\n" "$(basename "$local_file")" >> "$STORE_FILE"
    cleanup_message_artifacts "$message_id"
    sent_count=$((sent_count + 1))
    echo "Synced message ${message_id}: $(basename "$local_file")"
    return 0
  fi

  echo "Send failed for message: ${message_id}" >&2
  fail_count=$((fail_count + 1))
  return 1
}

# -----------------------------
# Main
# -----------------------------

load_env_file

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults.
SYNC_DIR="${SYNC_DIR:-sync-telegram}"
STATE_FILE=""
STORE_FILE_NAME="all-store-telegram.txt"
STORE_FILE=""
SOURCE_CHAT_REF="${TELEGRAM_SOURCE_CHAT_ID:-${TELEGRAM_SOURCE_CHAT:-https://web.telegram.org/a/#-1002482766032}}"
DFROM_REF="${TELEGRAM_DFROM:-https://t.me/UdemyPieFiles/3710}"
DEND_REF="${TELEGRAM_DEND:-https://t.me/UdemyPieFiles/3804}"
SPLIT_SIZE_BYTES="$(to_positive_int_or_default "${TELEGRAM_SPLIT_MAX_BYTES:-1950000000}" 1950000000)"

# Parse CLI options.
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dir)
      [[ $# -lt 2 ]] && { echo "Missing value for $1" >&2; exit 1; }
      SYNC_DIR="$2"; shift 2 ;;
    --state-file)
      [[ $# -lt 2 ]] && { echo "Missing value for $1" >&2; exit 1; }
      STATE_FILE="$2"; shift 2 ;;
    --source-chat-id|--source-chat)
      [[ $# -lt 2 ]] && { echo "Missing value for $1" >&2; exit 1; }
      SOURCE_CHAT_REF="$2"; shift 2 ;;
    --d-from|--from-id)
      [[ $# -lt 2 ]] && { echo "Missing value for $1" >&2; exit 1; }
      DFROM_REF="$2"; shift 2 ;;
    --d-end|--to-id)
      [[ $# -lt 2 ]] && { echo "Missing value for $1" >&2; exit 1; }
      DEND_REF="$2"; shift 2 ;;
    --split-max-bytes)
      [[ $# -lt 2 ]] && { echo "Missing value for $1" >&2; exit 1; }
      SPLIT_SIZE_BYTES="$(to_positive_int_or_default "$2" "$SPLIT_SIZE_BYTES")"
      shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# Core env vars.
BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-${BOT_TOKEN:-}}"
CHAT_ID="${TELEGRAM_CHAT_ID:-${TELEGRAM_GROUP_CHAT_ID:-${CHAT_ID:-}}}"
FALLBACK_API_BASE_URL="${TELEGRAM_FALLBACK_API_BASE_URL:-}"

# tdl env vars.
TDL_COMPOSE_FILE="${TDL_COMPOSE_FILE:-docker-compose.telegram-bot-api.yml}"
TDL_NS="${TDL_NS:-tgsync}"
TDL_THREADS="$(to_positive_int_or_default "${TDL_THREADS:-4}" 4)"
TDL_SOURCE_CHAT="${TDL_SOURCE_CHAT:-}"

# Runtime tunables.
SEND_DELAY_SEC="$(to_positive_int_or_default "${TELEGRAM_SEND_DELAY_SEC:-1}" 1)"
MAX_RETRIES="$(to_positive_int_or_default "${TELEGRAM_MAX_RETRIES:-3}" 3)"
RETRY_BASE_SEC="$(to_positive_int_or_default "${TELEGRAM_RETRY_BASE_SEC:-2}" 2)"
MOVE_TO_TRASH="$(to_bool_or_default "${SYNC_MOVE_TO_TRASH:-true}" "true")"
TRASH_DIR="${TRASH_DIR:-$HOME/.Trash}"
LOG_ERRORS="$(to_bool_or_default "${TELEGRAM_LOG_ERRORS:-true}" "true")"
ERROR_LOG_FILE="${TELEGRAM_ERROR_LOG_FILE:-$SCRIPT_DIR/telegram-sync-error.log}"

# Validate required env values.
if [[ -z "$BOT_TOKEN" ]]; then
  echo "Missing TELEGRAM_BOT_TOKEN in environment or .env" >&2; exit 1
fi
if [[ -z "$CHAT_ID" ]]; then
  echo "Missing TELEGRAM_CHAT_ID in environment or .env" >&2; exit 1
fi
if [[ -z "$FALLBACK_API_BASE_URL" ]]; then
  echo "Missing TELEGRAM_FALLBACK_API_BASE_URL in environment or .env" >&2; exit 1
fi

# Validate required tools.
for cmd in curl jq split docker; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2; exit 1
  fi
done

# Validate docker compose subcommand availability.
if ! docker compose version >/dev/null 2>&1; then
  echo "Missing required command: docker compose (v2)" >&2; exit 1
fi

# Validate tdl compose file exists.
if [[ ! -f "$TDL_COMPOSE_FILE" ]]; then
  echo "TDL_COMPOSE_FILE not found: ${TDL_COMPOSE_FILE}" >&2; exit 1
fi

# Resolve refs to numeric IDs.
SOURCE_CHAT_ID="$(parse_source_chat_id_ref "$SOURCE_CHAT_REF")"
FROM_ID="$(parse_message_id_ref "$DFROM_REF")"
TO_ID="$(parse_message_id_ref "$DEND_REF")"

if [[ -z "$SOURCE_CHAT_ID" ]]; then
  echo "Invalid source chat reference: $SOURCE_CHAT_REF" >&2; exit 1
fi
if [[ -z "$FROM_ID" || -z "$TO_ID" ]]; then
  echo "Invalid dFrom/dEnd references." >&2; exit 1
fi
if (( FROM_ID > TO_ID )); then
  echo "Invalid range: dFrom (${FROM_ID}) must be <= dEnd (${TO_ID})." >&2; exit 1
fi

# Resolve tdl source chat ref:
# 1) explicit TDL_SOURCE_CHAT env
# 2) username from source ref / dFrom / dEnd
# 3) fallback SOURCE_CHAT_ID
if [[ -z "$TDL_SOURCE_CHAT" ]]; then
  tdl_source_username="$(parse_tme_username_ref "$SOURCE_CHAT_REF")"
  [[ -z "$tdl_source_username" ]] && tdl_source_username="$(parse_tme_username_ref "$DFROM_REF")"
  [[ -z "$tdl_source_username" ]] && tdl_source_username="$(parse_tme_username_ref "$DEND_REF")"
  if [[ -n "$tdl_source_username" ]]; then
    TDL_SOURCE_CHAT="@${tdl_source_username}"
  else
    TDL_SOURCE_CHAT="$SOURCE_CHAT_ID"
  fi
fi

# Normalize plain username override into @username.
if [[ "$TDL_SOURCE_CHAT" =~ ^[A-Za-z][A-Za-z0-9_]{3,}$ ]]; then
  TDL_SOURCE_CHAT="@${TDL_SOURCE_CHAT}"
fi

# Build Bot API URL (upload only).
TELEGRAM_API_URL="$(build_bot_api_url "$FALLBACK_API_BASE_URL" "$BOT_TOKEN")"

# Prepare working directory.
mkdir -p "$SYNC_DIR"
SYNC_DIR="$(cd "$SYNC_DIR" && pwd)"

# TDL_DOWNLOAD_DIR defaults to SYNC_DIR; used as host-side mount for /downloads.
TDL_DOWNLOAD_DIR="${TDL_DOWNLOAD_DIR:-$SYNC_DIR}"
export TDL_DOWNLOAD_DIR

[[ -z "$STATE_FILE" ]] && STATE_FILE="$SYNC_DIR/.telegram-sync-state"

STORE_FILE="$SCRIPT_DIR/$STORE_FILE_NAME"
touch "$STATE_FILE"
touch "$STORE_FILE"

if [[ "$LOG_ERRORS" == "true" ]]; then
  mkdir -p "$(dirname "$ERROR_LOG_FILE")"
  touch "$ERROR_LOG_FILE"
fi

state_load

log_message "INFO" "start source_chat_id=${SOURCE_CHAT_ID} tdl_source_chat=${TDL_SOURCE_CHAT} from=${FROM_ID} to=${TO_ID} split_max_bytes=${SPLIT_SIZE_BYTES}"

# Counters.
sent_count=0
skip_count=0
fail_count=0

# -----------------------------------------------------------------------
# Step 1: Use tdl to download the entire range in one shot.
#         tdl handles resumption internally (--continue).
#         Already-downloaded files are reused by tdl automatically.
# -----------------------------------------------------------------------
if ! tdl_download_range "$FROM_ID" "$TO_ID"; then
  echo "tdl download step failed — aborting." >&2
  log_message "ERROR" "tdl_download_range_failed from=${FROM_ID} to=${TO_ID}"
  exit 1
fi

# -----------------------------------------------------------------------
# Step 2: Walk the message range sequentially and send each file.
#         Per-message and per-part idempotency is handled via state file.
# -----------------------------------------------------------------------
for ((message_id=FROM_ID; message_id<=TO_ID; message_id++)); do
  process_downloaded_message "$message_id" || true
done

echo "Done. Sent=${sent_count} Skipped=${skip_count} Failed=${fail_count}"
log_message "INFO" "done sent=${sent_count} skipped=${skip_count} failed=${fail_count}"

[[ $fail_count -eq 0 ]]
