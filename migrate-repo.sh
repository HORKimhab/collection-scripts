#!/usr/bin/env bash
# Move current repo history to a new GitHub repo.
# Usage: ./migrate-repo.sh [new-repo-url]

set -e

NEW_URL="$1"

# If no URL was passed, ask for it until the user types one
while [ -z "$NEW_URL" ]; do
  read -r -p "Enter new repo URL (required): " NEW_URL
done

# Rename old origin (ignore if it does not exist)
git remote rename origin old-origin 2>/dev/null || true

# Add the new repo
git remote add origin "$NEW_URL"

# Push all branches and tags
git push -u origin --all
git push origin --tags

echo "Done!"