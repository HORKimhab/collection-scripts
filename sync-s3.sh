#!/bin/bash

# ─── CONFIG ────────────────────────────────────────────────
BUCKETS=(
  "bucket1"
  "bucket2"
)
OUTPUT_DIR="./downloaded_images"
LOG_FILE="./sync_s3.log"
MAX_RETRIES=10
RETRY_DELAY=15
# ───────────────────────────────────────────────────────────

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_deps() {
  if ! command -v aws &>/dev/null; then
    log "❌ AWS CLI not found. Install it first."
    exit 1
  fi
  # Use pigz (parallel gzip) if available, fallback to gzip
  if command -v pigz &>/dev/null; then
    COMPRESS_CMD="pigz"
    log "⚡ Using pigz (parallel compression)"
  else
    COMPRESS_CMD="gzip"
    log "📦 Using gzip (install pigz for faster compression)"
  fi
}

check_disk_space() {
  BUCKET=$1
  log "💾 Checking disk space..."
  AVAILABLE=$(df -BG . | awk 'NR==2 {print $4}' | tr -d 'G')
  log "   Available: ${AVAILABLE}GiB"
  if [ "$AVAILABLE" -lt 50 ]; then
    log "⚠️  Warning: Less than 50GiB free. You may run out of space."
    read -p "   Continue anyway? (y/n): " confirm
    [[ "$confirm" != "y" ]] && exit 1
  fi
}

sync_bucket() {
  BUCKET=$1
  DIR="$OUTPUT_DIR/$BUCKET"
  ARCHIVE="${OUTPUT_DIR}/${BUCKET}.tar.gz"
  PART_ARCHIVE="${ARCHIVE}.part"
  ATTEMPT=1

  mkdir -p "$DIR"

  # Skip if already fully compressed
  if [ -f "$ARCHIVE" ]; then
    log "⏭️  [$BUCKET] Archive already exists, skipping."
    return 0
  fi

  # ── Step 1: Sync with resume ──────────────────────────────
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "📂 [$BUCKET] Starting sync..."

  while [ $ATTEMPT -le $MAX_RETRIES ]; do
    log "🔄 [$BUCKET] Sync attempt $ATTEMPT/$MAX_RETRIES..."

    aws s3 sync s3://$BUCKET "$DIR" \
      --exact-timestamps \
      --no-progress=false 2>&1 | tee -a "$LOG_FILE"

    if [ ${PIPESTATUS[0]} -eq 0 ]; then
      log "✅ [$BUCKET] Sync complete!"
      break
    fi

    if [ $ATTEMPT -eq $MAX_RETRIES ]; then
      log "💀 [$BUCKET] Sync failed after $MAX_RETRIES attempts. Skipping compression."
      return 1
    fi

    log "❌ [$BUCKET] Sync failed. Retrying in ${RETRY_DELAY}s... (files already downloaded are safe)"
    ATTEMPT=$((ATTEMPT + 1))
    sleep $RETRY_DELAY
  done

  # ── Step 2: Compress with resume ─────────────────────────
  log "📦 [$BUCKET] Compressing → ${ARCHIVE}..."

  # Use .part file so incomplete archives are never mistaken for complete
  tar -I "$COMPRESS_CMD" -cf "$PART_ARCHIVE" -C "$OUTPUT_DIR" "$BUCKET" 2>&1 | tee -a "$LOG_FILE"

  if [ $? -eq 0 ]; then
    mv "$PART_ARCHIVE" "$ARCHIVE"
    log "✅ [$BUCKET] Compressed → $ARCHIVE"
    log "🗑️  [$BUCKET] Removing raw folder..."
    rm -rf "$DIR"
  else
    log "❌ [$BUCKET] Compression failed. Raw files kept at $DIR"
    log "   Re-run script to retry compression."
    rm -f "$PART_ARCHIVE"
    return 1
  fi
}

summarize() {
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "🎉 All done! Archive sizes:"
  ls -lh "$OUTPUT_DIR"/*.tar.gz 2>/dev/null | awk '{print "   " $5 "  " $9}' | tee -a "$LOG_FILE"
  log "📋 Full log saved to: $LOG_FILE"
}

# ── Main ───────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"
check_deps
check_disk_space

log "╔══════════════════════════════════════════════════════╗"
log "║         S3 Sync + Compress with Auto-Resume          ║"
log "╚══════════════════════════════════════════════════════╝"
log "  Buckets : ${BUCKETS[*]}"
log "  Output  : $(realpath $OUTPUT_DIR)"
log "  Retries : $MAX_RETRIES"

for BUCKET in "${BUCKETS[@]}"; do
  sync_bucket "$BUCKET"
done

summarize