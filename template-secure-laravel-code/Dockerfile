# # Base PHP-FPM image
FROM php:8.3-fpm-alpine

# --------------------------------------------------
# System dependencies + tools
# --------------------------------------------------
    RUN apk add --no-cache \
    age \
    tar \
    bash \
    nano \
    nginx \
    supervisor \
    curl \
    libzip-dev \
    oniguruma-dev

# --------------------------------------------------
# PHP extensions required by Laravel
# --------------------------------------------------
    RUN docker-php-ext-install \
    mbstring \
    zip \
    pdo \
    pdo_mysql \
    opcache

# --------------------------------------------------
# Install Composer (official)
# --------------------------------------------------
RUN curl -sS https://getcomposer.org/installer \
| php -- --install-dir=/usr/local/bin --filename=composer
# --------------------------------------------------

# Cleanup to keep image small
# --------------------------------------------------
RUN rm -rf /tmp/* /var/cache/apk/*

# Set working directory for decrypted Laravel
WORKDIR /var/www

# Copy only encrypted Laravel and entrypoint
COPY laravel.enc /tmp/laravel.enc
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# Make entrypoint executable
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Copy Nginx config
COPY docker/nginx/default.conf /etc/nginx/http.d/default.conf

# Copy supervisor config into /etc in container
COPY  docker/supervisord.conf /etc/supervisord.conf

EXPOSE 8000

# Entrypoint for runtime decryption
ENTRYPOINT ["docker-entrypoint.sh"]

# # Default command to run PHP-FPM
# CMD ["php-fpm"]
# Start supervisor to run PHP-FPM + Nginx
# CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisord.conf"]
