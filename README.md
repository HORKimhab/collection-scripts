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

## Sync encrypted files to Telegram group

### 1) Configure environment

Copy `.env.example` to `.env` and update:

```bash
TELEGRAM_BOT_TOKEN="1234567890:your_bot_token_here"
TELEGRAM_CHAT_ID="-1001234567890"
TELEGRAM_API_BASE_URL="https://api.telegram.org"
TELEGRAM_FALLBACK_API_BASE_URL="http://127.0.0.1:8081"
TELEGRAM_API_ID="12345678"
TELEGRAM_API_HASH="your_api_hash_from_my_telegram_org"
TELEGRAM_ENCRYPT_PASSWORD="your-main-secret"
SECRET_45="your-secret-45"
SECRET_SAME="your-secret-same"
TELEGRAM_SEND_DELAY_SEC="1"
TELEGRAM_MAX_RETRIES="3"
TELEGRAM_RETRY_BASE_SEC="2"
SYNC_INCLUDE_HIDDEN="false"
SYNC_MOVE_TO_TRASH="true"
TRASH_DIR="$HOME/.Trash"
TELEGRAM_LOG_ERRORS="true"
TELEGRAM_ERROR_LOG_FILE="/Users/hkimhab25/personal-project/collection-scripts/telegram-sync-error.log"
```

### 2) Put files in folder (default)

Default folder is `sync-telegram`.

```bash
mkdir -p sync-telegram
# add your files/photos inside sync-telegram/
```

### 3) Run sync script

```bash
bash sync-telegram.sh
```

### 4) Use custom folder (optional)

```bash
bash sync-telegram.sh /path/to/your/folder
# or
bash sync-telegram.sh --dir /path/to/your/folder
```

### Notes

- Images/videos are sent without encryption so they can open directly after download.
- All other file types are encrypted before upload using password:
  `TELEGRAM_ENCRYPT_PASSWORD + SECRET_45 + SECRET_SAME` (string concatenation).
- Encrypted files are uploaded with `.enc` suffix and caption includes:
  `Encypt Hint: ${TELEGRAM_ENCRYPT_PASSWORD}45same`
- No temp directory is used. A hidden encrypted working file is created next to source, uploaded, then deleted.
- Script writes/appends sent names to `all-store-telegram.txt` next to `sync-telegram.sh` with template:
  `- {OriginalFileName}`.
- Script keeps a local state file (`.telegram-sync-state`) and only sends new/changed files in later runs.
- Anti-spam: script throttles each send (`TELEGRAM_SEND_DELAY_SEC`) and retries failed/rate-limited requests (`TELEGRAM_MAX_RETRIES`, `TELEGRAM_RETRY_BASE_SEC`).
- After successful send, source file is moved to Trash (restorable). Configure with `SYNC_MOVE_TO_TRASH` and `TRASH_DIR`.
- Telegram API errors are logged with timestamp and response detail to `telegram-sync-error.log` (configurable via `TELEGRAM_ERROR_LOG_FILE`).
- Telegram bot must be added to your group/channel and have permission to send messages.
- To use local Bot API server (supports large uploads, up to ~2000 MB), set:
  `TELEGRAM_API_BASE_URL="http://127.0.0.1:8081"` (always local), or
  `TELEGRAM_FALLBACK_API_BASE_URL="http://127.0.0.1:8081"` (auto-switch only when cloud API returns `413`).
- For fallback mode, keep `TELEGRAM_API_BASE_URL="https://api.telegram.org"` and run a local [tdlib/telegram-bot-api](https://github.com/tdlib/telegram-bot-api) server.

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
