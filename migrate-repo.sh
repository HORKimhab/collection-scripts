#!/usr/bin/env bash
# Move current repo history to a new GitHub repo.
# Usage: ./migrate-repo.sh [new-repo-url]
# alias migrate-repo='bash <(curl -fsSL https://raw.githubusercontent.com/HORKimhab/collection-scripts/refs/heads/main/migrate-repo.sh)'

set -e

NEW_URL="$1"

# If no URL was passed, ask for it until the user types one
while [ -z "$NEW_URL" ]; do
  read -r -p "Enter new repo URL (required): " NEW_URL
done

# Remove the old origin (show its URL first, ignore if none)
if git remote get-url origin >/dev/null 2>&1; then
  echo "Removing old origin: $(git remote get-url origin)"
  git remote remove origin
fi

# Add the new repo
git remote add origin "$NEW_URL"

# Push all branches and tags
git push -u origin --all
git push origin --tags

echo "Done! Origin is now: $(git remote get-url origin)"