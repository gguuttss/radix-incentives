#!/bin/bash
# Deployment script for Radix Incentives on a fresh VPS
# Run as root or with sudo on Ubuntu/Debian

set -euo pipefail

APP_DIR="/opt/radix-incentives"
COMPOSE="docker compose -f docker-compose.prod.yml --env-file .env.prod"

echo "=== Radix Incentives VPS Setup ==="
echo ""

# 1. Install Docker if not present
if ! command -v docker &> /dev/null; then
  echo "[1/7] Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
else
  echo "[1/7] Docker already installed, skipping"
fi

# 2. Install Tailscale if not present
if ! command -v tailscale &> /dev/null; then
  echo "[2/7] Installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
  echo ""
  echo "  Run 'tailscale up' after this script finishes to authenticate."
  echo "  Then access admin/BullBoard via your Tailscale IP."
  echo ""
else
  echo "[2/7] Tailscale already installed"
  TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "not connected")
  echo "  Tailscale IP: $TAILSCALE_IP"
fi

# 3. Set up firewall (UFW)
echo "[3/7] Configuring firewall..."
if command -v ufw &> /dev/null; then
  ufw allow 22/tcp      # SSH
  ufw allow 80/tcp      # HTTP (public)
  ufw allow 443/tcp     # HTTPS (public)
  # Ports 3001 (admin) and 3003 (BullBoard) are NOT opened here.
  # They're only reachable via Tailscale, which bypasses UFW.
  ufw --force enable
  echo "  Firewall enabled: ports 22, 80, 443 open to public"
  echo "  Ports 3001, 3003 only accessible via Tailscale"
else
  echo "  WARNING: UFW not found. Install with: apt install ufw"
fi

# 4. Clone or update the repo
if [ ! -d "$APP_DIR" ]; then
  echo "[4/7] Cloning repository..."
  git clone https://github.com/radixdlt/radix-incentives.git "$APP_DIR"
else
  echo "[4/7] Updating repository..."
  cd "$APP_DIR"
  git pull
fi

cd "$APP_DIR"

# 5. Check for .env.prod
if [ ! -f "$APP_DIR/.env.prod" ]; then
  echo ""
  echo "[5/7] ERROR: .env.prod not found!"
  echo ""
  echo "  Copy the example and fill in your values:"
  echo "    cp .env.prod.example .env.prod"
  echo "    nano .env.prod"
  echo ""
  echo "  Then run this script again."
  exit 1
else
  echo "[5/7] .env.prod found"
fi

# 6. Build and start infrastructure
echo "[6/7] Building Docker images (this takes a few minutes on first run)..."
$COMPOSE build

echo "Starting infrastructure (postgres + redis)..."
$COMPOSE up -d postgres redis

echo "Waiting for database to be ready..."
until $COMPOSE exec -T postgres pg_isready -U postgres > /dev/null 2>&1; do
  sleep 2
done

# 7. Run migrations and start everything
echo "[7/7] Running database migrations..."
$COMPOSE run --rm migrate

echo "Starting all services..."
$COMPOSE up -d

echo ""
echo "=== Deployment complete! ==="
echo ""
echo "Services running:"
$COMPOSE ps
echo ""
echo "Access:"
echo "  Incentives (public):  http://$(curl -s ifconfig.me)"
echo "  Admin (Tailscale):    http://<tailscale-ip>:3001"
echo "  BullBoard (Tailscale): http://<tailscale-ip>:3003/ui"
echo ""
echo "If Tailscale is not yet connected, run:"
echo "  tailscale up"
echo ""
echo "Once you have a domain, update the Caddyfile:"
echo "  Replace ':80' with 'incentives.yourdomain.com'"
echo "  Then: $COMPOSE restart caddy"
echo ""
echo "Set up daily backups:"
echo "  crontab -e"
echo "  0 3 * * * $APP_DIR/scripts/backup.sh >> /var/log/radix-backup.log 2>&1"
echo ""
echo "Useful commands:"
echo "  View logs:     $COMPOSE logs -f"
echo "  View service:  $COMPOSE logs -f workers"
echo "  Restart:       $COMPOSE restart"
echo "  Stop:          $COMPOSE down"
echo "  Update:        git pull && $COMPOSE up -d --build"
echo "  Run migration: $COMPOSE run --rm migrate"
