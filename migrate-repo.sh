#!/usr/bin/env bash
# Move old repo history to a new GitHub repo.
# Usage: ./migrate-repo.sh <old-repo-path> <new-repo-url>

set -e

OLD_REPO="$1"
NEW_URL="$2"

# Both inputs are required
if [ -z "$OLD_REPO" ] || [ -z "$NEW_URL" ]; then
  echo "Usage: ./migrate-repo.sh <old-repo-path> <new-repo-url>"
  exit 1
fi

cd "$OLD_REPO"

# Rename old origin (ignore if it does not exist)
git remote rename origin old-origin 2>/dev/null || true

# Add the new repo
git remote add origin "$NEW_URL"

# Push all branches and tags
git push -u origin --all
git push origin --tags

echo "Done!"