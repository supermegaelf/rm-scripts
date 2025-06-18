#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Fixing SSL Certificate Paths ===${NC}"

# Load variables
if [ -f "remnawave-vars.sh" ]; then
    source remnawave-vars.sh
    echo -e "${GREEN}✓ Variables loaded${NC}"
else
    echo -e "${RED}remnawave-vars.sh not found!${NC}"
    exit 1
fi

echo
echo -e "${YELLOW}Current domain configuration:${NC}"
echo "PANEL_DOMAIN: $PANEL_DOMAIN"
echo "SUB_DOMAIN: $SUB_DOMAIN"

# Check which certificate directories actually contain valid certificates
echo
echo -e "${YELLOW}Checking for valid certificates...${NC}"

# Check if certificates exist in the correct locations
if [ -f "/etc/letsencrypt/live/$PANEL_DOMAIN/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/$PANEL_DOMAIN/privkey.pem" ]; then
    PANEL_CERT_DIR="$PANEL_DOMAIN"
    echo -e "${GREEN}✓ Found valid certificates for panel in: /etc/letsencrypt/live/$PANEL_DOMAIN${NC}"
elif [ -f "/etc/letsencrypt/live/familiartaste.xyz/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/familiartaste.xyz/privkey.pem" ]; then
    PANEL_CERT_DIR="familiartaste.xyz"
    echo -e "${GREEN}✓ Found valid certificates for panel in: /etc/letsencrypt/live/familiartaste.xyz${NC}"
else
    echo -e "${RED}✗ No valid certificates found for panel domain${NC}"
    PANEL_CERT_DIR=""
fi

if [ -f "/etc/letsencrypt/live/$SUB_DOMAIN/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/$SUB_DOMAIN/privkey.pem" ]; then
    SUB_CERT_DIR="$SUB_DOMAIN"
    echo -e "${GREEN}✓ Found valid certificates for sub in: /etc/letsencrypt/live/$SUB_DOMAIN${NC}"
elif [ -f "/etc/letsencrypt/live/familiartaste.info/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/familiartaste.info/privkey.pem" ]; then
    SUB_CERT_DIR="familiartaste.info"
    echo -e "${GREEN}✓ Found valid certificates for sub in: /etc/letsencrypt/live/familiartaste.info${NC}"
else
    echo -e "${RED}✗ No valid certificates found for sub domain${NC}"
    SUB_CERT_DIR=""
fi

# Update docker-compose.yml with correct paths
if [ -n "$PANEL_CERT_DIR" ] && [ -n "$SUB_CERT_DIR" ]; then
    echo
    echo -e "${YELLOW}Updating docker-compose.yml with correct certificate paths...${NC}"
    
    # Backup original file
    cp /opt/remnawave/docker-compose.yml /opt/remnawave/docker-compose.yml.backup
    
    # Update certificate paths in docker-compose.yml
    sed -i "s|/etc/letsencrypt/live/[^/]*/fullchain.pem:/etc/nginx/ssl/$PANEL_DOMAIN/fullchain.pem|/etc/letsencrypt/live/$PANEL_CERT_DIR/fullchain.pem:/etc/nginx/ssl/$PANEL_DOMAIN/fullchain.pem|g" /opt/remnawave/docker-compose.yml
    sed -i "s|/etc/letsencrypt/live/[^/]*/privkey.pem:/etc/nginx/ssl/$PANEL_DOMAIN/privkey.pem|/etc/letsencrypt/live/$PANEL_CERT_DIR/privkey.pem:/etc/nginx/ssl/$PANEL_DOMAIN/privkey.pem|g" /opt/remnawave/docker-compose.yml
    sed -i "s|/etc/letsencrypt/live/[^/]*/fullchain.pem:/etc/nginx/ssl/$SUB_DOMAIN/fullchain.pem|/etc/letsencrypt/live/$SUB_CERT_DIR/fullchain.pem:/etc/nginx/ssl/$SUB_DOMAIN/fullchain.pem|g" /opt/remnawave/docker-compose.yml
    sed -i "s|/etc/letsencrypt/live/[^/]*/privkey.pem:/etc/nginx/ssl/$SUB_DOMAIN/privkey.pem|/etc/letsencrypt/live/$SUB_CERT_DIR/privkey.pem:/etc/nginx/ssl/$SUB_DOMAIN/privkey.pem|g" /opt/remnawave/docker-compose.yml
    
    echo -e "${GREEN}✓ docker-compose.yml updated${NC}"
    
    # Show the updated lines
    echo
    echo -e "${YELLOW}Updated certificate mounts:${NC}"
    grep -E "(fullchain|privkey)" /opt/remnawave/docker-compose.yml | grep letsencrypt
    
    # Restart containers
    echo
    echo -e "${YELLOW}Restarting containers with correct certificate paths...${NC}"
    cd /opt/remnawave
    docker compose down
    docker compose up -d
    
    echo
    echo -e "${GREEN}✓ Containers restarted${NC}"
    
    # Wait for services
    echo -e "${YELLOW}Waiting for services to start...${NC}"
    sleep 10
    
    # Check status
    docker compose ps
    
else
    echo
    echo -e "${RED}Cannot proceed - valid certificates not found${NC}"
    echo -e "${YELLOW}Please check the certificate files manually:${NC}"
    echo "ls -la /etc/letsencrypt/live/"
    echo
    echo -e "${YELLOW}If certificates exist in different locations, manually update docker-compose.yml${NC}"
fi
