#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Xray Configuration Setup ===${NC}"

# Load environment variables
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
if [ -z "$PANEL_DOMAIN" ] || [ -z "$SELFSTEAL_DOMAIN" ] || [ -z "$SUPERADMIN_USERNAME" ] || [ -z "$SUPERADMIN_PASSWORD" ] || [ -z "$cookies_random1" ] || [ -z "$cookies_random2" ]; then
    echo -e "${RED}Required variables are missing!${NC}"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}jq is not installed!${NC}"
    echo -e "${YELLOW}Installing jq...${NC}"
    apt-get update && apt-get install -y jq
fi

# Set domain URL
domain_url="127.0.0.1:3000"

# Registration
echo
echo -e "${YELLOW}Registering admin user...${NC}"
register_response=$(curl -s -X POST "http://$domain_url/api/auth/register" \
    -H "Authorization: Bearer " \
    -H "Content-Type: application/json" \
    -H "Host: $PANEL_DOMAIN" \
    -H "X-Forwarded-For: 127.0.0.1" \
    -H "X-Forwarded-Proto: https" \
    -d "{\"username\":\"$SUPERADMIN_USERNAME\",\"password\":\"$SUPERADMIN_PASSWORD\"}")

token=$(echo "$register_response" | jq -r '.response.accessToken')

if [ -z "$token" ] || [ "$token" = "null" ]; then
    echo -e "${RED}Failed to register or get token!${NC}"
    echo -e "${YELLOW}Response: $register_response${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Admin user registered successfully${NC}"

# Get public key
echo
echo -e "${YELLOW}Getting public key...${NC}"
api_response=$(curl -s -X GET "http://$domain_url/api/keygen" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -H "Host: $PANEL_DOMAIN" \
    -H "X-Forwarded-For: 127.0.0.1" \
    -H "X-Forwarded-Proto: https")

pubkey=$(echo "$api_response" | jq -r '.response.pubKey')

if [ -z "$pubkey" ] || [ "$pubkey" = "null" ]; then
    echo -e "${RED}Failed to get public key!${NC}"
    echo -e "${YELLOW}Response: $api_response${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Public key obtained${NC}"

# Generate Xray keys
echo
echo -e "${YELLOW}Generating Xray keys...${NC}"
docker run --rm ghcr.io/xtls/xray-core x25519 > /tmp/xray_keys.txt 2>&1
keys=$(cat /tmp/xray_keys.txt)
rm -f /tmp/xray_keys.txt
private_key=$(echo "$keys" | grep "Private key:" | awk '{print $3}')
public_key=$(echo "$keys" | grep "Public key:" | awk '{print $3}')

if [ -z "$private_key" ] || [ -z "$public_key" ]; then
    echo -e "${RED}Failed to generate Xray keys!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Xray keys generated${NC}"

# Create Xray configuration
echo
echo -e "${YELLOW}Creating Xray configuration...${NC}"
short_id=$(openssl rand -hex 8)
config_file="/opt/remnawave/config.json"

cat > "$config_file" <<EOL
{
    "log": {
        "loglevel": "warning"
    },
    "dns": {
        "queryStrategy": "ForceIPv4",
        "servers": [
            {
                "address": "https://dns.google/dns-query",
                "skipFallback": false
            }
        ]
    },
    "inbounds": [
        {
            "tag": "VLESS Reality Steal Oneself",
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [],
                "decryption": "none"
            },
            "sniffing": {
                "enabled": true,
                "destOverride": [
                    "http",
                    "tls",
                    "quic"
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "xver": 1,
                    "dest": "/dev/shm/nginx.sock",
                    "spiderX": "",
                    "shortIds": [
                        "$short_id"
                    ],
                    "publicKey": "$public_key",
                    "privateKey": "$private_key",
                    "serverNames": [
                        "$SELFSTEAL_DOMAIN"
                    ]
                }
            }
        }
    ],
    "outbounds": [
        {
            "tag": "DIRECT",
            "protocol": "freedom"
        },
        {
            "tag": "BLOCK",
            "protocol": "blackhole"
        }
    ],
    "routing": {
        "rules": [
            {
                "ip": [
                    "geoip:private"
                ],
                "type": "field",
                "outboundTag": "BLOCK"
            },
            {
                "type": "field",
                "protocol": [
                    "bittorrent"
                ],
                "outboundTag": "BLOCK"
            }
        ]
    }
}
EOL

echo -e "${GREEN}✓ Xray configuration created${NC}"

# Update configuration
echo
echo -e "${YELLOW}Updating Xray configuration...${NC}"
new_config=$(cat "$config_file")
update_response=$(curl -s -X PUT "http://$domain_url/api/xray" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -H "Host: $PANEL_DOMAIN" \
    -H "X-Forwarded-For: 127.0.0.1" \
    -H "X-Forwarded-Proto: https" \
    -d "$new_config")

# Check if update was successful
if echo "$update_response" | jq -e '.ok' > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Xray configuration updated successfully${NC}"
else
    echo -e "${RED}Failed to update Xray configuration!${NC}"
    echo -e "${YELLOW}Response: $update_response${NC}"
fi

# Clean up
rm -f "$config_file"

# Display summary
echo
echo -e "${GREEN}=== Xray Setup Complete! ===${NC}"
