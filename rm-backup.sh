#!/bin/bash

POSTGRES_USER="postgres"
POSTGRES_PASSWORD="postgres"
POSTGRES_DB="postgres"
TG_BOT_TOKEN=""
TG_CHAT_ID=""

if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ]; then
    read -p $'\033[32mPostgreSQL username (default is postgres, press Enter to use it): \033[0m' POSTGRES_USER_INPUT
    POSTGRES_USER=${POSTGRES_USER_INPUT:-postgres}
    read -sp $'\033[32mPostgreSQL password (default is postgres, press Enter to use it): \033[0m' POSTGRES_PASSWORD_INPUT
    echo
    POSTGRES_PASSWORD=${POSTGRES_PASSWORD_INPUT:-postgres}
    read -p $'\033[32mPostgreSQL database (default is postgres, press Enter to use it): \033[0m' POSTGRES_DB_INPUT
    POSTGRES_DB=${POSTGRES_DB_INPUT:-postgres}
    read -p $'\033[32mTelegram Bot Token: \033[0m' TG_BOT_TOKEN
    read -p $'\033[32mTelegram Chat ID: \033[0m' TG_CHAT_ID

    if [[ ! "$TG_BOT_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
        echo "Error: Invalid Telegram Bot Token format"
        exit 1
    fi
    if [[ ! "$TG_CHAT_ID" =~ ^-?[0-9]+$ ]]; then
        echo "Error: Invalid Telegram Chat ID format"
        exit 1
    fi

    sed -i "s/TG_BOT_TOKEN=\"\"/TG_BOT_TOKEN=\"$TG_BOT_TOKEN\"/" "$0"
    sed -i "s/TG_CHAT_ID=\"\"/TG_CHAT_ID=\"$TG_CHAT_ID\"/" "$0"

    if ! grep -q "/root/scripts/rm-backup.sh" /etc/crontab; then
        echo "0 */1 * * * root /bin/bash /root/scripts/rm-backup.sh >/dev/null 2>&1" | tee -a /etc/crontab
    fi
fi

if [[ ! "$TG_BOT_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
    echo "Error: Invalid Telegram Bot Token format"
    exit 1
fi

if [[ ! "$TG_CHAT_ID" =~ ^-?[0-9]+$ ]]; then
    echo "Error: Invalid Telegram Chat ID format"
    exit 1
fi

TEMP_DIR=$(mktemp -d)
if [ ! -d "$TEMP_DIR" ]; then
    echo "Error: Failed to create temporary directory"
    exit 1
fi
BACKUP_FILE="$TEMP_DIR/rm-backup-$(date +%d.%m.%Y_%H.%M).tar.gz"

POSTGRES_CONTAINER_NAME="remnawave-db"
if ! docker ps -q -f name="$POSTGRES_CONTAINER_NAME" | grep -q .; then
    echo "Error: Container $POSTGRES_CONTAINER_NAME is not running"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Create database backup directory
mkdir -p /opt/remnawave/db-backup/

# Create PostgreSQL database backup
echo "Creating PostgreSQL database backup..."
docker exec $POSTGRES_CONTAINER_NAME pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" > /opt/remnawave/db-backup/remnawave.sql 2>/tmp/remnawave_error.log
if [ $? -ne 0 ]; then
    echo "Error: Failed to create database backup"
    cat /tmp/remnawave_error.log
    rm -rf "$TEMP_DIR" /tmp/remnawave_error.log
    exit 1
fi
rm -f /tmp/remnawave_error.log

# Create compressed backup archive
echo "Creating backup archive..."
tar --exclude='/opt/remnawave/db-backup' \
    -cf "$TEMP_DIR/backup-remnawave.tar" \
    -C / \
    /opt/remnawave/.env \
    /opt/remnawave/docker-compose.yml \
    /opt/remnawave/nginx.conf \
    /opt/remnawave/remnawave-vars.sh \
    /etc/letsencrypt/live/ \
    /etc/letsencrypt/renewal/

# Add database backup to archive
tar -rf "$TEMP_DIR/backup-remnawave.tar" -C / /opt/remnawave/db-backup/remnawave.sql

# Compress the archive
gzip "$TEMP_DIR/backup-remnawave.tar"
mv "$TEMP_DIR/backup-remnawave.tar.gz" "$BACKUP_FILE"

# Send to Telegram
echo "Sending backup to Telegram..."
curl -F chat_id="$TG_CHAT_ID" \
     -F document=@"$BACKUP_FILE" \
     https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument

# Check if upload was successful
if [ $? -eq 0 ]; then
    echo
    echo "✓ Backup successfully sent to Telegram"
    # Clean up database backup directory
    rm -rf /opt/remnawave/db-backup/remnawave.sql
else
    echo
    echo "✖ Failed to send backup to Telegram"
fi

# Clean up temporary files
rm -rf "$TEMP_DIR"
