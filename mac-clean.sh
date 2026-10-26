#!/bin/bash
# mac-clean.sh

# mkdir -p ~/bin
# grep -q "alias macclean=" ~/.zshrc || echo "alias macclean='\$HOME/bin/mac-clean.sh'" >> ~/.zshrc
# source ~/.zshrc
# macclean-update

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
Usage: $SCRIPT [dry|run] [--quit]
       $SCRIPT -h | --help
EOF
}

show_help() {
  cat <<EOF
$SCRIPT - Clean caches and temp files on macOS (browsers are left untouched)

USAGE
  $SCRIPT [MODE] [--quit]
  $SCRIPT -h | --help

MODES
  dry    Preview only, nothing is deleted (default)
  run    Actually delete files

OPTIONS
  -q, --quit    Quit open browsers first (like Cmd+Q, so logins are saved)
  -h, --help    Show this help message and exit

EXAMPLES
  $SCRIPT              Same as 'dry'
  $SCRIPT dry          Preview what would be deleted
  $SCRIPT run          Delete for real (asks for sudo only to flush DNS)
  $SCRIPT run --quit   Quit open browsers, then delete for real

WHAT IT CLEANS
  - ~/Library/Caches (except browsers, com.apple.*, CloudKit)
  - \$TMPDIR contents (except browsers)
  - ~/Library/Logs and crash reports
  - Saved Application State (except browsers)
  - Dev caches: brew, npm, yarn, pnpm, go, pip3, composer,
    Xcode DerivedData, CoreSimulator, Gradle, Maven
  - DNS cache

WHAT IT NEVER TOUCHES
  - Browser data: Chrome, Safari, Firefox, Edge, Arc, Brave, Opera,
    Vivaldi, Chromium, Orion, Zen (cookies and logins stay intact)
  - /System, /Library, /private/var
  - Trash, Xcode Archives, iCloud/CloudKit caches

NOTES
  - Quit your apps before using 'run' (it refuses to run while a browser
    is open, unless you add --quit).
  - Do not run as root or with sudo.
  - Restart your Mac afterward for a full refresh.
EOF
}

# Parse arguments
MODE="dry"
QUIT_BROWSERS=0
for arg in "$@"; do
  case "$arg" in
    -h|--help) show_help; exit 0 ;;
    dry|run)   MODE="$arg" ;;
    -q|--quit) QUIT_BROWSERS=1 ;;
    *)
      echo "Error: unknown option '$arg'" >&2
      echo >&2
      usage >&2
      echo "Try '$SCRIPT --help' for more information." >&2
      exit 1
      ;;
  esac
done

# Safety: never run as root (would target the wrong home folder)
if [ "$(id -u)" -eq 0 ]; then
  echo "Do not run as root/sudo." >&2; exit 1
fi

# In dry mode, sizes of what would be deleted are collected here for a total
if [ "$MODE" = "dry" ]; then
  DRY_LOG="$(mktemp -t mac-clean)"
  trap 'rm -f "$DRY_LOG"' EXIT
fi

# Delete helper: prints with size in dry mode, deletes in run mode
del() {
  if [ "$MODE" = "run" ]; then
    rm -rf "$@" 2>/dev/null
  else
    local kb
    kb=$(du -sk "$@" 2>/dev/null | awk '{s += $1} END {print s + 0}')
    echo "$kb" >> "$DRY_LOG"
    echo "[dry] rm -rf $* ($(human "$kb"))"
  fi
}

# Command helper for tool cleanups
runcmd() {
  if [ "$MODE" = "run" ]; then "$@" >/dev/null 2>&1; else echo "[dry] $*"; fi
}

# Browser data (caches, temp files, saved state) is skipped so logins and
# cookies for sites like Gmail/Facebook are never touched
is_browser() {
  local name
  name="$(basename "$1" | tr '[:upper:]' '[:lower:]')"
  case "$name" in
    *brave*|*google*|*chrome*|*chromium*|*firefox*|*mozilla*|*safari*|*webkit*| \
    *edge*|*edgemac*|arc|company.thebrowser.*|*opera*|*vivaldi*|*orion*|*zen*)
      return 0 ;;
  esac
  return 1
}

# Delete each entry of a directory, skipping browser-related ones
del_contents() {
  [ -d "$1" ] || return 0
  find "$1" -mindepth 1 -maxdepth 1 "${@:2}" -print0 |
    while IFS= read -r -d '' p; do
      is_browser "$p" && continue
      [ "$p" = "$DRY_LOG" ] && continue
      del "$p"
    done
}

# Browsers must be closed, otherwise deleting their temp files can end sessions
BROWSERS=("Google Chrome" "Safari" "firefox" "Microsoft Edge" "Arc" "Brave Browser"
          "Opera" "Vivaldi" "Chromium" "Orion" "zen")
running_browsers() {
  local b
  for b in "${BROWSERS[@]}"; do
    pgrep -xq "$b" && echo "$b"
  done
}

if [ "$MODE" = "run" ]; then
  running=()
  while IFS= read -r b; do running+=("$b"); done < <(running_browsers)

  if [ "${#running[@]}" -gt 0 ] && [ "$QUIT_BROWSERS" -eq 1 ]; then
    # Quit like Cmd+Q (not kill) so browsers save cookies and sessions
    for b in "${running[@]}"; do
      echo "Quitting $b..."
      osascript -e "quit app \"$b\"" >/dev/null 2>&1
    done
    # Wait up to 15 seconds for them to close
    for _ in $(seq 15); do
      [ -z "$(running_browsers)" ] && break
      sleep 1
    done
    running=()
    while IFS= read -r b; do running+=("$b"); done < <(running_browsers)
  fi

  if [ "${#running[@]}" -gt 0 ]; then
    echo "Please quit these browsers first: ${running[*]}" >&2
    echo >&2
    echo "Quit them yourself with Cmd+Q, or run:" >&2
    for b in "${running[@]}"; do
      echo "  osascript -e 'quit app \"$b\"'" >&2
    done
    echo >&2
    echo "Or let this script quit them for you:" >&2
    echo "  $SCRIPT run --quit" >&2
    exit 1
  fi
fi

echo "Mode: $MODE"
# Free space on / in KB, used to report how much was freed
free_kb() { df -k / | awk 'NR==2 {print $4}'; }

# Format KB as a human-readable size
human() {
  awk -v kb="$1" 'BEGIN {
    if (kb >= 1048576) printf "%.2f GB", kb / 1048576
    else if (kb >= 1024) printf "%.1f MB", kb / 1024
    else printf "%d KB", kb
  }'
}

FREE_BEFORE=$(free_kb)
echo "Free space before:"; df -h / | tail -1
echo

# 1. User caches (skips browsers, all Apple-owned caches, and CloudKit)
del_contents ~/Library/Caches ! -name "com.apple.*" ! -name "CloudKit"

# 2. Temp files (guarded so an empty $TMPDIR can never expand to rm -rf *)
if [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ]; then
  del_contents "${TMPDIR%/}"
fi

# 3. Logs and crash reports
del ~/Library/Logs/*
del ~/Library/Logs/DiagnosticReports/*
del ~/Library/Application\ Support/CrashReporter/*

# 4. Saved window state (apps won't reopen previous windows)
del_contents ~/Library/Saved\ Application\ State

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

if [ "$MODE" = "run" ]; then
  FREED=$(( $(free_kb) - FREE_BEFORE ))
  [ "$FREED" -lt 0 ] && FREED=0
  echo "Space freed: $(human "$FREED")"
  echo "Free now:    $(human "$(free_kb)")"
  echo "Done. Restart your Mac for a full refresh."
else
  echo "Would free about: $(human "$(awk '{s += $1} END {print s + 0}' "$DRY_LOG")")"
  echo "(plus brew/npm/yarn/pnpm/go/pip/composer caches, not measured)"
  echo "Run '$SCRIPT run' to delete for real."
fi