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
  Download media from a source Telegram channel message range, split files >1.95GB,
  upload to TELEGRAM_CHAT_ID, and keep idempotent state.

Options:
  -d, --dir <path>               Working folder (default: sync-telegram)
  --state-file <path>            Custom state file
  --source-chat-id <ref>         Source chat ref (ID or web URL)
  --d-from <ref>                 Start message ref (ID or t.me URL)
  --d-end <ref>                  End message ref (ID or t.me URL)
  --split-max-bytes <bytes>      Split threshold (default: 1950000000)
  -h, --help                     Show this help

Environment variables:
  TELEGRAM_BOT_TOKEN
  TELEGRAM_CHAT_ID
  TELEGRAM_FALLBACK_API_BASE_URL  (required for this workflow)
  TELEGRAM_SOURCE_CHAT_ID          (optional, default: https://web.telegram.org/a/#-1002482766032)
  TELEGRAM_DFROM                   (optional, default: https://t.me/UdemyPieFiles/3710)
  TELEGRAM_DEND                    (optional, default: https://t.me/UdemyPieFiles/3804)
  TELEGRAM_SPLIT_MAX_BYTES         (optional, default: 1950000000)
  TELEGRAM_SEND_DELAY_SEC          (optional, default: 1)
  TELEGRAM_MAX_RETRIES             (optional, default: 3)
  TELEGRAM_RETRY_BASE_SEC          (optional, default: 2)
  SYNC_MOVE_TO_TRASH               (optional: true/false, default: true)
  TRASH_DIR                        (optional, default: $HOME/.Trash)
  TELEGRAM_LOG_ERRORS              (optional: true/false, default: true)
  TELEGRAM_ERROR_LOG_FILE          (optional, default: <script_dir>/telegram-sync-error.log)
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

  # Accept only positive integer strings.
  if [[ "$value" =~ ^[0-9]+$ ]] && [[ "$value" -gt 0 ]]; then
    # Valid input path.
    printf '%s' "$value"
  else
    # Invalid input path.
    printf '%s' "$fallback"
  fi
}

# Convert to boolean string or fallback.
to_bool_or_default() {
  local value="$1"
  local fallback="$2"
  local lower
  # Normalize once for stable matching.
  lower="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"

  case "$lower" in
    # Truthy aliases.
    true|1|yes|y) printf 'true' ;;
    # Falsy aliases.
    false|0|no|n) printf 'false' ;;
    # Unknown value: keep fallback.
    *) printf '%s' "$fallback" ;;
  esac
}

# Build Telegram bot API base path from server URL + token.
build_bot_api_url() {
  local base_url="$1"
  local token="$2"

  # Trim trailing slashes to avoid `//` in URLs.
  while [[ "$base_url" == */ ]]; do
    base_url="${base_url%/}"
  done

  # Compose method endpoint prefix.
  printf '%s/bot%s' "$base_url" "$token"
}

# Build Telegram file API base path from server URL + token.
build_file_api_url() {
  local base_url="$1"
  local token="$2"

  # Trim trailing slashes to avoid `//` in URLs.
  while [[ "$base_url" == */ ]]; do
    base_url="${base_url%/}"
  done

  # Compose file download endpoint prefix.
  printf '%s/file/bot%s' "$base_url" "$token"
}

# Return SHA256 for a file; supports macOS and Linux.
sha256_file() {
  local file="$1"

  # Prefer `shasum` on macOS.
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  # Fallback to Linux `sha256sum`.
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    # No hashing tool available.
    echo "Missing hash tool: install shasum or sha256sum" >&2
    return 1
  fi
}

# Return SHA256 for a text input; supports macOS and Linux.
sha256_text() {
  local text="$1"

  # Prefer `shasum` on macOS.
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$text" | shasum -a 256 | awk '{print $1}'
  # Fallback to Linux `sha256sum`.
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$text" | sha256sum | awk '{print $1}'
  else
    # No hashing tool available.
    echo "Missing hash tool: install shasum or sha256sum" >&2
    return 1
  fi
}

# Get file size in bytes on both macOS/Linux.
file_size_bytes() {
  local file="$1"

  # macOS syntax.
  if stat -f '%z' "$file" >/dev/null 2>&1; then
    stat -f '%z' "$file"
  else
    # Linux syntax.
    stat -c '%s' "$file"
  fi
}

# Read message ID from numeric value or URL suffix.
parse_message_id_ref() {
  local ref="$1"

  # Already a numeric ID.
  if [[ "$ref" =~ ^[0-9]+$ ]]; then
    printf '%s' "$ref"
    return 0
  fi

  # Extract trailing numeric ID from URL.
  if [[ "$ref" =~ /([0-9]+)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi

  # Return empty on unsupported format.
  printf ''
}

# Read source chat ID from raw numeric ID or web URL.
parse_source_chat_id_ref() {
  local ref="$1"

  # Already a numeric chat ID.
  if [[ "$ref" =~ ^-?[0-9]+$ ]]; then
    printf '%s' "$ref"
    return 0
  fi

  # Extract chat ID from hash fragment form.
  if [[ "$ref" =~ \#(-?[0-9]+)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi

  # Extract trailing numeric fallback.
  if [[ "$ref" =~ /(-?[0-9]+)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi

  # Return empty on unsupported format.
  printf ''
}

# Replace problematic characters for local file naming.
sanitize_filename() {
  local name="$1"

  # Remove path separators.
  name="${name//\//_}"
  # Remove line breaks.
  name="${name//$'\n'/_}"
  name="${name//$'\r'/_}"
  # Remove characters that can break filesystem handling.
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

# Write log line when error logging is enabled.
log_message() {
  local level="$1"
  local message="$2"

  # Skip all writes if logging is disabled.
  if [[ "$LOG_ERRORS" != "true" ]]; then
    return 0
  fi

  # Append a timestamped one-line entry.
  printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$message" >> "$ERROR_LOG_FILE"
}

# Move file to trash; fallback naming avoids collisions.
move_to_trash() {
  local file="$1"
  local base
  local target

  # Nothing to do if file does not exist.
  [[ ! -e "$file" ]] && return 0

  # Ensure trash directory exists before move.
  mkdir -p "$TRASH_DIR" 2>/dev/null || {
    echo "Warning: cannot access trash dir: $TRASH_DIR" >&2
    return 1
  }

  # Build destination path in trash.
  base="$(basename "$file")"
  target="$TRASH_DIR/$base"

  # Avoid overwriting existing file in trash.
  if [[ -e "$target" ]]; then
    target="$TRASH_DIR/${base}.$(date +%Y%m%d-%H%M%S)"
  fi

  # Move source file into trash directory.
  mv -- "$file" "$target" 2>/dev/null || {
    echo "Warning: failed moving to trash: $file" >&2
    return 1
  }

  return 0
}

# -----------------------------
# State handling (performance)
# -----------------------------

# In-memory state index to avoid repeated grep over large state files.
declare -A STATE_INDEX=()

# Load all state lines into associative array once.
state_load() {
  local line=""

  # Read every saved state line and index non-empty keys in memory.
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    STATE_INDEX["$line"]=1
  done < "$STATE_FILE"
}

# Check if a state key already exists.
state_has() {
  local key="$1"
  # Associative-array existence check.
  [[ -n "${STATE_INDEX[$key]+x}" ]]
}

# Persist and index a new state key.
state_add() {
  local key="$1"

  # Skip duplicate keys to keep state file clean.
  if state_has "$key"; then
    return 0
  fi

  # Persist new key to both file and memory cache.
  printf '%s\n' "$key" >> "$STATE_FILE"
  STATE_INDEX["$key"]=1
}

# -----------------------------
# Telegram API helpers
# -----------------------------

# Shared holder for API responses from helper functions.
API_LAST_RESPONSE=""

# Extract retry_after from Telegram JSON response (if any).
read_retry_after_seconds() {
  local response="$1"
  # Extract Telegram `retry_after` hint if provided.
  jq -r '.parameters.retry_after // empty' <<<"$response" 2>/dev/null | head -n 1
}

# Call JSON Telegram API method with retries.
telegram_api_post_json() {
  local method="$1"
  local payload="$2"
  local label="$3"
  local attempt=1
  local response=""
  local curl_exit=1
  local retry_after=""
  local sleep_sec=0
  local compact_response=""

  # Retry JSON API calls to handle transient failures.
  while [[ $attempt -le $MAX_RETRIES ]]; do
    # Send JSON payload to requested Bot API method.
    response="$(curl -sS -X POST "${TELEGRAM_API_URL}/${method}" \
      -H "Content-Type: application/json" \
      -d "$payload" 2>&1)"
    # Capture transport-level status.
    curl_exit=$?

    # Normalize response for one-line logs.
    compact_response="${response//$'\n'/ }"
    compact_response="${compact_response//$'\r'/ }"

    # Success path: HTTP transport ok and API says ok=true.
    if [[ $curl_exit -eq 0 ]] && jq -e '.ok == true' >/dev/null 2>&1 <<<"$response"; then
      API_LAST_RESPONSE="$response"
      return 0
    fi

    # Failure path: keep visibility in logs.
    log_message "WARN" "attempt=${attempt}/${MAX_RETRIES} method=${method} label=${label} curl_exit=${curl_exit} response=${compact_response}"

    # Honor Telegram-provided backoff when available.
    retry_after="$(read_retry_after_seconds "$response")"
    if [[ -n "$retry_after" ]]; then
      sleep_sec="$retry_after"
    else
      # Fallback backoff grows with attempt count.
      sleep_sec=$((RETRY_BASE_SEC * attempt))
    fi

    # Sleep only when another retry is pending.
    if [[ $attempt -lt $MAX_RETRIES ]]; then
      sleep "$sleep_sec"
    fi

    # Advance retry counter.
    attempt=$((attempt + 1))
  done

  # Preserve final response for caller diagnostics.
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
  local response=""
  local curl_exit=1
  local retry_after=""
  local sleep_sec=0
  local compact_response=""

  # Fail fast when source file cannot be read.
  if [[ ! -r "$file_path" ]]; then
    echo "Upload file is not readable: $label" >&2
    log_message "ERROR" "upload_not_readable label=${label}"
    return 1
  fi

  # Retry sendDocument requests to handle transient failures.
  while [[ $attempt -le $MAX_RETRIES ]]; do
    # Upload file as multipart/form-data.
    response="$(curl -sS -X POST "${TELEGRAM_API_URL}/sendDocument" \
      -F "chat_id=${CHAT_ID}" \
      -F "caption=${caption}" \
      -F "document=@${file_path};filename=${upload_name}" 2>&1)"
    # Capture transport-level status.
    curl_exit=$?

    # Normalize response for one-line logs.
    compact_response="${response//$'\n'/ }"
    compact_response="${compact_response//$'\r'/ }"

    # Success path: HTTP transport ok and API says ok=true.
    if [[ $curl_exit -eq 0 ]] && jq -e '.ok == true' >/dev/null 2>&1 <<<"$response"; then
      # Delay between sends helps reduce rate-limit hits.
      sleep "$SEND_DELAY_SEC"
      return 0
    fi

    # Curl 26 means local read error, retries are not useful.
    if [[ $curl_exit -eq 26 ]]; then
      echo "Cannot read file for upload: $label" >&2
      log_message "ERROR" "upload_read_error_26 label=${label}"
      break
    fi

    # Log failed attempt details.
    log_message "WARN" "attempt=${attempt}/${MAX_RETRIES} send label=${label} curl_exit=${curl_exit} response=${compact_response}"

    # Honor Telegram-provided backoff when available.
    retry_after="$(read_retry_after_seconds "$response")"
    if [[ -n "$retry_after" ]]; then
      sleep_sec="$retry_after"
    else
      # Fallback backoff grows with attempt count.
      sleep_sec=$((RETRY_BASE_SEC * attempt))
    fi

    # Sleep only when another retry is pending.
    if [[ $attempt -lt $MAX_RETRIES ]]; then
      echo "Retry send (${attempt}/${MAX_RETRIES}) after ${sleep_sec}s: $label" >&2
      sleep "$sleep_sec"
    fi

    # Advance retry counter.
    attempt=$((attempt + 1))
  done

  # Final failure after all retries.
  echo "Telegram send failed: $label" >&2
  log_message "ERROR" "final_send_failed label=${label} response=${compact_response}"
  return 1
}

# Download binary file from Telegram by file_id (getFile + file URL).
telegram_download_file_by_id() {
  local file_id="$1"
  local destination="$2"
  local label="$3"
  local payload=""
  local file_path=""
  local download_url=""
  local tmp_file="${destination}.part"
  local attempt=1
  local curl_exit=1
  local sleep_sec=0

  # Resolve server file path from file_id.
  payload="$(jq -nc --arg file_id "$file_id" '{file_id:$file_id}')"
  if ! telegram_api_post_json "getFile" "$payload" "$label"; then
    echo "getFile failed for: $label" >&2
    log_message "ERROR" "getFile_failed label=${label} response=${API_LAST_RESPONSE//$'\n'/ }"
    return 1
  fi

  # Read resolved file path from API response.
  file_path="$(jq -r '.result.file_path // empty' <<<"$API_LAST_RESPONSE")"
  if [[ -z "$file_path" ]]; then
    echo "Missing file_path for: $label" >&2
    return 1
  fi

  # Build download URL and clear stale temp artifact.
  download_url="${TELEGRAM_FILE_API_URL}/${file_path}"
  rm -f -- "$tmp_file"

  # Retry download for transient issues.
  while [[ $attempt -le $MAX_RETRIES ]]; do
    # Download to temporary file first for atomic final move.
    curl -sS -L --fail "$download_url" --output "$tmp_file"
    curl_exit=$?

    # Success path: non-empty downloaded file.
    if [[ $curl_exit -eq 0 && -s "$tmp_file" ]]; then
      mv -- "$tmp_file" "$destination"
      # Delay before next operation.
      sleep "$SEND_DELAY_SEC"
      return 0
    fi

    # Compute fallback backoff.
    sleep_sec=$((RETRY_BASE_SEC * attempt))
    # Sleep only when another retry is pending.
    if [[ $attempt -lt $MAX_RETRIES ]]; then
      echo "Retry download (${attempt}/${MAX_RETRIES}) after ${sleep_sec}s: $label" >&2
      sleep "$sleep_sec"
    fi

    # Advance retry counter.
    attempt=$((attempt + 1))
  done

  # Remove partial file after final failure.
  rm -f -- "$tmp_file"
  log_message "ERROR" "download_failed label=${label} url=${download_url}"
  return 1
}

# -----------------------------
# Message parsing helpers
# -----------------------------

# Fetch one source message; try getMessage first, then getChatHistory fallback.
fetch_message_json() {
  local message_id="$1"
  local payload=""
  local message_json=""

  # First attempt: direct lookup by exact message ID.
  payload="$(jq -nc --arg chat_id "$SOURCE_CHAT_ID" --argjson message_id "$message_id" '{chat_id:$chat_id, message_id:$message_id}')"
  if telegram_api_post_json "getMessage" "$payload" "message_id=${message_id}"; then
    # Extract raw result payload from API response.
    message_json="$(jq -c '.result' <<<"$API_LAST_RESPONSE")"
    # Accept only non-empty, non-null message payloads.
    if [[ -n "$message_json" && "$message_json" != "null" ]]; then
      printf '%s' "$message_json"
      return 0
    fi
  fi

  # Second attempt: small history window around target message.
  payload="$(jq -nc --arg chat_id "$SOURCE_CHAT_ID" --argjson from_message_id "$message_id" '{chat_id:$chat_id, from_message_id:$from_message_id, offset:0, limit:20, only_local:false}')"
  if telegram_api_post_json "getChatHistory" "$payload" "message_id=${message_id}"; then
    # Try exact message match first, then first entry fallback.
    message_json="$(jq -c --argjson message_id "$message_id" '
      (
        if (.result.messages | type) == "array" then .result.messages
        elif (.result | type) == "array" then .result
        else []
        end
      ) as $messages
      | ($messages | map(select((.message_id // .id // -1) == $message_id)) | .[0])
        // ($messages | .[0] // empty)
    ' <<<"$API_LAST_RESPONSE")"

    # Accept only non-empty, non-null message payloads.
    if [[ -n "$message_json" && "$message_json" != "null" ]]; then
      printf '%s' "$message_json"
      return 0
    fi
  fi

  # No message could be fetched from either method.
  return 1
}

# Extract media identifiers (file_id, file_unique_id, file_name) from a message JSON.
extract_message_file_fields() {
  local message_json="$1"
  local message_id="$2"

  jq -r --arg mid "$message_id" '
    def pick(xs): (xs | map(select(. != null and . != "")) | .[0] // "");
    {
      file_id: pick([
        .document.file_id,
        .video.file_id,
        .audio.file_id,
        .voice.file_id,
        .animation.file_id,
        .video_note.file_id,
        .sticker.file_id,
        (if (.photo | type) == "array" and (.photo | length) > 0 then .photo[-1].file_id else empty end)
      ]),
      file_unique_id: pick([
        .document.file_unique_id,
        .video.file_unique_id,
        .audio.file_unique_id,
        .voice.file_unique_id,
        .animation.file_unique_id,
        .video_note.file_unique_id,
        .sticker.file_unique_id,
        (if (.photo | type) == "array" and (.photo | length) > 0 then .photo[-1].file_unique_id else empty end)
      ]),
      file_name: pick([
        .document.file_name,
        .video.file_name,
        .audio.file_name,
        .animation.file_name
      ]),
      mime_type: pick([
        .document.mime_type,
        .video.mime_type,
        .audio.mime_type,
        .animation.mime_type
      ]),
      is_photo: ((.photo | type) == "array" and (.photo | length) > 0)
    }
    | if .file_name == "" then
        .file_name = ("message-" + $mid + "." + (
          if .is_photo then "jpg"
          elif (.mime_type | startswith("video/")) then "mp4"
          elif (.mime_type | startswith("audio/")) then "mp3"
          elif (.mime_type | startswith("image/")) then "jpg"
          else "bin"
          end
        ))
      else . end
    | [.file_id, .file_unique_id, .file_name] | @tsv
  ' <<<"$message_json"
}

# -----------------------------
# Split / send / cleanup helpers
# -----------------------------

# Return a list of files to send (single file or split parts).
# Existing parts are reused to avoid repeated split work.
collect_files_to_send() {
  local file_path="$1"
  local size=0
  local split_prefix=""
  local parts=()

  # Get file size to choose split vs direct send.
  size="$(file_size_bytes "$file_path")" || return 1

  # Small file path: send one file only.
  if [[ "$size" -le "$SPLIT_SIZE_BYTES" ]]; then
    printf '%s\n' "$file_path"
    return 0
  fi

  # Part files use deterministic suffix pattern.
  split_prefix="${file_path}.part."

  # Reuse split outputs if they already exist.
  shopt -s nullglob
  parts=("${split_prefix}"*)
  shopt -u nullglob

  # Create parts when not present.
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

  # No parts indicates split failure.
  [[ ${#parts[@]} -eq 0 ]] && return 1
  # Return one path per line for caller mapfile.
  printf '%s\n' "${parts[@]}"
}

# Send one source file with split-aware idempotent state (per part hash).
send_file_with_split_state() {
  local message_id="$1"
  local source_file="$2"
  local files_to_send=()
  local total=0
  local idx=1
  local item=""
  local item_hash=""
  local part_state_key=""
  local caption=""

  # Build sending list (single file or split parts).
  mapfile -t files_to_send < <(collect_files_to_send "$source_file") || return 1
  total="${#files_to_send[@]}"
  # Guard against empty send list.
  [[ "$total" -eq 0 ]] && return 1

  # Send in stable order so retries are predictable.
  for item in "${files_to_send[@]}"; do
    # Hash in key ensures changed part contents will be resent when needed.
    item_hash="$(sha256_file "$item")" || return 1
    part_state_key="channel|${SOURCE_CHAT_ID}|${message_id}|part|${idx}/${total}|${item_hash}|sent"

    # Skip part already sent in previous run.
    if state_has "$part_state_key"; then
      # Already sent part: skip and move on.
      idx=$((idx + 1))
      continue
    fi

    # Build useful caption for traceability.
    caption="Source Chat: ${SOURCE_CHAT_ID}
Source Message ID: ${message_id}
Part: ${idx}/${total}
File: $(basename "$source_file")
Time: $(date '+%Y-%m-%d %H:%M:%S')"

    # Send part and persist state only after success.
    if ! telegram_send_document "$item" "$caption" "$(basename "$item")" "$item"; then
      return 1
    fi

    # Mark this exact part-content as sent.
    state_add "$part_state_key"
    # Increment 1-based part index.
    idx=$((idx + 1))
  done

  # All parts sent.
  return 0
}

# Cleanup local artifacts for a message using shell glob for speed.
cleanup_message_artifacts() {
  local message_id="$1"
  local path=""

  # Avoid literal glob text when there are no matches.
  shopt -s nullglob
  # Match message-local base file and split parts.
  for path in "$SYNC_DIR"/msg-"$message_id"-*; do
    # Keep old behavior: move to trash when enabled.
    if [[ "$MOVE_TO_TRASH" == "true" ]]; then
      move_to_trash "$path" || true
    else
      # Delete immediately only when trash mode is disabled.
      rm -f -- "$path"
    fi
  done
  # Restore shell behavior after cleanup.
  shopt -u nullglob
}

# -----------------------------
# Core per-message workflow
# -----------------------------

# Process one message ID end-to-end:
# fetch -> detect media -> download (once) -> split -> send (once) -> mark sent -> cleanup.
process_message() {
  local message_id="$1"
  local message_json=""
  local fields=""
  local file_id=""
  local file_unique_id=""
  local file_name=""
  local safe_name=""
  local local_file=""

  local sent_key="channel|${SOURCE_CHAT_ID}|${message_id}|sent"
  local no_media_key="channel|${SOURCE_CHAT_ID}|${message_id}|no_media"

  # If already fully sent, keep old behavior: cleanup local artifacts and skip.
  if state_has "$sent_key"; then
    cleanup_message_artifacts "$message_id"
    skip_count=$((skip_count + 1))
    return 0
  fi

  # If already known as no-media, skip quickly.
  if state_has "$no_media_key"; then
    skip_count=$((skip_count + 1))
    return 0
  fi

  # Fetch message from source channel.
  message_json="$(fetch_message_json "$message_id")" || {
    echo "Failed fetching source message: ${message_id}" >&2
    log_message "ERROR" "fetch_message_failed message_id=${message_id}"
    fail_count=$((fail_count + 1))
    return 1
  }

  # Extract main file metadata from the message.
  fields="$(extract_message_file_fields "$message_json" "$message_id")"
  IFS=$'\t' read -r file_id file_unique_id file_name <<<"$fields"

  # Mark no-media messages so reruns do not fetch repeatedly.
  if [[ -z "$file_id" ]]; then
    # Persist no-media marker for future runs.
    state_add "$no_media_key"
    skip_count=$((skip_count + 1))
    return 0
  fi

  # Build deterministic local path per message and file.
  safe_name="$(sanitize_filename "$file_name")"
  # Use fallback filename when source has no name.
  [[ -z "$safe_name" ]] && safe_name="message-${message_id}.bin"

  # Build fallback unique id when Telegram does not provide one.
  if [[ -z "$file_unique_id" ]]; then
    file_unique_id="$(sha256_text "${SOURCE_CHAT_ID}|${message_id}|${safe_name}" | cut -c1-16)"
  fi

  local_file="${SYNC_DIR}/msg-${message_id}-${file_unique_id}-${safe_name}"

  # Track successful downloads separately from send state.
  local download_key="channel|${SOURCE_CHAT_ID}|${message_id}|downloaded|${file_unique_id}"

  # Download only when not already downloaded or missing on disk.
  if ! state_has "$download_key" || [[ ! -s "$local_file" ]]; then
    if ! telegram_download_file_by_id "$file_id" "$local_file" "message_id=${message_id}"; then
      echo "Download failed for message: ${message_id}" >&2
      fail_count=$((fail_count + 1))
      return 1
    fi
    # Persist successful download marker.
    state_add "$download_key"
  fi

  # Send file (or parts), then mark message as sent.
  if send_file_with_split_state "$message_id" "$local_file"; then
    # Persist message-level completion marker.
    state_add "$sent_key"
    # Append short send history line.
    printf -- "- %s\n" "$(basename "$local_file")" >> "$STORE_FILE"
    # Apply cleanup after successful full send.
    cleanup_message_artifacts "$message_id"
    # Increase success counter.
    sent_count=$((sent_count + 1))
    echo "Synced message ${message_id}: $(basename "$local_file")"
    return 0
  fi

  # Send failed; keep local downloaded file for retry later.
  echo "Send failed for message: ${message_id}" >&2
  fail_count=$((fail_count + 1))
  return 1
}

# -----------------------------
# Main
# -----------------------------

# Load environment first so CLI options can still override defaults.
load_env_file

# Resolve script path once for stable relative files.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default working values.
SYNC_DIR="${SYNC_DIR:-sync-telegram}"
STATE_FILE=""
STORE_FILE_NAME="all-store-telegram.txt"
STORE_FILE=""
SOURCE_CHAT_REF="${TELEGRAM_SOURCE_CHAT_ID:-https://web.telegram.org/a/#-1002482766032}"
DFROM_REF="${TELEGRAM_DFROM:-https://t.me/UdemyPieFiles/3710}"
DEND_REF="${TELEGRAM_DEND:-https://t.me/UdemyPieFiles/3804}"
SPLIT_SIZE_BYTES="$(to_positive_int_or_default "${TELEGRAM_SPLIT_MAX_BYTES:-1950000000}" 1950000000)"

# Parse CLI options.
while [[ $# -gt 0 ]]; do
  # Handle one option at a time.
  case "$1" in
    -d|--dir)
      # Ensure option has value.
      [[ $# -lt 2 ]] && { echo "Missing value for $1" >&2; exit 1; }
      # Override default working directory.
      SYNC_DIR="$2"
      shift 2
      ;;
    --state-file)
      # Ensure option has value.
      [[ $# -lt 2 ]] && { echo "Missing value for $1" >&2; exit 1; }
      # Override default state file location.
      STATE_FILE="$2"
      shift 2
      ;;
    --source-chat-id|--source-chat)
      # Ensure option has value.
      [[ $# -lt 2 ]] && { echo "Missing value for $1" >&2; exit 1; }
      # Override source chat reference.
      SOURCE_CHAT_REF="$2"
      shift 2
      ;;
    --d-from|--from-id)
      # Ensure option has value.
      [[ $# -lt 2 ]] && { echo "Missing value for $1" >&2; exit 1; }
      # Override start message reference.
      DFROM_REF="$2"
      shift 2
      ;;
    --d-end|--to-id)
      # Ensure option has value.
      [[ $# -lt 2 ]] && { echo "Missing value for $1" >&2; exit 1; }
      # Override end message reference.
      DEND_REF="$2"
      shift 2
      ;;
    --split-max-bytes)
      # Ensure option has value.
      [[ $# -lt 2 ]] && { echo "Missing value for $1" >&2; exit 1; }
      # Parse split threshold with positive-int fallback.
      SPLIT_SIZE_BYTES="$(to_positive_int_or_default "$2" "$SPLIT_SIZE_BYTES")"
      shift 2
      ;;
    -h|--help)
      # Print usage and exit successfully.
      usage
      exit 0
      ;;
    *)
      # Reject unknown option early.
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

# Read core environment variables.
BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-${BOT_TOKEN:-}}"
CHAT_ID="${TELEGRAM_CHAT_ID:-${TELEGRAM_GROUP_CHAT_ID:-${CHAT_ID:-}}}"
FALLBACK_API_BASE_URL="${TELEGRAM_FALLBACK_API_BASE_URL:-}"

# Read runtime tunables.
SEND_DELAY_SEC="$(to_positive_int_or_default "${TELEGRAM_SEND_DELAY_SEC:-1}" 1)"
MAX_RETRIES="$(to_positive_int_or_default "${TELEGRAM_MAX_RETRIES:-3}" 3)"
RETRY_BASE_SEC="$(to_positive_int_or_default "${TELEGRAM_RETRY_BASE_SEC:-2}" 2)"
MOVE_TO_TRASH="$(to_bool_or_default "${SYNC_MOVE_TO_TRASH:-true}" "true")"
TRASH_DIR="${TRASH_DIR:-$HOME/.Trash}"
LOG_ERRORS="$(to_bool_or_default "${TELEGRAM_LOG_ERRORS:-true}" "true")"
ERROR_LOG_FILE="${TELEGRAM_ERROR_LOG_FILE:-$SCRIPT_DIR/telegram-sync-error.log}"

# Validate required env values.
if [[ -z "$BOT_TOKEN" ]]; then
  # Bot token is mandatory for all Telegram API calls.
  echo "Missing TELEGRAM_BOT_TOKEN in environment or .env" >&2
  exit 1
fi

if [[ -z "$CHAT_ID" ]]; then
  # Destination chat is required for sendDocument.
  echo "Missing TELEGRAM_CHAT_ID in environment or .env" >&2
  exit 1
fi

if [[ -z "$FALLBACK_API_BASE_URL" ]]; then
  # This script intentionally uses fallback endpoint for all actions.
  echo "Missing TELEGRAM_FALLBACK_API_BASE_URL in environment or .env" >&2
  exit 1
fi

# Validate required tools.
if ! command -v curl >/dev/null 2>&1; then
  # Curl is used for all HTTP calls.
  echo "Missing required command: curl" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  # jq is used for JSON parsing and payload building.
  echo "Missing required command: jq" >&2
  exit 1
fi

if ! command -v split >/dev/null 2>&1; then
  # split is used for >1.95GB chunking.
  echo "Missing required command: split" >&2
  exit 1
fi

# Resolve source chat and message range.
SOURCE_CHAT_ID="$(parse_source_chat_id_ref "$SOURCE_CHAT_REF")"
FROM_ID="$(parse_message_id_ref "$DFROM_REF")"
TO_ID="$(parse_message_id_ref "$DEND_REF")"

if [[ -z "$SOURCE_CHAT_ID" ]]; then
  # Source chat reference must parse to numeric chat ID.
  echo "Invalid source chat reference: $SOURCE_CHAT_REF" >&2
  exit 1
fi

if [[ -z "$FROM_ID" || -z "$TO_ID" ]]; then
  # Start/end refs must parse to numeric message IDs.
  echo "Invalid dFrom/dEnd references." >&2
  exit 1
fi

if (( FROM_ID > TO_ID )); then
  # Enforce forward inclusive range.
  echo "Invalid range: dFrom (${FROM_ID}) must be <= dEnd (${TO_ID})." >&2
  exit 1
fi

# Build API URLs from fallback base only (as requested logic).
TELEGRAM_API_URL="$(build_bot_api_url "$FALLBACK_API_BASE_URL" "$BOT_TOKEN")"
TELEGRAM_FILE_API_URL="$(build_file_api_url "$FALLBACK_API_BASE_URL" "$BOT_TOKEN")"

# Prepare working paths and files.
mkdir -p "$SYNC_DIR"
SYNC_DIR="$(cd "$SYNC_DIR" && pwd)"

if [[ -z "$STATE_FILE" ]]; then
  # Default state file in working directory.
  STATE_FILE="$SYNC_DIR/.telegram-sync-state"
fi

STORE_FILE="$SCRIPT_DIR/$STORE_FILE_NAME"
touch "$STATE_FILE"
touch "$STORE_FILE"

# Ensure log file exists when logging is enabled.
if [[ "$LOG_ERRORS" == "true" ]]; then
  # Ensure log parent path exists before append.
  mkdir -p "$(dirname "$ERROR_LOG_FILE")"
  touch "$ERROR_LOG_FILE"
fi

# Load state index once for faster lookups.
state_load

# Log run metadata.
log_message "INFO" "start source_chat_id=${SOURCE_CHAT_ID} from=${FROM_ID} to=${TO_ID} split_max_bytes=${SPLIT_SIZE_BYTES} api_base_url=${FALLBACK_API_BASE_URL}"

# Counters for summary.
sent_count=0
skip_count=0
fail_count=0

# Process messages sequentially from from_id to to_id (inclusive).
for ((message_id=FROM_ID; message_id<=TO_ID; message_id++)); do
  # Keep batch running even if one message fails.
  process_message "$message_id" || true
done

# Print and log final summary.
echo "Done. Sent=${sent_count} Skipped=${skip_count} Failed=${fail_count}"
log_message "INFO" "done sent=${sent_count} skipped=${skip_count} failed=${fail_count}"

# Exit non-zero if any failures happened.
# This lets cron/CI detect partial failures.
[[ $fail_count -eq 0 ]]
