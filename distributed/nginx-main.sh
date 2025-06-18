#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Panel Nginx Setup and Container Launch ===${NC}"

# Load environment variables if remnawave-vars.sh exists
if [ -f "remnawave-vars.sh" ]; then
    echo -e "${YELLOW}Loading existing environment variables...${NC}"
    source remnawave-vars.sh
    echo -e "${GREEN}✓ Environment variables loaded${NC}"
else
    echo -e "${RED}Error: remnawave-vars.sh not found!${NC}"
    echo -e "${YELLOW}Please run var-main.sh first${NC}"
    exit 1
fi

# Check required variables
if [ -z "$PANEL_DOMAIN" ] || [ -z "$SUB_DOMAIN" ] || [ -z "$cookies_random1" ] || [ -z "$cookies_random2" ]; then
    echo -e "${RED}Required variables are missing!${NC}"
    exit 1
fi

# Create nginx.conf
echo
echo -e "${YELLOW}Creating nginx.conf for panel...${NC}"
cat > /opt/remnawave/nginx.conf <<EOL
upstream remnawave {
    server 127.0.0.1:3000;
}
upstream json {
    server 127.0.0.1:3010;
}
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ""      close;
}
map \$http_cookie \$auth_cookie {
    default 0;
    "~*${cookies_random1}=${cookies_random2}" 1;
}
map \$arg_${cookies_random1} \$auth_query {
    default 0;
    "${cookies_random2}" 1;
}
map "\$auth_cookie\$auth_query" \$authorized {
    "~1" 1;
    default 0;
}
map \$arg_${cookies_random1} \$set_cookie_header {
    "${cookies_random2}" "${cookies_random1}=${cookies_random2}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=31536000";
    default "";
}
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ecdh_curve X25519:prime256v1:secp384r1;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers on;
ssl_session_timeout 1d;
ssl_session_cache shared:MozSSL:10m;
server {
    server_name $PANEL_DOMAIN;
    listen 443 ssl;
    http2 on;
    ssl_certificate "/etc/nginx/ssl/$PANEL_DOMAIN/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$PANEL_DOMAIN/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$PANEL_DOMAIN/fullchain.pem";
    add_header Set-Cookie \$set_cookie_header;
    location / {
        if (\$authorized = 0) {
            return 404;
        }
        proxy_http_version 1.1;
        proxy_pass http://remnawave;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
server {
    server_name $SUB_DOMAIN;
    listen 443 ssl;
    http2 on;
    ssl_certificate "/etc/nginx/ssl/$SUB_DOMAIN/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$SUB_DOMAIN/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$SUB_DOMAIN/fullchain.pem";
    location / {
        proxy_http_version 1.1;
        proxy_pass http://json;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        proxy_intercept_errors on;
        error_page 400 404 500 502 @redirect;
    }
    location @redirect {
        return 404;
    }
}
server {
    listen 443 ssl default_server;
    server_name _;
    ssl_reject_handshake on;
}
EOL

echo -e "${GREEN}✓ nginx.conf created!${NC}"

# Save cookie values for reference
echo
echo -e "${YELLOW}Saving authentication cookie values...${NC}"
cat > /opt/remnawave/auth-cookies.txt <<EOL
# Authentication Cookie Values
# Generated on $(date)
Cookie Name: ${cookies_random1}
Cookie Value: ${cookies_random2}

# Access URL with authentication:
# https://$PANEL_DOMAIN/?${cookies_random1}=${cookies_random2}
EOL
echo -e "${GREEN}✓ Cookie values saved to /opt/remnawave/auth-cookies.txt${NC}"

# Start containers
echo
echo -e "${YELLOW}Starting Docker containers...${NC}"
cd /opt/remnawave
docker compose up -d && docker compose logs -f &
LOGS_PID=$!

# Wait 20 seconds
sleep 20

# Kill logs viewing
kill $LOGS_PID 2>/dev/null

# Wait for service to be ready
echo
echo -e "${YELLOW}Waiting for service to be ready...${NC}"
until curl -s "http://127.0.0.1:3000/api/auth/register" \
    --header 'X-Forwarded-For: 127.0.0.1' \
    --header 'X-Forwarded-Proto: https' \
    > /dev/null; do
    sleep 10
done

echo -e "${GREEN}✓ Service is ready!${NC}"

# Display access information
echo
echo -e "${GREEN}=== Setup Complete! ===${NC}"
echo
echo -e "${BLUE}Panel Access URL:${NC}"
echo -e "${GREEN}https://$PANEL_DOMAIN/?${cookies_random1}=${cookies_random2}${NC}"
echo
echo -e "${BLUE}Admin Credentials:${NC}"
echo -e "${YELLOW}Username: $SUPERADMIN_USERNAME${NC}"
echo -e "${YELLOW}Password: $SUPERADMIN_PASSWORD${NC}"
