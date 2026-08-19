#!/usr/bin/env bash
# Need to record demo video via OBS record

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash clone-gitea-repo.sh --url=https://git.projectnightcrawler.dev/NightmareEclipse

Optional environment variables:
  GITEA_TOKEN   Personal access token for private repos or higher API limits

Options:
  --list-only    Print repository clone URLs without cloning or zipping
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
}

URL=""
LIST_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --url=*)
      URL="${arg#*=}"
      ;;
    --list-only)
      LIST_ONLY=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$URL" ]]; then
  echo "--url is required" >&2
  usage >&2
  exit 1
fi

require_cmd git
require_cmd curl
require_cmd zip
require_cmd python3

BASE_URL="${URL%/}"
OWNER="${BASE_URL##*/}"
HOST="${BASE_URL%/*}"
API_BASE="${HOST}/api/v1"
TIMESTAMP="$(date '+%Y-%m-%d-%H-%M')"
ARCHIVE_NAME="${OWNER}-${TIMESTAMP}.zip"

auth_args=()
if [[ -n "${GITEA_TOKEN:-}" ]]; then
  auth_args=(-H "Authorization: token ${GITEA_TOKEN}")
fi

fetch_repos() {
  local endpoint="$1"
  local page=1
  local per_page=100
  local count=0

  while :; do
    local response
    response="$(curl -fsSL "${auth_args[@]}" \
      "${API_BASE}/${endpoint}?limit=${per_page}&page=${page}")"

    python3 - "$response" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
if not isinstance(data, list):
    sys.exit(2)

for repo in data:
    clone_url = repo.get("clone_url")
    if clone_url:
        print(clone_url)
PY

    count="$(python3 - "$response" <<'PY'
import json
import sys
data = json.loads(sys.argv[1])
print(len(data) if isinstance(data, list) else -1)
PY
)"

    if [[ "$count" -lt "$per_page" ]]; then
      break
    fi

    page=$((page + 1))
  done
}

repo_urls=""
if repo_urls="$(fetch_repos "users/${OWNER}/repos" 2>/dev/null)"; then
  :
elif repo_urls="$(fetch_repos "orgs/${OWNER}/repos" 2>/dev/null)"; then
  :
else
  echo "Failed to fetch repositories for ${URL}" >&2
  echo "Check that the URL is a valid Gitea user/org page and that the repos are accessible." >&2
  exit 1
fi

if [[ -z "$repo_urls" ]]; then
  echo "No repositories found for ${URL}" >&2
  exit 1
fi

if [[ "$LIST_ONLY" -eq 1 ]]; then
  printf '%s\n' "$repo_urls"
  exit 0
fi

tmp_dir="$(mktemp -d)"
work_dir="${tmp_dir}/${OWNER}"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$work_dir"

while IFS= read -r repo_url; do
  [[ -z "$repo_url" ]] && continue
  echo "Cloning ${repo_url}"
  git clone --quiet "$repo_url" "${work_dir}/$(basename "${repo_url%.git}")"
done <<< "$repo_urls"

rm -f "$ARCHIVE_NAME"
(
  cd "$tmp_dir"
  zip -rq "$OLDPWD/$ARCHIVE_NAME" "$OWNER"
)

echo "Created archive: $ARCHIVE_NAME"
