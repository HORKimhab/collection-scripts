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

`sync-telegram.sh` syncs media from a source channel/chat message range to `TELEGRAM_CHAT_ID`, in order, with idempotent state and split support.

Required env vars:

```bash
TELEGRAM_BOT_TOKEN="1234567890:your_bot_token_here"
TELEGRAM_CHAT_ID="-1001234567890"
TELEGRAM_FALLBACK_API_BASE_URL="http://127.0.0.1:8081"
```

Optional env vars (defaults):

```bash
TELEGRAM_SOURCE_CHAT_ID="https://web.telegram.org/a/#-1002482766032"
TELEGRAM_SOURCE_CHAT="https://web.telegram.org/a/#-1002482766032" # alias
TELEGRAM_DFROM="https://t.me/UdemyPieFiles/3710"
TELEGRAM_DEND="https://t.me/UdemyPieFiles/3804"
TELEGRAM_SPLIT_MAX_BYTES="1950000000"
TELEGRAM_SOURCE_MODE="bot" # bot|dtt
TELEGRAM_SOURCE_LINK_BASE="" # optional link base, ex: https://t.me/UdemyPieFiles
TELEGRAM_DTT_FETCH_CMD_TEMPLATE="docker compose -f docker-compose.telegram-bot-api.yml run --rm telegram-dtt tdl chat export -c __SOURCE_CHAT__ -T id -i __MESSAGE_ID__,__MESSAGE_ID__ --all -o -"
TELEGRAM_DTT_DOWNLOAD_CMD_TEMPLATE="docker compose -f docker-compose.telegram-bot-api.yml run --rm telegram-dtt tdl dl -u __MESSAGE_LINK__ -d __OUTPUT_DIR__ --continue --skip-same"
```

Defaults:
- source chat: `https://web.telegram.org/a/#-1002482766032`
- dFrom: `https://t.me/UdemyPieFiles/3710`
- dEnd: `https://t.me/UdemyPieFiles/3804`
- split max: `1950000000` bytes (~1.95 GB)

Usage examples:

Default run:
```bash
bash sync-telegram.sh
```

Custom range:
```bash
bash sync-telegram.sh --d-from 3720 --d-end 3750
```

Custom source chat/channel:
```bash
bash sync-telegram.sh --source-chat-id "-1002482766032"
bash sync-telegram.sh --source-chat-id "@UdemyPieFiles"
bash sync-telegram.sh --source-chat-id "https://t.me/UdemyPieFiles"
```

Custom split size:
```bash
bash sync-telegram.sh --split-max-bytes 1500000000
```

Source access via Docker DTT/TDLib mode:
```bash
TELEGRAM_SOURCE_MODE=dtt bash sync-telegram.sh --d-from 3720 --d-end 3750 --source-chat-id "-1002482766032"
```

Behavior notes:
- Bot actions (fetch where available, getFile/download, send/upload) use `TELEGRAM_FALLBACK_API_BASE_URL`.
- `bot` mode reads source via Bot API.
- `dtt` mode reads/downloads source via Docker command templates, then still uploads via Bot API to `TELEGRAM_CHAT_ID`.
- Download/send are idempotent: completed downloads and sent parts are skipped on rerun.
- Message-level `sent` is marked only after all required parts succeed.
- Existing cleanup behavior is preserved after successful send (move/delete local source and split parts).
- If source is inaccessible, the script exits early and logs the exact reason.

### Local tdlib Bot API + DTT setup (`127.0.0.1:8081`)

1. Create Telegram API credentials (`api_id`, `api_hash`) at [my.telegram.org](https://my.telegram.org).
2. Put them in `.env` as `TELEGRAM_API_ID` and `TELEGRAM_API_HASH`.
3. Start local services:

```bash
docker compose -f docker-compose.telegram-bot-api.yml up -d telegram-bot-api
# optional DTT profile:
docker compose -f docker-compose.telegram-bot-api.yml --profile dtt up -d telegram-dtt
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
