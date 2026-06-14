#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/tmp/mac_cleanup_dryrun_$(date +%Y%m%d_%H%M%S).log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "🧪 macOS Cleanup (DRY RUN - NO CHANGES MADE)"
echo "=========================================="
echo "📄 Log file: $LOG_FILE"
echo

echo "→ Homebrew cleanup (preview only)"
brew cleanup -n
brew autoremove --dry-run || echo "autoremove dry-run not supported on this version"

echo
echo "→ User cache files that would be removed (keeping Brave):"
find "$HOME/Library/Caches" -mindepth 1 -maxdepth 1 \
  ! -name "BraveSoftware" -print

echo
echo "→ System cache files that would be removed:"
find /Library/Caches -mindepth 1 -maxdepth 1 -print 2>&1 || true

echo
echo "→ Trash contents that would be removed:"
find "$HOME/.Trash" -mindepth 1 -print 2>&1 || true

echo
echo "=========================================="
echo "✅ DRY RUN COMPLETE - NOTHING WAS DELETED"
echo "📄 Saved log: $LOG_FILE"
echo "=========================================="