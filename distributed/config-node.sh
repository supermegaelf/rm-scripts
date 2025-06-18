#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Creating Configuration Files ===${NC}"

# Check if node-vars.sh exists
if [ ! -f "node-vars.sh" ]; then
    echo -e "${RED}Error: node-vars.sh not found!${NC}"
    echo -e "${YELLOW}Please run var-node.sh first to create the variables file.${NC}"
    exit 1
fi

# Load environment variables
echo -e "${YELLOW}Loading environment variables...${NC}"
source node-vars.sh

# Extract base domain from SELFSTEAL_DOMAIN (remove subdomain)
SELFSTEAL_BASE_DOMAIN=$(echo "$SELFSTEAL_DOMAIN" | awk -F. '{print $(NF-1)"."$NF}')

# Create directory if it doesn't exist
echo -e "${YELLOW}Creating /opt/remnawave directory...${NC}"
mkdir -p /opt/remnawave

# Create docker-compose.yml
echo -e "${YELLOW}Creating docker-compose.yml...${NC}"
cat > docker-compose.yml <<EOL
services:
  remnawave-nginx:
    image: nginx:1.26
    container_name: remnawave-nginx
    hostname: remnawave-nginx
    restart: always
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - /etc/letsencrypt/live/$SELFSTEAL_BASE_DOMAIN/fullchain.pem:/etc/nginx/ssl/$SELFSTEAL_DOMAIN/fullchain.pem:ro
      - /etc/letsencrypt/live/$SELFSTEAL_BASE_DOMAIN/privkey.pem:/etc/nginx/ssl/$SELFSTEAL_DOMAIN/privkey.pem:ro
      - /dev/shm:/dev/shm:rw
      - /var/www/html:/var/www/html:ro
    command: sh -c 'rm -f /dev/shm/nginx.sock && nginx -g "daemon off;"'
    network_mode: host
    depends_on:
      - remnanode
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'
  remnanode:
    image: remnawave/node:latest
    container_name: remnanode
    hostname: remnanode
    restart: always
    network_mode: host
    env_file:
      - path: /opt/remnawave/.env-node
        required: false
    volumes:
      - /dev/shm:/dev/shm:rw
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'
EOL

echo -e "${GREEN}✓ docker-compose.yml created!${NC}"

# Create nginx.conf
echo -e "${YELLOW}Creating nginx.conf...${NC}"
cat > /opt/remnawave/nginx.conf <<EOL
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ""      close;
}
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ecdh_curve X25519:prime256v1:secp384r1;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers on;
ssl_session_timeout 1d;
ssl_session_cache shared:MozSSL:10m;
server {
    server_name $SELFSTEAL_DOMAIN;
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;
    http2 on;
    ssl_certificate "/etc/nginx/ssl/$SELFSTEAL_DOMAIN/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$SELFSTEAL_DOMAIN/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$SELFSTEAL_DOMAIN/fullchain.pem";
    root /var/www/html;
    index index.html;
}
server {
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol default_server;
    server_name _;
    ssl_reject_handshake on;
    return 444;
}
EOL

echo -e "${GREEN}✓ nginx.conf created!${NC}"

# Copy nginx.conf to current directory for docker-compose
cp /opt/remnawave/nginx.conf ./nginx.conf

echo
echo -e "${GREEN}=== Configuration files created successfully! ===${NC}"
