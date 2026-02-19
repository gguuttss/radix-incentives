#!/bin/bash
# Database backup script - run via cron daily
# Add to crontab: 0 3 * * * /opt/radix-incentives/scripts/backup.sh

set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/opt/radix-incentives/backups}"
COMPOSE_FILE="${COMPOSE_FILE:-/opt/radix-incentives/docker-compose.prod.yml}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

echo "[$(date)] Starting database backup..."

# Dump the database from the running postgres container
docker compose -f "$COMPOSE_FILE" exec -T postgres \
  pg_dump -U postgres -d radix-incentives --format=custom \
  > "$BACKUP_DIR/radix-incentives_${TIMESTAMP}.dump"

echo "[$(date)] Backup created: radix-incentives_${TIMESTAMP}.dump"

# Remove backups older than retention period
find "$BACKUP_DIR" -name "*.dump" -mtime +${RETENTION_DAYS} -delete

echo "[$(date)] Cleaned up backups older than ${RETENTION_DAYS} days"
echo "[$(date)] Backup complete"
