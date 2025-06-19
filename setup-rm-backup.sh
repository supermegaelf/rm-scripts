#!/bin/bash

SCRIPT_URL="https://raw.githubusercontent.com/supermegaelf/rm-scripts/main/rm-backup.sh"
SCRIPT_DIR="/root/scripts"
SCRIPT_PATH="$SCRIPT_DIR/rm-backup.sh"

if [ ! -d "$SCRIPT_DIR" ]; then
    echo "Creating directory $SCRIPT_DIR..."
    mkdir -p "$SCRIPT_DIR"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create directory $SCRIPT_DIR"
        exit 1
    fi
fi

echo "Downloading rm-backup.sh from $SCRIPT_URL..."
wget -O "$SCRIPT_PATH" "$SCRIPT_URL"
if [ $? -ne 0 ]; then
    echo "Error: Failed to download rm-backup.sh"
    exit 1
fi

chmod 700 "$SCRIPT_PATH"
if [ $? -ne 0 ]; then
    echo "Error: Failed to set permissions on $SCRIPT_PATH"
    exit 1
fi

echo "Running rm-backup.sh to configure variables..."
/bin/bash "$SCRIPT_PATH"
if [ $? -ne 0 ]; then
    echo "Error: rm-backup.sh failed to execute"
    exit 1
fi

echo "Verifying cron setup..."
if grep -q "$SCRIPT_PATH" /etc/crontab; then
    echo "Cron job successfully added to /etc/crontab"
else
    echo "Error: Cron job was not added to /etc/crontab"
    exit 1
fi

echo "Restarting cron service..."
systemctl restart cron 2>/dev/null || service cron restart 2>/dev/null
if [ $? -ne 0 ]; then
    echo "Warning: Failed to restart cron service, changes may not apply until next reboot"
fi

echo "Setup completed successfully! rm-backup.sh is configured in $SCRIPT_PATH and scheduled to run hourly."
