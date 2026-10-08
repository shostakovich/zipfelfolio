# Deploy

One container on the home server behind Caddy at `https://folio.rocu.de`. Passkeys need exactly
this origin: use the host name, not the LAN IP.

## Image

- CI publishes `ghcr.io/shostakovich/zipfelfolio:latest` and `:sha-<commit>` on every push to `main`
  once the tests pass (`.github/workflows/docker.yml`), `linux/amd64` only.
- GHCR creates the package as private: make it public once in the package settings, or
  `docker login ghcr.io` on the host.
- The container runs pending migrations on start (`bin/migrate`), then the server on port 4000.
- `GET /up` answers 200 when the database answers, 503 otherwise.

## First setup

```sh
mkdir -p /web/config/zipfelfolio /web/data/zipfelfolio
chown 1000:1000 /web/data/zipfelfolio
cp docker-compose.yml /web/config/zipfelfolio/compose.yml
ss -ltn | grep -q ':4100 ' && echo "port 4100 is taken: change it in compose.yml and Caddy"
```

`/web/config/zipfelfolio/.env`:

```sh
SECRET_KEY_BASE=...        # openssl rand -hex 64
SMTP_HOST=...
SMTP_PORT=587              # 465 for TLS from the start
SMTP_USERNAME=...
SMTP_PASSWORD=...
MAIL_FROM=folio@rocu.de
```

Caddy (`/web/config/caddy/Caddyfile`, TLS settings as for the other `*.rocu.de` sites), then
`caddy reload`:

```caddy
folio.rocu.de {
	reverse_proxy 192.168.8.100:4100
}
```

Caddy sets `X-Forwarded-Proto: https`; only then does the app treat a request as HTTPS (secure
cookies, HSTS).

Start and create the first user, who then signs in with a link by email:

```sh
cd /web/config/zipfelfolio
docker compose pull && docker compose up -d
docker compose exec zipfelfolio bin/zipfelfolio eval 'Zipfelfolio.Release.create_user("robert@example.com")'
curl -fsS https://folio.rocu.de/up
```

The data under `/web/data/zipfelfolio` is in the nightly restic backup (`/web`). Never open the
SQLite file from the host while the container runs.

## Update

```sh
cd /web/config/zipfelfolio
docker compose stop
cp -a /web/data/zipfelfolio "/web/data/zipfelfolio-pre-update-$(date +%F-%H%M)"
docker compose pull && docker compose up -d
curl -fsS https://folio.rocu.de/up
```

Roll back with `ZIPFELFOLIO_TAG=sha-<commit>` in `.env` and the copied data.
