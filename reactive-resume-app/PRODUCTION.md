# Reactive Resume v5 on Oracle Linux 9

This runbook deploys [Reactive Resume](https://github.com/reactive-resume/app) on
the existing Oracle Linux 9 server described below. It uses:

- Reactive Resume `v5.3.0`
- PostgreSQL 16
- Redis 7
- The server's existing Apache HTTP Server as the HTTPS reverse proxy
- Docker Engine and Docker Compose
- Docker named volumes for persistent data

Apache already owns public ports 80 and 443. Reactive Resume is published only on
`127.0.0.1:3000`; PostgreSQL and Redis remain private Docker services.

## Existing server assessment

The checked server has 2 vCPUs, 3.4 GiB RAM, 3.4 GiB swap, and 19 GiB free on the
root filesystem. At the time of assessment, about 2.4 GiB RAM and 3.2 GiB swap
were available. This is adequate for a personal or small-team deployment, but
disk and memory usage must be monitored because the server also hosts Apache and
possibly other applications.

SELinux is enforcing and must remain enabled. Apache is already listening on
ports 80 and 443, so **do not deploy the Caddy configuration from a generic
single-host guide and do not publish another container on ports 80 or 443**.

> **Version note:** `v5.3.0` was the latest verified release when this guide was
> written on 2026-09-12. Pinning a release is safer than using `latest`. Review
> the project's release notes before changing the version.

## 1. Prerequisites

Prepare the following before starting:

- An Oracle Linux 9 server with at least 2 vCPU, 4 GB RAM, and 20 GB disk
- A non-root account with `sudo` access
- The public domain `resume.rean-it.com`
- A DNS `A` record pointing the domain to the server's public IPv4 address
- TCP ports 22, 80, and 443 allowed in the OCI Network Security Group or security
  list; do not add a new rule if the existing policy already provides it
- Access to the existing Apache configuration and its TLS certificate process
- An SMTP account if email verification and password-reset emails are required

Keep SSH restricted to trusted source addresses in OCI when possible. Do not open
ports 3000, 5432, or 6379 in OCI or `firewalld`.

## 2. Verify the existing host and install Docker

On an existing production server, review pending updates before applying a full
system update. Do not restart Apache or reboot until the effect on other hosted
applications is understood.

```bash
sudo dnf install -y dnf-plugins-core firewalld openssl
sudo systemctl enable --now firewalld

sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker

sudo docker version
sudo docker compose version
sudo docker run --rm hello-world
```

If Docker is already installed, do not reinstall it. Verify it instead:

```bash
sudo systemctl status docker --no-pager
sudo docker version
sudo docker compose version
sudo docker ps
```

Oracle Linux 9 is RHEL-compatible; the commands above use Docker's CentOS/RHEL
RPM repository. When prompted about Docker's GPG key, verify the fingerprint
against the current value in the official Docker installation documentation.

This guide deliberately uses `sudo docker`. Membership in the `docker` group is
effectively root access and should only be granted deliberately.

## 3. Open the host firewall

First identify the active zone:

```bash
sudo firewall-cmd --get-active-zones
```

The checked interface `ens3` is in the `public` zone. Inspect existing rules,
then add only missing HTTP/HTTPS services:

```bash
sudo firewall-cmd --permanent --zone=public --add-service=http
sudo firewall-cmd --permanent --zone=public --add-service=https
sudo firewall-cmd --reload
sudo firewall-cmd --zone=public --list-all
```

If the active zone is not `public`, replace `public` with the reported zone. Keep
SSH enabled before changing firewall configuration so that the server does not
become inaccessible.

## 4. Create the deployment directory

Use `/opt/reactive-resume` for the production stack:

```bash
sudo install -d -o "$USER" -g "$(id -gn)" -m 0750 /opt/reactive-resume
cd /opt/reactive-resume
```

If the directory was already created as `root:root` and `cd` reports
`Permission denied`, repair its ownership first:

```bash
sudo chown "$USER":"$(id -gn)" /opt/reactive-resume
sudo chmod 0750 /opt/reactive-resume
cd /opt/reactive-resume
```

This gives the current administrative user access to the deployment directory.
The secret `.env` file is changed to `root:root` with mode `0600` in the next
step and is read by commands executed with `sudo docker compose`.

Create `/opt/reactive-resume/.env`:

```dotenv
DOMAIN=resume.rean-it.com

POSTGRES_DB=reactive_resume
POSTGRES_USER=reactive_resume
POSTGRES_PASSWORD=REPLACE_WITH_A_RANDOM_HEX_VALUE

AUTH_SECRET=REPLACE_WITH_A_DIFFERENT_RANDOM_HEX_VALUE
ENCRYPTION_SECRET=REPLACE_WITH_ANOTHER_RANDOM_HEX_VALUE

FLAG_DISABLE_SIGNUPS=false
FLAG_DISABLE_EMAIL_AUTH=false
FLAG_DISABLE_IMAGE_PROCESSING=false
FLAG_DISABLE_API_RATE_LIMIT=false
FLAG_ALLOW_UNSAFE_OAUTH_REDIRECT_URI=false
FLAG_ALLOW_UNSAFE_AI_BASE_URL=false

# Optional SMTP configuration. Leave all four values empty to disable SMTP.
SMTP_HOST=
SMTP_PORT=
SMTP_USER=
SMTP_PASS=
SMTP_FROM="Reactive Resume <noreply@rean-it.com>"
SMTP_SECURE=false
```

Generate three independent secrets. The generated hexadecimal characters are
safe inside both the dotenv file and PostgreSQL connection URL:

```bash
openssl rand -hex 32
openssl rand -hex 32
openssl rand -hex 32
```

Use the first value for `POSTGRES_PASSWORD`, the second for `AUTH_SECRET`, and
the third for `ENCRYPTION_SECRET`. Replace `DOMAIN` and `SMTP_FROM` too. Then
restrict access to the file:

```bash
sudo chown root:root /opt/reactive-resume/.env
sudo chmod 0600 /opt/reactive-resume/.env
```

If SMTP is enabled, set every SMTP field required by the provider. Common values
are port `465` with `SMTP_SECURE=true`, or port `587` with
`SMTP_SECURE=false`. Do not commit `.env` to source control.

## 5. Create the Compose stack

Create `/opt/reactive-resume/compose.yaml`:

```yaml
name: reactive_resume

services:
  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - backend
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 10s

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    command: ["redis-server", "--appendonly", "yes"]
    volumes:
      - redis_data:/data
    networks:
      - backend
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 10

  reactive_resume:
    image: ghcr.io/reactive-resume/app:v5.3.0
    restart: unless-stopped
    environment:
      PORT: "3000"
      APP_URL: https://${DOMAIN}
      DATABASE_URL: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
      AUTH_SECRET: ${AUTH_SECRET}
      ENCRYPTION_SECRET: ${ENCRYPTION_SECRET}
      REDIS_URL: redis://redis:6379
      LOCAL_STORAGE_PATH: /app/data
      FLAG_DISABLE_SIGNUPS: ${FLAG_DISABLE_SIGNUPS:-false}
      FLAG_DISABLE_EMAIL_AUTH: ${FLAG_DISABLE_EMAIL_AUTH:-false}
      FLAG_DISABLE_IMAGE_PROCESSING: ${FLAG_DISABLE_IMAGE_PROCESSING:-false}
      FLAG_DISABLE_API_RATE_LIMIT: ${FLAG_DISABLE_API_RATE_LIMIT:-false}
      FLAG_ALLOW_UNSAFE_OAUTH_REDIRECT_URI: ${FLAG_ALLOW_UNSAFE_OAUTH_REDIRECT_URI:-false}
      FLAG_ALLOW_UNSAFE_AI_BASE_URL: ${FLAG_ALLOW_UNSAFE_AI_BASE_URL:-false}
      SMTP_HOST: ${SMTP_HOST:-}
      SMTP_PORT: ${SMTP_PORT:-}
      SMTP_USER: ${SMTP_USER:-}
      SMTP_PASS: ${SMTP_PASS:-}
      SMTP_FROM: ${SMTP_FROM:-}
      SMTP_SECURE: ${SMTP_SECURE:-false}
    volumes:
      - app_data:/app/data
    ports:
      - "127.0.0.1:3000:3000"
    networks:
      - backend
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test:
        - CMD
        - node
        - -e
        - "fetch('http://127.0.0.1:3000/api/health').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

volumes:
  postgres_data:
  redis_data:
  app_data:

networks:
  backend:
```

The deployment uses local persistent storage at `/app/data`, so no S3 variables
are set. SeaweedFS is therefore unnecessary for this single-server layout. Redis
supports the optional authenticated AI workspace and is also kept persistent.

The loopback binding ensures that port 3000 is reachable by host Apache but not
by remote clients. Named volumes do not require a host bind-mount label. Do not
disable SELinux.

Set safe ownership, validate the resolved configuration, and start the private
application stack:

```bash
sudo chown root:root /opt/reactive-resume/compose.yaml
sudo chmod 0644 /opt/reactive-resume/compose.yaml
cd /opt/reactive-resume
sudo docker compose config --quiet
sudo docker compose pull
sudo docker compose up -d
sudo docker compose ps
```

At this stage `curl http://127.0.0.1:3000/api/health` should succeed, but port
3000 should not be reachable from another machine.

## 6. Configure the existing Apache server

Confirm that Apache has the required modules:

```bash
sudo httpd -M | grep -E 'proxy_module|proxy_http_module|headers_module|ssl_module'
```

Enable Apache to connect to the loopback application port while SELinux remains
enforcing:

```bash
sudo setsebool -P httpd_can_network_connect 1
```

Back up the existing Apache configuration before changing it:

```bash
sudo cp -a /etc/httpd/conf.d /etc/httpd/conf.d.backup-before-reactive-resume
```

Create `/etc/httpd/conf.d/reactive-resume.conf`, replacing the hostname:

```apache
<VirtualHost *:80>
    ServerName resume.rean-it.com

    ProxyPreserveHost On
    RequestHeader set X-Forwarded-Proto "http"
    ProxyPass / http://127.0.0.1:3000/ connectiontimeout=5 timeout=120
    ProxyPassReverse / http://127.0.0.1:3000/
</VirtualHost>
```

Validate before reloading Apache:

```bash
sudo httpd -t
sudo systemctl reload httpd
```

Use the server's existing certificate automation to obtain a certificate for the
new hostname. If this server already uses Certbot's Apache integration, the usual
command is:

```bash
sudo certbot --apache -d resume.rean-it.com
```

Choose HTTPS redirection when prompted. Do not install a second certificate tool
without first checking how the server's existing certificates are managed. After
certificate configuration, inspect the generated TLS virtual host and ensure it
contains the proxy directives plus:

```apache
RequestHeader set X-Forwarded-Proto "https"
```

Finally, validate Apache and reload it:

```bash
sudo httpd -t
sudo systemctl reload httpd
```

The DNS record must resolve to this server before certificate issuance. Ensure
the new virtual host does not become Apache's default for unrelated domains.

## 7. Start and verify the service

```bash
cd /opt/reactive-resume
sudo docker compose ps
sudo docker compose logs --tail=100 reactive_resume
```

Check the local health endpoint from inside the app container:

```bash
sudo docker compose exec reactive_resume node -e \
  "fetch('http://127.0.0.1:3000/api/health').then(async r=>{console.log(r.status,await r.text());process.exit(r.ok?0:1)}).catch(e=>{console.error(e);process.exit(1)})"
```

Check the public endpoint:

```bash
curl -I https://resume.rean-it.com
```

Replace the example hostname. Then open the URL in a browser, create a test
account, create a resume, upload an image, and export the resume. If SMTP is
configured, also test email verification and password reset.

Useful diagnostic commands:

```bash
sudo docker compose ps
sudo docker compose logs --tail=200 reactive_resume
sudo docker compose logs --tail=200 postgres
sudo journalctl -u httpd --since "15 minutes ago" --no-pager
sudo ss -lntup
sudo ausearch -m AVC -ts recent
```

Expected public listeners are ports 80 and 443. Port 22 is also expected if SSH
uses its default port. Ports 3000, 5432, and 6379 must not listen publicly.

## 8. Create the first administrator account

Reactive Resume v5 uses Better Auth and stores an account role in PostgreSQL.
There is no supported bootstrap-admin command in v5.3.0, so create the account
through the normal registration page first and then promote that existing account
to `admin`. Do not insert a user directly into PostgreSQL; normal registration is
required to create and hash its credential records correctly.

### 8.1 Temporarily allow registration

Edit `/opt/reactive-resume/.env` and ensure these values are present:

```dotenv
FLAG_DISABLE_SIGNUPS=false
FLAG_DISABLE_EMAIL_AUTH=false
```

Recreate the application container so it reads the updated environment:

```bash
cd /opt/reactive-resume
sudo docker compose up -d --force-recreate reactive_resume
sudo docker compose ps reactive_resume
```

Open the following URL and register the intended administrator account with a
unique username and strong password:

```text
https://resume.rean-it.com/auth/register
```

Reactive Resume v5.3.0 accepts passwords from 8 through 64 characters. Verify the
email address if SMTP is configured. If SMTP is disabled, verification messages
are written to the application logs, but this release does not require email
verification before login.

### 8.2 Promote the registered account

Open PostgreSQL's interactive console from inside its container:

```bash
cd /opt/reactive-resume
sudo docker compose exec postgres \
  sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
```

At the `psql` prompt, list the accounts and carefully identify the exact email:

```sql
SELECT id, email, username, role, email_verified
FROM "user"
ORDER BY created_at;
```

Replace `you@rean-it.com` below with that exact email, then promote only that
account:

```sql
BEGIN;

UPDATE "user"
SET role = 'admin', updated_at = NOW()
WHERE lower(email) = lower('you@rean-it.com')
RETURNING id, email, username, role;
```

The `UPDATE` must return exactly one row with role `admin`. If it is the correct
account, save the change:

```sql
COMMIT;
```

If it returns no row or the wrong account, discard the change instead:

```sql
ROLLBACK;
```

Correct the email and try again if necessary. Exit PostgreSQL with:

```sql
\q
```

Sign out of Reactive Resume and sign in again so the new role is reflected in a
fresh session.

> **Admin UI note:** v5.3.0 includes Better Auth's admin authorization endpoints,
> but Reactive Resume does not currently expose a general user-management page in
> its web interface. The `admin` role does not make other users' resumes appear in
> the dashboard. A normal `user` role is sufficient to create and manage that
> account's own resumes.

### 8.3 Close public registration

For a private instance, edit `/opt/reactive-resume/.env` again and set:

```dotenv
FLAG_DISABLE_SIGNUPS=true
```

Apply and verify the change:

```bash
cd /opt/reactive-resume
sudo docker compose up -d --force-recreate reactive_resume
sudo docker compose ps reactive_resume
```

Confirm that `https://resume.rean-it.com/auth/register` no longer permits a new
account. Keep API rate limiting enabled by leaving
`FLAG_DISABLE_API_RATE_LIMIT=false`.

## 9. Backups

Back up PostgreSQL and uploaded application data together. The following creates
files below `/opt/reactive-resume/backups`:

```bash
cd /opt/reactive-resume
sudo install -d -m 0700 backups
STAMP=$(date -u +%Y%m%dT%H%M%SZ)

sudo docker compose exec -T postgres \
  sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' \
  > "backups/postgres-${STAMP}.dump"

sudo docker run --rm \
  -v reactive_resume_app_data:/source:ro \
  -v "$PWD/backups:/backup:Z" \
  alpine:3.22 \
  tar -czf "/backup/app-data-${STAMP}.tar.gz" -C /source .

sudo cp .env "backups/env-${STAMP}"
sudo chmod 0600 "backups/env-${STAMP}"
sudo sha256sum backups/*"${STAMP}"* > "backups/SHA256SUMS-${STAMP}"
```

Because `.env` contains credentials, encrypt it before moving backups off the
server. Copy backups to separate, access-controlled storage and test restoration
regularly. A backup stored only on this server is not sufficient.

To restore, first stop the application and take a fresh safety backup. Restore
into an empty database with `pg_restore`, restore the application-data archive to
the `reactive_resume_app_data` volume, and then restart the stack. Restoration
overwrites production state, so perform it only in a scheduled recovery window.

Redis contains agent workspace stream data but is not the primary application
database. If that feature is operationally important, also snapshot the
`reactive_resume_redis_data` volume.

## 10. Upgrade and rollback

Read the [Reactive Resume releases](https://github.com/reactive-resume/app/releases)
and migration notes before every upgrade. Never replace the pinned application
tag with `latest` in production.

After taking a verified backup, change only the image tag in `compose.yaml`, then:

```bash
cd /opt/reactive-resume
sudo docker compose config --quiet
sudo docker compose pull reactive_resume
sudo docker compose up -d
sudo docker compose ps
sudo docker compose logs --tail=200 reactive_resume
```

Complete the browser checks from section 7. If the release supports rollback,
restore the previous image tag and run `sudo docker compose up -d`. If an upgrade
changed database data incompatibly, restore both the database and application
data from the matching pre-upgrade backup.

Update the supporting images and Oracle Linux packages during a maintenance
window, with backups taken first:

```bash
sudo dnf update -y
cd /opt/reactive-resume
sudo docker compose pull
sudo docker compose up -d
sudo docker image prune -f
```

## 11. Operations checklist

- Monitor disk space with `df -h` and Docker usage with `sudo docker system df`.
- Alert on an unhealthy or restarting container.
- Keep Oracle Linux and Docker security updates current.
- Retain encrypted, off-server database and upload backups.
- Test restore procedures on a separate server.
- Review Reactive Resume release notes before upgrades.
- Review application users periodically and disable public signup when possible.
- Never expose PostgreSQL, Redis, or the application container directly.
- Leave SELinux enforcing and `firewalld` enabled.

## References

- [Reactive Resume repository](https://github.com/reactive-resume/app)
- [Reactive Resume self-hosting documentation](https://docs.rxresu.me)
- [Reactive Resume releases](https://github.com/reactive-resume/app/releases)
- [Docker Engine installation for RPM-based systems](https://docs.docker.com/engine/install/centos/)
- [Docker Compose plugin installation](https://docs.docker.com/compose/install/linux/)
- [Oracle Linux 9 firewalld documentation](https://docs.oracle.com/en/operating-systems/oracle-linux/9/firewall/firewall-ConfiguringfirewalldZones.html)
