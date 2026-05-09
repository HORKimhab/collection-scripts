#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
PLAYLIST_FILE="$SCRIPT_DIR/playlists.txt"
EMAIL_FILE="$SCRIPT_DIR/emails.txt"
OUTPUT_ROOT="$SCRIPT_DIR/output"
TIMESTAMP="${TIMESTAMP_OVERRIDE:-$(date +%Y%m%d-%H%M%S)}"
RUN_DIR="$OUTPUT_ROOT/$TIMESTAMP"
REPORT_PATH="$RUN_DIR/report.json"

usage() {
  cat <<'EOF'
Usage:
  bash share-private-yt.sh report
  bash share-private-yt.sh share
  bash share-private-yt.sh install-automation

Commands:
  report               Generate playlist/video report via YouTube Data API
  share                Generate report, then automate "Share privately" in YouTube Studio
  install-automation   Install Node dependencies for browser automation
EOF
}

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "Missing file: $path" >&2
    exit 1
  fi
}

load_env() {
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    set -a
    source "$ENV_FILE"
    set +a
  fi
}

run_report() {
  mkdir -p "$RUN_DIR"
  python "$SCRIPT_DIR/scripts/youtube_report.py" \
    --playlist-file "$PLAYLIST_FILE" \
    --emails-file "$EMAIL_FILE" \
    --output-dir "$RUN_DIR"
}

find_existing_report() {
  if [[ -n "${REPORT_JSON_PATH:-}" && -f "${REPORT_JSON_PATH:-}" ]]; then
    printf '%s\n' "$REPORT_JSON_PATH"
    return 0
  fi

  local latest
  latest="$(find "$OUTPUT_ROOT" -type f -name report.json 2>/dev/null | sort | tail -n 1 || true)"
  if [[ -n "$latest" ]]; then
    printf '%s\n' "$latest"
    return 0
  fi

  return 1
}

run_share() {
  if [[ "${YT_REFRESH_REPORT_BEFORE_SHARE:-1}" != "0" ]]; then
    run_report
  else
    REPORT_PATH="$(find_existing_report || true)"
  fi

  if [[ ! -f "$REPORT_PATH" ]]; then
    echo "Report not found: $REPORT_PATH" >&2
    echo "Run 'bash share-private-yt.sh report' first, set REPORT_JSON_PATH, or keep YT_REFRESH_REPORT_BEFORE_SHARE=1." >&2
    exit 1
  fi

  node "$SCRIPT_DIR/scripts/share_private_videos.mjs" "$REPORT_PATH"
}

main() {
  local command="${1:-}"
  if [[ -z "$command" ]]; then
    usage
    exit 1
  fi

  load_env

  case "$command" in
    report)
      require_file "$PLAYLIST_FILE"
      require_file "$EMAIL_FILE"
      run_report
      ;;
    share)
      require_file "$PLAYLIST_FILE"
      require_file "$EMAIL_FILE"
      run_share
      ;;
    install-automation)
      (cd "$SCRIPT_DIR" && npm install)
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
