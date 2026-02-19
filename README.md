# collection scripts

## Install

```bash
curl -o ~/.custom-bash.sh https://raw.githubusercontent.com/HORKimhab/collection-scripts/main/.custom-bash.sh
```

```bash
# Append .custom-bash.sh to .bashrc
echo -e "\n# ----------------------------- Append or Customize ---------------------------------------------------\nif [ -f ~/.custom-bash.sh ]; then\n  . ~/.custom-bash.sh\nfi\n# ----------------------------- Append or Customize ---------------------------------------------------" >> ~/.bashrc
```

```bash
# Reload .bashrc
source .bashrc
```

## Install postman without third party or apt

```bash
curl -o ~/install-postman-without-third-party.sh \
    https://raw.githubusercontent.com/HORKimhab/collection-scripts/main/install-postman-without-third-party.sh
sudo chmod +x ~/install-postman-without-third-party.sh
```

```bash
# Run it
bash ~/install-postman-without-third-party.sh
```

## Telegram Channel Range Sync

`sync-telegram.sh` downloads media from a source Telegram channel message range, splits large files (`> 1.95 GB`), sends them to `TELEGRAM_CHAT_ID`, and keeps idempotent local state so reruns do not repeat completed work.

### 1) Configure environment

Copy `.env.example` to `.env` and set:

```bash
# Required
TELEGRAM_BOT_TOKEN="1234567890:your_bot_token_here"
TELEGRAM_CHAT_ID="-1001234567890"
TELEGRAM_FALLBACK_API_BASE_URL="http://127.0.0.1:8081"

# Optional (defaults shown)
TELEGRAM_SOURCE_CHAT_ID="https://web.telegram.org/a/#-1002482766032"
TELEGRAM_DFROM="https://t.me/UdemyPieFiles/3710"
TELEGRAM_DEND="https://t.me/UdemyPieFiles/3804"
TELEGRAM_SPLIT_MAX_BYTES="1950000000"
TELEGRAM_SEND_DELAY_SEC="1"
TELEGRAM_MAX_RETRIES="3"
TELEGRAM_RETRY_BASE_SEC="2"
SYNC_MOVE_TO_TRASH="true"
TRASH_DIR="$HOME/.Trash"
TELEGRAM_LOG_ERRORS="true"
TELEGRAM_ERROR_LOG_FILE="/Users/hkimhab25/personal-project/collection-scripts/telegram-sync-error.log"
```

Notes:
- The script uses `TELEGRAM_FALLBACK_API_BASE_URL` for all Telegram API actions (fetch/download/send).
- Default source range is inclusive: message ID `3710` to `3804`.

### 2) Run with defaults

```bash
bash sync-telegram.sh
```

### 3) Custom examples

Custom range:
```bash
bash sync-telegram.sh --d-from 3720 --d-end 3750
```

Custom source chat:
```bash
bash sync-telegram.sh --source-chat-id "https://web.telegram.org/a/#-1002482766032"
# or
bash sync-telegram.sh --source-chat-id "-1002482766032"
```

Custom split size:
```bash
bash sync-telegram.sh --split-max-bytes 1500000000
```

Custom work/state folder:
```bash
bash sync-telegram.sh --dir /path/to/workdir --state-file /path/to/workdir/.telegram-sync-state
```

### 4) Logic and state (idempotent)

For each message ID from `dFrom` to `dEnd`:
1. Fetch message from source chat.
2. If no media exists, mark as `no_media` and skip in future runs.
3. If media exists, download once and mark `downloaded`.
4. If file size is above `TELEGRAM_SPLIT_MAX_BYTES` (default `1950000000`), split into parts.
5. Send each part/file to `TELEGRAM_CHAT_ID`; each part is tracked in state.
6. When all parts are sent, mark message as `sent`.
7. Apply old cleanup behavior: already-sent local files/parts are removed from working dir (moved to Trash when `SYNC_MOVE_TO_TRASH=true`).

State file defaults to:
- `sync-telegram/.telegram-sync-state`

This allows safe reruns:
- downloaded files are not re-downloaded
- sent files/parts are not re-sent
- already-sent artifacts are cleaned up

### Local tdlib Bot API setup (`127.0.0.1:8081`)

1. Create Telegram API credentials (`api_id`, `api_hash`) at [my.telegram.org](https://my.telegram.org).
2. Put them in `.env` as `TELEGRAM_API_ID` and `TELEGRAM_API_HASH`.
3. Start local server:

```bash
docker compose -f docker-compose.telegram-bot-api.yml up -d
```

4. Check server is listening:

```bash
docker compose -f docker-compose.telegram-bot-api.yml ps
curl -sS http://127.0.0.1:8081/ || true
```

5. If needed, inspect logs:

```bash
docker compose -f docker-compose.telegram-bot-api.yml logs -f --tail=100
```

## TODO

- Use fish and separate append alias to one file, use it with 'include'
- `sudo find "$dir" -type f -name "$basename.*bak" -mtime +0 -print0 | xargs -0 -r sudo rm` is slow...
- Install mysql via script: https://chatgpt.com/share/694617e7-6884-800b-bd3d-65997827355e

```bash
# Set auto
# Start ssh-agent if not running
  if [ -z "$SSH_AUTH_SOCK" ]; then
  eval "$(ssh-agent -s)" >/dev/null
  ssh-add /home/deploy/.ssh/rean-it-deploy >/dev/null 2>&1
  fi

  # Reuse existing ssh-agent if available
if [ -f "$HOME/.ssh/agent.env" ]; then
    . "$HOME/.ssh/agent.env" >/dev/null
fi

if ! ssh-add -l >/dev/null 2>&1; then
    eval "$(ssh-agent -s)" >/dev/null
    echo "export SSH_AUTH_SOCK=$SSH_AUTH_SOCK" > "$HOME/.ssh/agent.env"
    echo "export SSH_AGENT_PID=$SSH_AGENT_PID" >> "$HOME/.ssh/agent.env"
    ssh-add /home/deploy/.ssh/rean-it-deploy
fi

```

### Naming convention

- snake_case: e.g: `highlight_file`

### Ubuntu command

- remove alias: `unalias ${alias_name}`

### Test git on Window

- Hello Universe from #HKimhab
- Hello Universe from Mac #HKimhab

### Secure-laravel-code

```bash
# Store encrypt laravel on dockerhub
# Mac
# brew install age

# Encrypt laravel archive
tar cz --exclude-vcs --exclude-from=.gitignore --exclude='._*' --no-xattrs . | age -p -o laravel.enc

# Decrypt
age -d -p -o - laravel.enc | tar xz

# Run laravel inside docker
docker build -t template-secure-laravel-code . && docker run -p 8000:8000 -it template-secure-laravel-code sh

# Docker push
tar cz --exclude-vcs --exclude-from=.gitignore --exclude='._*' . | age -p -o laravel.enc && docker build -t 460616120572/template-secure-laravel-code .

docker push 460616120572/template-secure-laravel-code:latest

# Docker pull and run it
# Key check in "General doc"
docker pull 460616120572/template-secure-laravel-code:latest && docker build -t 460616120572/template-secure-laravel-code . && docker run -p 8000:8000 -it 460616120572/template-secure-laravel-code sh

```
