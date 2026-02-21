# Telegram Channel Range Sync

Download media from any Telegram channel your account can access, then forward
files to a destination chat — idempotently, with large-file splitting support.

```
tdl (your personal MTProto session)
  └─ downloads from source channel  →  ./sync-telegram/

telegram-bot-api (local Bot API server)
  └─ uploads files to TELEGRAM_CHAT_ID
```

---

## Requirements

| Tool                       | Purpose                                      |
| -------------------------- | -------------------------------------------- |
| Docker + Docker Compose v2 | Runs `telegram-bot-api` and `tdl` containers |
| `curl`                     | Uploads files to local Bot API               |
| `jq`                       | JSON parsing                                 |
| `split`                    | Splits files larger than 1.95 GB             |

---

## 1 — Get credentials

### Telegram API ID + Hash (for both services)

1. Go to [my.telegram.org](https://my.telegram.org)
2. Log in with your phone number
3. Click **API Development Tools**
4. Create an app → copy `api_id` and `api_hash`

### Bot Token (for uploads only)

1. Open [@BotFather](https://t.me/BotFather) in Telegram
2. Send `/newbot` and follow prompts
3. Copy the token

### Destination Chat ID (`TELEGRAM_CHAT_ID`)

Add the bot to your destination channel/group as **admin**, then either:

- Use a bot like [@userinfobot](https://t.me/userinfobot) to get the chat ID
- Or check the URL in Telegram Web — the number after `#` is the ID

---

## 2 — Create `.env`

```env
# Telegram API credentials (from my.telegram.org)
TELEGRAM_API_ID=12345678
TELEGRAM_API_HASH=abcdef1234567890abcdef1234567890

# Bot token (from @BotFather)
TELEGRAM_BOT_TOKEN=123456789:AAxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# Destination chat/channel ID (where files will be sent)
TELEGRAM_CHAT_ID=-1001234567890

# Local Bot API server URL (do not change unless you moved the port)
TELEGRAM_FALLBACK_API_BASE_URL=http://127.0.0.1:8081

# ── Optional ────────────────────────────────────────────────────────────────

# Source channel (default shown)
# TELEGRAM_SOURCE_CHAT_ID=https://web.telegram.org/a/#-1002482766032

# Message range (default shown)
# TELEGRAM_DFROM=https://t.me/UdemyPieFiles/3710
# TELEGRAM_DEND=https://t.me/UdemyPieFiles/3804

# Split threshold in bytes — files larger than this are chunked (default 1.95 GB)
# TELEGRAM_SPLIT_MAX_BYTES=1950000000

# tdl session namespace — keep consistent across runs
# TDL_NS=tgsync

# tdl parallel download threads
# TDL_THREADS=4

# Delay between Bot API sends in seconds
# TELEGRAM_SEND_DELAY_SEC=1

# Move synced local files to trash instead of deleting (true/false)
# SYNC_MOVE_TO_TRASH=true
```

---

## 3 — Start the local Bot API server

```bash
docker compose -f docker-compose.telegram-bot-api.yml up -d
```

Wait for it to become healthy:

```bash
docker compose -f docker-compose.telegram-bot-api.yml ps
# STATUS column should show: healthy
```

---

## 4 — Log in with tdl (one time only)

This is interactive — it will ask for your phone number and the OTP Telegram
sends you. The session is saved in the `tdl-data` Docker volume and reused on
every subsequent run.

```bash
docker compose -f docker-compose.telegram-bot-api.yml run --rm tdl login
```

Example prompt:

```
Enter your phone number: +855xxxxxxxxx
Enter the code you received: 12345
Two-step verification password (if enabled): ••••••
Login successful!
```

> You only need to do this once. The session persists in the `tdl-data` volume.

---

## 5 — Run the sync

### Default run (uses all defaults from `.env`)

```bash
bash sync-telegram.sh
```

### Custom message range

```bash
bash sync-telegram.sh --d-from 3720 --d-end 3750
```

### Custom source channel

```bash
bash sync-telegram.sh \
  --source-chat-id "-1002482766032" \
  --d-from 3720 \
  --d-end 3750

  cd /Users/hkimhab25/personal-project/collection-scripts
docker compose -f /Users/hkimhab25/personal-project/collection-scripts/docker-compose.telegram-bot-api.yml up -d tdl
tdl login -T qr

```

### Source via URL

```bash
bash sync-telegram.sh \
  --source-chat-id "https://web.telegram.org/a/#-1002482766032" \
  --d-from "https://t.me/UdemyPieFiles/3720" \
  --d-end "https://t.me/UdemyPieFiles/3750"
```

### Custom split size (e.g. 500 MB parts)

```bash
bash sync-telegram.sh --split-max-bytes 500000000
```

### Custom working directory

```bash
bash sync-telegram.sh --dir /data/tg-downloads
```

---

## How it works (step by step)

```
bash sync-telegram.sh
  │
  ├─ 1. Validate env vars and tools
  │
  ├─ 2. tdl dl --chat <source> --from <id> --to <id> --dir /downloads
  │       └─ Downloads all media in the range to ./sync-telegram/
  │          (tdl uses your personal MTProto session — works on any channel
  │           you're a member of, public or private)
  │
  └─ 3. For each message ID in the range:
          ├─ Find the file tdl downloaded for that message
          ├─ Skip if already sent (idempotent state)
          ├─ Split if file > TELEGRAM_SPLIT_MAX_BYTES
          ├─ Send each part to TELEGRAM_CHAT_ID via local Bot API
          ├─ Mark as sent in state file
          └─ Move/delete local file after successful send
```

---

## Idempotency

The script keeps a state file at `./sync-telegram/.telegram-sync-state`.

| Event                   | Behavior on rerun                              |
| ----------------------- | ---------------------------------------------- |
| Message already sent    | Skipped immediately                            |
| File already downloaded | Not re-downloaded                              |
| Split part already sent | That part is skipped; remaining parts continue |
| No media in message     | Recorded once, skipped on all reruns           |
| Send failed             | Local file kept; retried on next run           |

Safe to run repeatedly — already-completed work is never repeated.

---

## Cleanup behavior

After a message is **fully sent**:

- `SYNC_MOVE_TO_TRASH=true` (default) → file moved to `~/.Trash`
- `SYNC_MOVE_TO_TRASH=false` → file deleted immediately with `rm`

Files are only cleaned up **after confirmed successful send**. Failed or
in-progress files are left in place for the next run to retry.

---

## Logs and errors

| File                                   | Content                               |
| -------------------------------------- | ------------------------------------- |
| `./telegram-sync-error.log`            | Timestamped error/warn/info entries   |
| `./all-store-telegram.txt`             | List of all successfully synced files |
| `./sync-telegram/.telegram-sync-state` | Raw idempotency state keys            |

Disable logging:

```bash
TELEGRAM_LOG_ERRORS=false bash sync-telegram.sh
```

---

## Troubleshooting

**`tdl login` keeps failing**

- Make sure your phone number includes the country code: `+855xxxxxxxxx`
- If you have 2FA enabled, enter your Telegram password when prompted

**Files not found after tdl download**

- Check `./sync-telegram/` for what tdl actually wrote
- tdl names files as `<message_id>-<filename>` — verify the pattern matches

**Bot API upload fails with 413 (file too large)**

- The local Bot API server removes the 50 MB limit, but your file may still
  exceed Telegram's server-side limit for the destination chat type
- Lower `TELEGRAM_SPLIT_MAX_BYTES` (e.g. `1900000000`) and rerun

**`docker compose` not found**

- Ensure you have Docker Compose v2 (bundled with Docker Desktop, or
  install the `docker-compose-plugin` package)
- Test with: `docker compose version`

**Session expired**

- Re-run `docker compose -f docker-compose.telegram-bot-api.yml run --rm tdl login`

## Note: 

``` bash 
    # Example 
    bash sync-telegram.sh --source-chat-id 'https://web.telegram.org/a/#-1002482766032' --d-from https://t.me/UdemyPieFiles/3720 --d-end https://t.me/UdemyPieFiles/3720
``` 
