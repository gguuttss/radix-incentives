# VPS Deployment Guide

Complete guide for deploying Radix Incentives on a single VPS with Docker Compose, replacing the previous Kubernetes/AWS setup.

## Architecture

Everything runs on a single VPS via Docker Compose:

| Service | Port | Access |
|---------|------|--------|
| **Incentives** (user dashboard) | 443 | Public via Caddy (HTTPS) |
| **Admin** (admin dashboard) | 3001 | Tailscale only |
| **Workers** (background jobs) | 3003 | Tailscale only (BullBoard UI at `/ui`) |
| **Streamer** (blockchain listener) | — | Internal only |
| **PostgreSQL** | 5432 | Tailscale only (for pgAdmin desktop) |
| **Redis** | — | Internal only |
| **pgAdmin** (web UI) | 5050 | Tailscale only |
| **Caddy** (reverse proxy) | 80/443 | Public |

**Security model**: UFW firewall only allows ports 22 (SSH), 80, and 443 from the public internet. All other ports (3001, 3003, 5050, 5432) are only reachable via Tailscale.

## Cost

~$15/month for a Hetzner CPX31 (4 vCPU, 8GB RAM, 160GB SSD). That's it.

## Prerequisites

Before starting, you need:

- [ ] A VPS (Hetzner CPX31 recommended, Ubuntu 24.04)
- [ ] A domain or free subdomain (e.g. DuckDNS)
- [ ] A Tailscale account (free, https://tailscale.com)
- [ ] A Radix DApp definition address (registered on-ledger with your domain as the claimed origin)
- [ ] `TOKEN_PRICE_SERVICE_API_KEY` from the Radix team

## Fresh Deployment (Step by Step)

### 1. SSH into the VPS

```bash
ssh root@YOUR_VPS_IP
```

### 2. Install Docker

```bash
curl -fsSL https://get.docker.com | sh
```

### 3. Install and authenticate Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up
# Opens a URL — authenticate in your browser
tailscale ip -4  # Note this IP for later
```

### 4. Set up the firewall

```bash
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
```

### 5. Clone the repo

```bash
git clone https://github.com/gguuttss/radix-incentives.git /opt/radix-incentives
cd /opt/radix-incentives
```

### 6. Configure environment

```bash
cp .env.prod.example .env.prod
nano .env.prod
```

Fill in the values:

| Variable | How to get it |
|----------|---------------|
| `POSTGRES_PASSWORD` | Generate: `openssl rand -hex 32` (no special characters!) |
| `INCENTIVES_URL` | `https://incentives.duckdns.org` (or your domain) |
| `DAPP_DEFINITION_ADDRESS` | Your on-ledger DApp definition address |
| `TOKEN_PRICE_SERVICE_API_KEY` | From the Radix team |
| `JWT_SECRET` | Generate: `openssl rand -base64 64` |

**Important**: The `POSTGRES_PASSWORD` must NOT contain `/`, `+`, or `=` characters (breaks the database URL). Use `openssl rand -hex 32` to generate a safe one.

### 7. Update the Caddyfile

```bash
nano Caddyfile
```

Replace the domain with yours:

```
your-domain.com {
    reverse_proxy incentives:3000
}
```

### 8. Set up DNS

Point your domain to the VPS IP address:
- **DuckDNS**: Go to duckdns.org, set your subdomain's IP to your VPS IP
- **Custom domain**: Create an A record pointing to your VPS IP

### 9. Deploy

```bash
chmod +x scripts/deploy.sh scripts/backup.sh
./scripts/deploy.sh
```

This will:
1. Build all Docker images (~5-10 minutes on first run)
2. Start PostgreSQL and Redis
3. Run database migrations
4. Start all application services
5. Start Caddy (auto-provisions SSL certificate)

### 10. Set up daily backups

```bash
crontab -e
```

Add this line:

```
0 3 * * * /opt/radix-incentives/scripts/backup.sh >> /var/log/radix-backup.log 2>&1
```

### 11. Seed the database

If this is a fresh deployment, you need to set up seasons, weeks, and activities through the admin panel at `http://<tailscale-ip>:3001`.

## Accessing Services

| Service | URL |
|---------|-----|
| Incentives (public) | `https://incentives.duckdns.org` |
| Admin dashboard | `http://<tailscale-ip>:3001` |
| BullBoard (job queues) | `http://<tailscale-ip>:3003/ui` |
| pgAdmin (web) | `http://<tailscale-ip>:5050` |
| PostgreSQL (desktop pgAdmin) | Host: `<tailscale-ip>`, Port: `5432`, User: `postgres` |

All Tailscale-only services require Tailscale to be installed and authenticated on your device.

## Common Operations

### View logs

```bash
cd /opt/radix-incentives

# All services
docker compose -f docker-compose.prod.yml --env-file .env.prod logs -f

# Specific service
docker compose -f docker-compose.prod.yml --env-file .env.prod logs -f incentives
docker compose -f docker-compose.prod.yml --env-file .env.prod logs -f workers
docker compose -f docker-compose.prod.yml --env-file .env.prod logs -f streamer
```

### Update to latest code

```bash
cd /opt/radix-incentives
git pull
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build
```

### Run database migrations

```bash
cd /opt/radix-incentives
docker compose -f docker-compose.prod.yml --env-file .env.prod run --rm migrate
```

### Restart a specific service

```bash
docker compose -f docker-compose.prod.yml --env-file .env.prod restart workers
```

### Stop everything

```bash
docker compose -f docker-compose.prod.yml --env-file .env.prod down
```

### Restore a database backup

```bash
# List available backups
ls /opt/radix-incentives/backups/

# Restore a specific backup
docker compose -f docker-compose.prod.yml --env-file .env.prod exec -T postgres \
  pg_restore -U postgres -d radix-incentives --clean --if-exists \
  < /opt/radix-incentives/backups/radix-incentives_YYYYMMDD_HHMMSS.dump
```

### Change domain

1. Update `INCENTIVES_URL` in `.env.prod`
2. Update the domain in `Caddyfile`
3. Restart: `docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build incentives && docker compose -f docker-compose.prod.yml --env-file .env.prod restart caddy`
4. Make sure the DApp definition on-ledger has the new domain as claimed origin

## Troubleshooting

### "database does not exist"
The `POSTGRES_DB: radix-incentives` env var in docker-compose.prod.yml auto-creates the database. If it still doesn't exist, the postgres volume may have been initialized without it:
```bash
docker compose -f docker-compose.prod.yml --env-file .env.prod down
docker volume rm radix-incentives_pgdata
./scripts/deploy.sh
```

### "password authentication failed"
Same fix — the postgres volume remembers the first password. Wipe and recreate:
```bash
docker compose -f docker-compose.prod.yml --env-file .env.prod down
docker volume rm radix-incentives_pgdata
./scripts/deploy.sh
```

### ROLA "invalidSignature" on wallet connect
The DApp definition address on-ledger must have your domain (e.g. `https://incentives.duckdns.org`) as a claimed website. Also verify `INCENTIVES_URL` in `.env.prod` matches exactly. Rebuild the incentives image after changing:
```bash
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build incentives
```

### "Invalid URL" in DATABASE_URL
The `POSTGRES_PASSWORD` contains special characters (`/`, `+`, `=`). Regenerate with `openssl rand -hex 32` and wipe the postgres volume (see above).

### Caddy not getting SSL certificate
- Make sure DNS is pointed to your VPS IP
- Make sure ports 80 and 443 are open: `ufw status`
- Check Caddy logs: `docker compose -f docker-compose.prod.yml --env-file .env.prod logs caddy`

## Files Overview

| File | Purpose |
|------|---------|
| `docker-compose.prod.yml` | All services: postgres, redis, incentives, admin, workers, streamer, pgadmin, caddy |
| `Caddyfile` | Reverse proxy config with auto-HTTPS |
| `.env.prod` | Production secrets (not in git) |
| `.env.prod.example` | Template for `.env.prod` |
| `scripts/deploy.sh` | One-command setup for a fresh VPS |
| `scripts/backup.sh` | Daily PostgreSQL backup with 14-day retention |
| `dockerfiles/` | Multi-stage Docker builds for each service |
| `postgres-init/init-db.sh` | Creates databases on first PostgreSQL startup |

## Migration from Kubernetes

This setup replaces:
- **AWS EKS clusters** → Single VPS with Docker Compose
- **Helm charts** → `docker-compose.prod.yml`
- **AWS Secrets Manager + Vault** → `.env.prod` file
- **OAuth2 proxy / Tailscale auth** → Tailscale + UFW firewall
- **Prometheus / AlertManager** → `docker compose logs` (add monitoring later if needed)
- **Jenkins CI/CD** → `git pull && docker compose up -d --build`

Monthly cost went from ~$400 (Kubernetes/AWS) to ~$15 (Hetzner VPS).
