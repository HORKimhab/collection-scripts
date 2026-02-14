#!/usr/bin/env bash

set -uo pipefail

usage() {
  cat <<'HELP'
Usage:
  bash sync-telegram.sh [directory]
  bash sync-telegram.sh --dir /path/to/folder

Description:
  Sync files from a folder to Telegram.
  - Image/video files are sent as-is (not encrypted)
  - All other file types are encrypted before upload
  Default folder is: sync-telegram

Options:
  -d, --dir <path>          Folder to sync (default: sync-telegram)
  --state-file <path>       Custom sync state file
  -h, --help                Show this help

Environment variables:
  TELEGRAM_BOT_TOKEN
  TELEGRAM_CHAT_ID
  TELEGRAM_API_BASE_URL    (optional, default: https://api.telegram.org)
  TELEGRAM_FALLBACK_API_BASE_URL (optional, fallback on 413, example: http://127.0.0.1:8081)
  TELEGRAM_ENCRYPT_PASSWORD
  SECRET_45
  SECRET_SAME
  TELEGRAM_SEND_DELAY_SEC   (optional, default: 1)
  TELEGRAM_MAX_RETRIES      (optional, default: 3)
  TELEGRAM_RETRY_BASE_SEC   (optional, default: 2)
  SYNC_INCLUDE_HIDDEN       (optional: true/false, default: false)
  SYNC_MOVE_TO_TRASH        (optional: true/false, default: true)
  TRASH_DIR                 (optional, default: $HOME/.Trash)
  TELEGRAM_LOG_ERRORS       (optional: true/false, default: true)
  TELEGRAM_ERROR_LOG_FILE   (optional, default: <script_dir>/telegram-sync-error.log)
HELP
}

load_env_file() {
  if [[ -f ".env" ]]; then
    # shellcheck disable=SC1091
    set -a
    source ".env"
    set +a
  fi
}

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

is_media_file() {
  local file_name="$1"
  local lower
  lower="$(printf '%s' "$file_name" | tr '[:upper:]' '[:lower:]')"

  case "$lower" in
    *.jpg|*.jpeg|*.png|*.gif|*.webp|*.bmp|*.tif|*.tiff|*.heic|*.heif|*.svg|*.avif|*.ico)
      return 0
      ;;
    *.mp4|*.mov|*.avi|*.mkv|*.webm|*.m4v|*.mpg|*.mpeg|*.3gp|*.mts|*.m2ts|*.wmv)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

to_positive_int_or_default() {
  local value="$1"
  local fallback="$2"

  if [[ "$value" =~ ^[0-9]+$ ]] && [[ "$value" -gt 0 ]]; then
    printf '%s' "$value"
  else
    printf '%s' "$fallback"
  fi
}

to_bool_or_default() {
  local value="$1"
  local fallback="$2"
  local lower
  lower="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"

  case "$lower" in
    true|1|yes|y) printf 'true' ;;
    false|0|no|n) printf 'false' ;;
    *) printf '%s' "$fallback" ;;
  esac
}

build_bot_api_url() {
  local base_url="$1"
  local token="$2"

  while [[ "$base_url" == */ ]]; do
    base_url="${base_url%/}"
  done

  if [[ "$base_url" == */bot${token} ]]; then
    printf '%s' "$base_url"
  elif [[ "$base_url" == */bot ]]; then
    printf '%s%s' "$base_url" "$token"
  else
    printf '%s/bot%s' "$base_url" "$token"
  fi
}

log_message() {
  local level="$1"
  local message="$2"

  if [[ "${LOG_ERRORS}" != "true" ]]; then
    return 0
  fi

  printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$message" >> "$ERROR_LOG_FILE"
}

move_to_trash() {
  local file="$1"
  local base
  local target

  [[ ! -e "$file" ]] && return 0

  mkdir -p "$TRASH_DIR" 2>/dev/null || {
    echo "Warning: cannot access trash dir: $TRASH_DIR" >&2
    return 1
  }

  base="$(basename "$file")"
  target="$TRASH_DIR/$base"

  if [[ -e "$target" ]]; then
    target="$TRASH_DIR/${base}.$(date +%Y%m%d-%H%M%S)"
  fi

  mv -- "$file" "$target" 2>/dev/null || {
    echo "Warning: failed moving to trash: $file" >&2
    return 1
  }
  return 0
}

send_to_telegram() {
  local upload_file="$1"
  local caption="$2"
  local upload_name="${3:-}"
  local source_label="${4:-$upload_file}"
  local current_api_url="$TELEGRAM_API_URL"
  local current_base_url="$API_BASE_URL"
  local switched_to_fallback="false"
  local attempt=1
  local response=""
  local curl_exit=1
  local retry_after=""
  local sleep_sec=0
  local compact_response=""

  while [[ $attempt -le $MAX_RETRIES ]]; do
    if [[ -n "$upload_name" ]]; then
      response="$(curl -sS -X POST "${current_api_url}/sendDocument" \
        -F "chat_id=${CHAT_ID}" \
        -F "caption=${caption}" \
        -F "document=@${upload_file};filename=${upload_name}" 2>&1)"
    else
      response="$(curl -sS -X POST "${current_api_url}/sendDocument" \
        -F "chat_id=${CHAT_ID}" \
        -F "caption=${caption}" \
        -F "document=@${upload_file}" 2>&1)"
    fi
    curl_exit=$?
    compact_response="${response//$'\n'/ }"
    compact_response="${compact_response//$'\r'/ }"

    if [[ $curl_exit -eq 0 && "$response" == *'"ok":true'* ]]; then
      sleep "$SEND_DELAY_SEC"
      return 0
    fi

    if [[ $curl_exit -eq 0 && "$response" == *'"error_code":413'* ]]; then
      if [[ "$switched_to_fallback" == "false" && -n "${TELEGRAM_FALLBACK_API_URL:-}" ]]; then
        echo "Detected 413 from ${current_base_url}; retrying via local tdlib Bot API server: ${FALLBACK_API_BASE_URL}" >&2
        log_message "INFO" "switch_to_fallback_413 file=${source_label} from=${current_base_url} to=${FALLBACK_API_BASE_URL}"
        current_api_url="$TELEGRAM_FALLBACK_API_URL"
        current_base_url="$FALLBACK_API_BASE_URL"
        switched_to_fallback="true"
        continue
      fi

      if [[ "$API_BASE_URL" == "https://api.telegram.org" && -z "${TELEGRAM_FALLBACK_API_URL:-}" ]]; then
        echo "Hint: Cloud Bot API upload limit reached. Set TELEGRAM_FALLBACK_API_BASE_URL to your tdlib local Bot API server (example: http://127.0.0.1:8081)." >&2
      fi
      compact_response="${response//$'\n'/ }"
      compact_response="${compact_response//$'\r'/ }"
      log_message "ERROR" "non_retryable_413 file=${source_label} api_base_url=${current_base_url} response=${compact_response}"
      break
    fi

    if [[ $curl_exit -eq 7 && -n "${TELEGRAM_FALLBACK_API_URL:-}" && "$current_base_url" == "$FALLBACK_API_BASE_URL" ]]; then
      echo "Local tdlib Bot API server is not reachable at ${FALLBACK_API_BASE_URL}. Start it with: docker compose -f ${SCRIPT_DIR}/docker-compose.telegram-bot-api.yml up -d" >&2
    fi

    log_message "WARN" "attempt=${attempt}/${MAX_RETRIES} file=${source_label} api_base_url=${current_base_url} curl_exit=${curl_exit} response=${compact_response}"

    retry_after="$(printf '%s' "$response" | sed -n 's/.*"retry_after"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n 1)"
    if [[ -n "$retry_after" ]]; then
      sleep_sec="$retry_after"
    else
      sleep_sec=$((RETRY_BASE_SEC * attempt))
    fi

    if [[ $attempt -lt $MAX_RETRIES ]]; then
      echo "Retry send (${attempt}/${MAX_RETRIES}) after ${sleep_sec}s" >&2
      log_message "INFO" "retry file=${source_label} after=${sleep_sec}s"
      sleep "$sleep_sec"
    fi

    attempt=$((attempt + 1))
  done

  echo "Telegram send failed for: $source_label" >&2
  echo "Telegram response: $response" >&2
  log_message "ERROR" "final_fail file=${source_label} curl_exit=${curl_exit} response=${compact_response}"
  return 1
}

send_plain_file() {
  local file="$1"
  local rel_path="$2"
  local original_name
  local caption

  original_name="$(basename "$file")"
  caption="Encrypted: NO (video/image)
File: ${rel_path}
Name: ${original_name}
Time: $(date '+%Y-%m-%d %H:%M:%S')"

  send_to_telegram "$file" "$caption" "" "$file"
}

send_encrypted_file() {
  local file="$1"
  local rel_path="$2"
  local work_dir
  local work_id
  local enc_file
  local original_name
  local upload_name
  local caption

  work_dir="$(dirname "$file")"
  work_id="$(sha256_text "$file|$PASS_HASH" | cut -c1-16)" || return 1
  enc_file="${work_dir}/.telegram-upload-${work_id}.enc"

  original_name="$(basename "$file")"
  upload_name="${original_name}.enc"
  upload_name="${upload_name//$'\n'/_}"
  upload_name="${upload_name//$'\r'/_}"
  upload_name="${upload_name//;/_}"

  caption="Encrypted: YES
File: ${rel_path}
Name: ${upload_name}
Encypt Hint: ${TELEGRAM_ENCRYPT_PASSWORD}45same
Time: $(date '+%Y-%m-%d %H:%M:%S')"

  if ! openssl enc -aes-256-cbc -salt -pbkdf2 -in "$file" -out "$enc_file" -pass "pass:${ENCRYPT_PASSWORD_COMBINED}" >/dev/null 2>&1; then
    echo "Encrypt failed: $file" >&2
    rm -f -- "$enc_file"
    return 1
  fi

  if ! send_to_telegram "$enc_file" "$caption" "$upload_name" "$file"; then
    rm -f -- "$enc_file"
    return 1
  fi

  rm -f -- "$enc_file"
  return 0
}

load_env_file

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_DIR="${SYNC_DIR:-sync-telegram}"
STATE_FILE=""
STORE_FILE_NAME="all-store-telegram.txt"
STORE_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dir)
      [[ $# -lt 2 ]] && { echo "Missing value for $1" >&2; exit 1; }
      SYNC_DIR="$2"
      shift 2
      ;;
    --state-file)
      [[ $# -lt 2 ]] && { echo "Missing value for $1" >&2; exit 1; }
      STATE_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      SYNC_DIR="$1"
      shift
      ;;
  esac
done

BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-${BOT_TOKEN:-}}"
CHAT_ID="${TELEGRAM_CHAT_ID:-${TELEGRAM_GROUP_CHAT_ID:-${CHAT_ID:-}}}"
API_BASE_URL="${TELEGRAM_API_BASE_URL:-https://api.telegram.org}"
FALLBACK_API_BASE_URL="${TELEGRAM_FALLBACK_API_BASE_URL:-}"
PART_A="${TELEGRAM_ENCRYPT_PASSWORD:-}"
PART_B="${SECRET_45:-}"
PART_C="${SECRET_SAME:-}"

SEND_DELAY_SEC="$(to_positive_int_or_default "${TELEGRAM_SEND_DELAY_SEC:-1}" 1)"
MAX_RETRIES="$(to_positive_int_or_default "${TELEGRAM_MAX_RETRIES:-3}" 3)"
RETRY_BASE_SEC="$(to_positive_int_or_default "${TELEGRAM_RETRY_BASE_SEC:-2}" 2)"
SYNC_INCLUDE_HIDDEN="${SYNC_INCLUDE_HIDDEN:-false}"
MOVE_TO_TRASH="$(to_bool_or_default "${SYNC_MOVE_TO_TRASH:-true}" "true")"
TRASH_DIR="${TRASH_DIR:-$HOME/.Trash}"
LOG_ERRORS="$(to_bool_or_default "${TELEGRAM_LOG_ERRORS:-true}" "true")"
ERROR_LOG_FILE="${TELEGRAM_ERROR_LOG_FILE:-$SCRIPT_DIR/telegram-sync-error.log}"

if [[ -z "${BOT_TOKEN}" ]]; then
  echo "Missing TELEGRAM_BOT_TOKEN in environment or .env" >&2
  exit 1
fi

if [[ -z "${CHAT_ID}" ]]; then
  echo "Missing TELEGRAM_CHAT_ID in environment or .env" >&2
  exit 1
fi

TELEGRAM_API_URL="$(build_bot_api_url "$API_BASE_URL" "$BOT_TOKEN")"
if [[ -n "$FALLBACK_API_BASE_URL" ]]; then
  TELEGRAM_FALLBACK_API_URL="$(build_bot_api_url "$FALLBACK_API_BASE_URL" "$BOT_TOKEN")"
fi

if [[ -z "${PART_A}" || -z "${PART_B}" || -z "${PART_C}" ]]; then
  echo "Missing encryption parts. Set TELEGRAM_ENCRYPT_PASSWORD, SECRET_45, and SECRET_SAME." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Missing required command: curl" >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "Missing required command: openssl" >&2
  exit 1
fi

ENCRYPT_PASSWORD_COMBINED="${PART_A}${PART_B}${PART_C}"
PASS_HASH="$(sha256_text "$ENCRYPT_PASSWORD_COMBINED")" || exit 1

mkdir -p "$SYNC_DIR"
SYNC_DIR="$(cd "$SYNC_DIR" && pwd)"

if [[ -z "$STATE_FILE" ]]; then
  STATE_FILE="$SYNC_DIR/.telegram-sync-state"
fi
STORE_FILE="$SCRIPT_DIR/$STORE_FILE_NAME"

touch "$STATE_FILE"
touch "$STORE_FILE"
if [[ "$LOG_ERRORS" == "true" ]]; then
  mkdir -p "$(dirname "$ERROR_LOG_FILE")"
  touch "$ERROR_LOG_FILE"
  log_message "INFO" "start sync_dir=${SYNC_DIR} api_base_url=${API_BASE_URL} fallback_api_base_url=${FALLBACK_API_BASE_URL:-none}"
fi

files=()
if [[ "$SYNC_INCLUDE_HIDDEN" == "true" ]]; then
  while IFS= read -r -d '' file; do
    files+=("$file")
  done < <(find "$SYNC_DIR" -type f \
    ! -name ".telegram-sync-state" \
    ! -name ".gitkeep" \
    ! -name "$STORE_FILE_NAME" \
    ! -name ".telegram-upload-*.enc" \
    -print0)
else
  while IFS= read -r -d '' file; do
    files+=("$file")
  done < <(find "$SYNC_DIR" -type f \
    ! -name ".*" \
    ! -name "$STORE_FILE_NAME" \
    ! -name ".telegram-upload-*.enc" \
    -print0)
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No files found in: $SYNC_DIR"
  exit 0
fi

sent_count=0
skip_count=0
fail_count=0

for file in "${files[@]}"; do
  rel_path="${file#$SYNC_DIR/}"
  file_hash="$(sha256_file "$file")" || { fail_count=$((fail_count + 1)); continue; }

  if is_media_file "$(basename "$file")"; then
    state_key="${rel_path}|${file_hash}|plain"
  else
    state_key="${rel_path}|${file_hash}|enc|${PASS_HASH}"
  fi

  if grep -Fqx -- "$state_key" "$STATE_FILE"; then
    skip_count=$((skip_count + 1))
    continue
  fi

  if is_media_file "$(basename "$file")"; then
    if send_plain_file "$file" "$rel_path"; then
      echo "$state_key" >> "$STATE_FILE"
      printf -- "- %s\n" "$(basename "$file")" >> "$STORE_FILE"
      if [[ "$MOVE_TO_TRASH" == "true" ]]; then
        move_to_trash "$file" || true
      fi
      sent_count=$((sent_count + 1))
      echo "Sent (plain media): $rel_path"
    else
      fail_count=$((fail_count + 1))
    fi
  else
    if send_encrypted_file "$file" "$rel_path"; then
      echo "$state_key" >> "$STATE_FILE"
      printf -- "- %s\n" "$(basename "$file")" >> "$STORE_FILE"
      if [[ "$MOVE_TO_TRASH" == "true" ]]; then
        move_to_trash "$file" || true
      fi
      sent_count=$((sent_count + 1))
      echo "Sent (encrypted): $rel_path"
    else
      fail_count=$((fail_count + 1))
    fi
  fi
done

echo "Done. Sent=$sent_count Skipped=$skip_count Failed=$fail_count"
log_message "INFO" "done sent=${sent_count} skipped=${skip_count} failed=${fail_count}"
[[ $fail_count -eq 0 ]]
