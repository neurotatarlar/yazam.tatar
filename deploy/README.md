# Deployment (demo + production)

This repo uses lightweight VPS deploys (no Docker) through GitHub Actions with two environments:
- `demo`: deployed on push to `master`, served under `/app` with API at `/app/api`
- `production`: deployed on push to `release`, served from `/` with API at `/api`

## Paths and services
- Backend venv: `/opt/gec_tt/venv`
- Backend config: `/opt/gec_tt/.env`
- Web root: `/var/www/gec_tt`
- Backend systemd: `gec-tt-backend`
- VPN policy systemd: `gec-tt-vpn-policy`

## Workflows
- `environment bootstrap` (`.github/workflows/dev-init.yml`): manual bootstrap for `demo` or `production`
- `environment deploy` (`.github/workflows/dev-deploy.yml`):
  - `master` -> deploy `demo`
  - `release` -> deploy `production`
- `release package` (`.github/workflows/release.yml`): manual tagged package release

## VPS preparation (first run)
1) Install packages:
```
sudo apt-get update
sudo apt-get install -y python3 python3-venv python3-pip nginx wireguard
```

2) Create deploy user and SSH access:
```
sudo useradd --create-home --shell /bin/bash gec-tt-bot
sudo mkdir -p /home/gec-tt-bot/.ssh
sudo tee /home/gec-tt-bot/.ssh/authorized_keys < /path/to/gec_tt_bot.pub
sudo chown -R gec-tt-bot:gec-tt-bot /home/gec-tt-bot/.ssh
sudo chmod 700 /home/gec-tt-bot/.ssh
sudo chmod 600 /home/gec-tt-bot/.ssh/authorized_keys
```

3) Allow passwordless sudo for deploy operations (`visudo`):
```
gec-tt-bot ALL=NOPASSWD:/bin/systemctl restart gec-tt-backend,/bin/systemctl reload nginx,/usr/sbin/nginx -t,/bin/systemctl daemon-reload,/bin/systemctl enable gec-tt-backend,/bin/systemctl enable wg-quick@wg0,/bin/systemctl disable wg-quick@wg0,/bin/systemctl start wg-quick@wg0,/bin/systemctl stop wg-quick@wg0,/bin/systemctl enable gec-tt-vpn-policy,/bin/systemctl disable gec-tt-vpn-policy,/bin/systemctl start gec-tt-vpn-policy,/bin/systemctl stop gec-tt-vpn-policy,/usr/bin/apt-get update,/usr/bin/apt-get install,/usr/bin/install,/usr/bin/tee,/usr/sbin/ip,/usr/sbin/nft,/bin/cp,/bin/chmod,/bin/chown,/bin/mkdir,/bin/sed
```

## GitHub environments and secrets
Create GitHub environments: `demo`, `production`.

Per environment, define secrets:
- `DEPLOY_HOST`
- `DEPLOY_USER`
- `DEPLOY_SSH_KEY`
- `DEPLOY_SSH_PORT`
- `GEMINI_API_KEYS`
- `WG_CONFIG` (optional; if set, bootstrap writes `/etc/wireguard/wg0.conf` and enables VPN services)

Per environment, optional vars:
- `NGINX_SITE` (override target nginx server file)
- `MODEL_BACKEND` (default `gemini`)
- `GEMINI_MODEL` (default `gemini-3-flash-preview`)

Defaults by environment if `NGINX_SITE` is not set:
- `demo` -> `/etc/nginx/sites-available/gec-annotation.conf`
- `production` -> `/etc/nginx/sites-available/gec-tt.conf`

## Nginx snippets
- Demo path routing: `deploy/nginx/gec-tt-app.conf`
- Production root routing: `deploy/nginx/gec-tt-root.conf`
- Brotli add-on: `deploy/nginx/gec-tt-brotli.conf`

## SSL (production)
After DNS `A`/`AAAA` for `yazam.tatar` points to production host and ports `80/443` are open:
1) Obtain certificate (example):
```
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d yazam.tatar -d www.yazam.tatar
```
2) Verify auto-renew:
```
sudo certbot renew --dry-run
```
