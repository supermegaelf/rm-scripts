#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Remnawave backup setup script
echo
echo -e "${PURPLE}=======================${NC}"
echo -e "${NC}Remnawave Backup Setup${NC}"
echo -e "${PURPLE}=======================${NC}"
echo

set -e

echo -e "${GREEN}================================${NC}"
echo -e "${NC}1. Preparing backup environment${NC}"
echo -e "${GREEN}================================${NC}"
echo

SCRIPT_URL="https://raw.githubusercontent.com/supermegaelf/rm-scripts/main/rm-backup.sh"
SCRIPT_DIR="/root/scripts"
SCRIPT_PATH="$SCRIPT_DIR/rm-backup.sh"

if [ ! -d "$SCRIPT_DIR" ]; then
    echo -e "${CYAN}Creating directory $SCRIPT_DIR...${NC}"
    mkdir -p "$SCRIPT_DIR"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to create directory $SCRIPT_DIR${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Directory created successfully${NC}"
else
    echo -e "${YELLOW}Directory $SCRIPT_DIR already exists${NC}"
fi

echo
echo -e "${GREEN}=============================${NC}"
echo -e "${NC}2. Downloading backup script${NC}"
echo -e "${GREEN}=============================${NC}"
echo

echo -e "${CYAN}Downloading rm-backup.sh from $SCRIPT_URL...${NC}"
wget -O "$SCRIPT_PATH" "$SCRIPT_URL"
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to download rm-backup.sh${NC}"
    exit 1
fi

echo -e "${CYAN}Setting permissions...${NC}"
chmod 700 "$SCRIPT_PATH"
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to set permissions on $SCRIPT_PATH${NC}"
    exit 1
fi

echo
echo -e "${GREEN}-----------------------------------------${NC}"
echo -e "${NC}✓ Backup script downloaded successfully!${NC}"
echo -e "${GREEN}-----------------------------------------${NC}"
echo

echo -e "${GREEN}=============================${NC}"
echo -e "${NC}3. Configuring backup script${NC}"
echo -e "${GREEN}=============================${NC}"
echo

echo -e "${CYAN}Running rm-backup.sh to configure variables...${NC}"
/bin/bash "$SCRIPT_PATH"
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: rm-backup.sh failed to execute${NC}"
    exit 1
fi

echo
echo -e "${GREEN}-----------------------------------------------${NC}"
echo -e "${NC}✓ Backup configuration completed successfully!${NC}"
echo -e "${GREEN}-----------------------------------------------${NC}"
echo

echo -e "${GREEN}==========================${NC}"
echo -e "${NC}4. Verifying installation${NC}"
echo -e "${GREEN}==========================${NC}"
echo

echo -e "${CYAN}Verifying cron setup...${NC}"
if grep -q "$SCRIPT_PATH" /etc/crontab; then
    echo -e "${GREEN}✓ Cron job successfully added to /etc/crontab${NC}"
else
    echo -e "${RED}Error: Cron job was not added to /etc/crontab${NC}"
    exit 1
fi

echo
echo -e "${CYAN}Restarting cron service...${NC}"
systemctl restart cron 2>/dev/null || service cron restart 2>/dev/null
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}Warning: Failed to restart cron service, changes may not apply until next reboot${NC}"
else
    echo -e "${GREEN}✓ Cron service restarted successfully${NC}"
fi

echo
echo -e "${GREEN}--------------------------------${NC}"
echo -e "${NC}✓ Setup completed successfully!${NC}"
echo -e "${GREEN}--------------------------------${NC}"
echo
echo -e "${CYAN}Backup script location: ${WHITE}$SCRIPT_PATH${NC}"
echo -e "${CYAN}Backup schedule: ${WHITE}Hourly execution${NC}"
echo
