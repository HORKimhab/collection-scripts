#!/bin/bash
# mac-clean.sh

# cat >> ~/.zshrc <<'EOF'

# macclean-update() {
#   curl -fsSL https://raw.githubusercontent.com/HORKimhab/collection-scripts/refs/heads/main/mac-clean.sh -o "$HOME/bin/mac-clean.sh" \
#     && chmod +x "$HOME/bin/mac-clean.sh" \
#     && echo "macclean updated."
# }
# EOF
# source ~/.zshrc

SCRIPT="$(basename "$0")"

usage() {
  cat <<EOF
Usage: $SCRIPT [dry|run]
       $SCRIPT -h | --help
EOF
}

show_help() {
  cat <<EOF
$SCRIPT - Clean caches and temp files on macOS (Brave is left untouched)

USAGE
  $SCRIPT [MODE]
  $SCRIPT -h | --help

MODES
  dry    Preview only, nothing is deleted (default)
  run    Actually delete files

OPTIONS
  -h, --help    Show this help message and exit

EXAMPLES
  $SCRIPT              Same as 'dry'
  $SCRIPT dry          Preview what would be deleted
  $SCRIPT run          Delete for real (asks for sudo only to flush DNS)

WHAT IT CLEANS
  - ~/Library/Caches (except Brave, com.apple.*, CloudKit)
  - \$TMPDIR contents
  - ~/Library/Logs and crash reports
  - Saved Application State
  - Dev caches: brew, npm, yarn, pnpm, go, pip3, composer,
    Xcode DerivedData, CoreSimulator, Gradle, Maven
  - DNS cache

WHAT IT NEVER TOUCHES
  - Brave cache and profile
  - /System, /Library, /private/var
  - Trash, Xcode Archives, iCloud/CloudKit caches

NOTES
  - Quit your apps before using 'run'.
  - Do not run as root or with sudo.
  - Restart your Mac afterward for a full refresh.
EOF
}

# Parse arguments
case "${1:-dry}" in
  -h|--help) show_help; exit 0 ;;
  dry|run)   MODE="${1:-dry}" ;;
  *)
    echo "Error: unknown option '$1'" >&2
    echo >&2
    usage >&2
    echo "Try '$SCRIPT --help' for more information." >&2
    exit 1
    ;;
esac

# Safety: never run as root (would target the wrong home folder)
if [ "$(id -u)" -eq 0 ]; then
  echo "Do not run as root/sudo." >&2; exit 1
fi

# Delete helper: prints in dry mode, deletes in run mode
del() {
  if [ "$MODE" = "run" ]; then rm -rf "$@" 2>/dev/null; else echo "[dry] rm -rf $*"; fi
}

# Command helper for tool cleanups
runcmd() {
  if [ "$MODE" = "run" ]; then "$@" >/dev/null 2>&1; else echo "[dry] $*"; fi
}

echo "Mode: $MODE"
echo "Free space before:"; df -h / | tail -1
echo

# 1. User caches (skips Brave, all Apple-owned caches, and CloudKit)
find ~/Library/Caches -mindepth 1 -maxdepth 1 \
  ! -iname "BraveSoftware" \
  ! -iname "com.brave.*" \
  ! -name "com.apple.*" \
  ! -name "CloudKit" \
  -print0 | while IFS= read -r -d '' p; do del "$p"; done

# 2. Temp files (guarded so an empty $TMPDIR can never expand to rm -rf *)
if [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ]; then
  del "${TMPDIR%/}"/*
fi

# 3. Logs and crash reports
del ~/Library/Logs/*
del ~/Library/Logs/DiagnosticReports/*
del ~/Library/Application\ Support/CrashReporter/*

# 4. Saved window state (apps won't reopen previous windows)
del ~/Library/Saved\ Application\ State/*

# 5. Developer tool caches (only if installed)
command -v brew      >/dev/null && runcmd brew cleanup -s --prune=all
command -v npm       >/dev/null && runcmd npm cache clean --force
command -v yarn      >/dev/null && runcmd yarn cache clean
command -v pnpm      >/dev/null && runcmd pnpm store prune
command -v go        >/dev/null && runcmd go clean -cache -testcache
command -v pip3      >/dev/null && runcmd pip3 cache purge
command -v composer  >/dev/null && runcmd composer clear-cache

del ~/Library/Developer/Xcode/DerivedData/*
del ~/Library/Developer/CoreSimulator/Caches/*
del ~/.gradle/caches/*
del ~/.m2/repository/.cache

# 6. Flush DNS cache (asks for your password in run mode)
if [ "$MODE" = "run" ]; then
  sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
else
  echo "[dry] flush DNS cache"
fi

echo
echo "Free space after:"; df -h / | tail -1
[ "$MODE" = "run" ] && echo "Done. Restart your Mac for a full refresh."