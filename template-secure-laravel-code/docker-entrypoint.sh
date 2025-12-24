#!/bin/sh
set -e

# Directory where Laravel will be decrypted
APP_DIR=/var/www
# HOST="${LARAVEL_HOST:-0.0.0.0}"
# PORT="${LARAVEL_PORT:-8000}"

mkdir -p "$APP_DIR"

# Only decrypt if /tmp/laravel.enc exists and .env.example is missing in $APP_DIR
if [ -f /tmp/laravel.enc ] && [ ! -f "$APP_DIR/.env.example" ]; then
    if [ -n "$AGE_PASSWORD" ]; then
        echo "[INFO] Decrypting Laravel source using AGE_PASSWORD..."
        echo "$AGE_PASSWORD" | age --passphrase --decrypt /tmp/laravel.enc | tar xz -C "$APP_DIR"
    else
        echo "[INFO] AGE_PASSWORD not set, will prompt for password interactively..."
        age -d /tmp/laravel.enc | tar xz -C "$APP_DIR"
    fi

    # Clean up encrypted file after decryption
    rm -f /tmp/laravel.enc

    echo "[INFO] Laravel decrypted successfully."
else
    echo "[INFO] Skipping decryption. Either laravel.enc missing or app already exists."
fi

# Remove macOS resource fork files inside app directory
find "$APP_DIR" -name '._*' -type f -delete

# ----------------------------
# Set correct permissions
# ----------------------------
echo "[INFO] Setting secure permissions..."

# Ensure correct ownership
chown -R www-data:www-data "$APP_DIR"

# App root: readable, not writable by others
find "$APP_DIR" -type d -exec chmod 755 {} \;
find "$APP_DIR" -type f -exec chmod 644 {} \;

# Writable directories (Laravel requirement)
chmod -R 775 "$APP_DIR/storage" "$APP_DIR/bootstrap/cache"

# Secure .env handling
if [ ! -f "$APP_DIR/.env" ]; then
    echo "[INFO] Creating .env from example..."
    cp "$APP_DIR/.env.example" "$APP_DIR/.env"
    chown www-data:www-data "$APP_DIR/.env"
    chmod 640 "$APP_DIR/.env"
else
    echo "[INFO] .env already exists, skipping"
fi

# ----------------------------
# Install composer dependencies if missing
# ----------------------------
if [ ! -d "$APP_DIR/vendor" ] || [ ! "$(ls -A "$APP_DIR/vendor")" ]; then
    echo "[INFO] Installing Composer dependencies..."
    composer install --no-dev --optimize-autoloader --working-dir="$APP_DIR"
fi

# --------------------------------------------------
# Laravel bootstrap (DO NOT FAIL CONTAINER)
# --------------------------------------------------
echo "[INFO] Running Laravel optimizations..."

php "$APP_DIR/artisan" key:generate --force || true
php "$APP_DIR/artisan" migrate --force || true

php "$APP_DIR/artisan" config:clear || true
php "$APP_DIR/artisan" config:cache || true
php "$APP_DIR/artisan" route:cache || true
php "$APP_DIR/artisan" view:cache || true

echo "[INFO] Starting supervisord in background..."

/usr/bin/supervisord -c /etc/supervisord.conf &
echo "[INFO] Supervisord started in background with PID $!"

# Keep container alive
while true; do sleep 60; done
