#!/bin/bash

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
LIGHT_GREEN='\033[1;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_input() {
    echo -n -e "${LIGHT_GREEN}$1${NC}"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

cd /opt/remnawave

# Check if install_vars.sh exists
if [[ ! -f "/opt/remnawave/install_vars.sh" ]]; then
    print_error "install_vars.sh not found. Please run config setup script first."
    exit 1
fi

# Load variables
source /opt/remnawave/install_vars.sh

# Load or create admin token
if [[ ! -f "/opt/remnawave/admin_token.txt" ]] || [[ ! -s "/opt/remnawave/admin_token.txt" ]]; then
    echo "Admin token not found, trying to get existing token via login..."
    
    # Try login first (user should already exist after deployment)
    LOGIN_RESPONSE=$(curl -s -X POST "http://127.0.0.1:3000/api/auth/login" \
        -H "Content-Type: application/json" \
        -H "Host: $PANEL_DOMAIN" \
        -H "X-Forwarded-For: 127.0.0.1" \
        -H "X-Forwarded-Proto: https" \
        -d "{\"username\":\"$SUPERADMIN_USERNAME\",\"password\":\"$SUPERADMIN_PASSWORD\"}")
    
    LOGIN_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.response.accessToken')
    
    if [ -n "$LOGIN_TOKEN" ] && [ "$LOGIN_TOKEN" != "null" ]; then
        echo "$LOGIN_TOKEN" > /opt/remnawave/admin_token.txt
        chmod 600 /opt/remnawave/admin_token.txt
        print_success "Token obtained via login"
    else
        print_error "Failed to get token via login"
        echo "Login response: $LOGIN_RESPONSE"
        print_error "Make sure the panel is running and credentials are correct"
        exit 1
    fi
fi

TOKEN=$(cat /opt/remnawave/admin_token.txt)

if [ -z "$TOKEN" ]; then
    print_error "Token is empty after creation!"
    exit 1
fi

print_success "Token loaded successfully"

# Generate X25519 keys for Reality
echo "Generating x25519 keys..."

XRAY_KEYS=$(docker run --rm ghcr.io/xtls/xray-core x25519)

PRIVATE_KEY=$(echo "$XRAY_KEYS" | grep "Private key:" | awk '{print $3}')
PUBLIC_KEY=$(echo "$XRAY_KEYS" | grep "Public key:" | awk '{print $3}')

if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    print_error "Key generation failed!"
    exit 1
fi

print_success "Keys generated successfully:"
echo "Private key: $PRIVATE_KEY"
echo "Public key: $PUBLIC_KEY"

cat > /opt/remnawave/xray_keys.txt <<EOL
PRIVATE_KEY=$PRIVATE_KEY
PUBLIC_KEY=$PUBLIC_KEY
EOL
chmod 600 /opt/remnawave/xray_keys.txt

# Prompt for selfsteal domain
print_input "Enter selfsteal domain for the node (e.g., node.example.com): "
read SELFSTEAL_DOMAIN

if [[ -z "$SELFSTEAL_DOMAIN" ]]; then
    print_error "Selfsteal domain cannot be empty"
    exit 1
fi

# Generate short ID
SHORT_ID=$(openssl rand -hex 8)

# Create Xray configuration
cat > /tmp/xray_config.json <<EOL
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
            "tag": "Steal",
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
                        "$SHORT_ID"
                    ],
                    "publicKey": "$PUBLIC_KEY",
                    "privateKey": "$PRIVATE_KEY",
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

print_success "Xray configuration created"

# Update Xray configuration in panel
echo "Updating Xray configuration..."

XRAY_CONFIG=$(cat /tmp/xray_config.json)

UPDATE_RESPONSE=$(curl -s -X PUT "http://127.0.0.1:3000/api/xray" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "Host: $PANEL_DOMAIN" \
    -H "X-Forwarded-For: 127.0.0.1" \
    -H "X-Forwarded-Proto: https" \
    -d "$XRAY_CONFIG")

if echo "$UPDATE_RESPONSE" | jq -e '.response.config' > /dev/null; then
    print_success "Xray configuration updated successfully"
else
    print_error "Failed to update Xray configuration"
    echo "Response: $UPDATE_RESPONSE"
    exit 1
fi

rm -f /tmp/xray_config.json

# Create node
echo "Creating node..."

NODE_ADDRESS="$SELFSTEAL_DOMAIN"

NODE_DATA=$(cat <<EOF
{
    "name": "Steal",
    "address": "$NODE_ADDRESS",
    "port": 2222,
    "isTrafficTrackingActive": false,
    "trafficLimitBytes": 0,
    "notifyPercent": 0,
    "trafficResetDay": 31,
    "excludedInbounds": [],
    "countryCode": "XX",
    "consumptionMultiplier": 1.0
}
EOF
)

NODE_RESPONSE=$(curl -s -X POST "http://127.0.0.1:3000/api/nodes" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "Host: $PANEL_DOMAIN" \
    -H "X-Forwarded-For: 127.0.0.1" \
    -H "X-Forwarded-Proto: https" \
    -d "$NODE_DATA")

if echo "$NODE_RESPONSE" | jq -e '.response.uuid' > /dev/null; then
    NODE_UUID=$(echo "$NODE_RESPONSE" | jq -r '.response.uuid')
    print_success "Node created successfully"
    echo "Node UUID: $NODE_UUID"
else
    print_error "Failed to create node"
    echo "Response: $NODE_RESPONSE"
    exit 1
fi

# Get inbound UUID
echo "Getting inbound UUID..."

INBOUNDS_RESPONSE=$(curl -s -X GET "http://127.0.0.1:3000/api/inbounds" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Host: $PANEL_DOMAIN" \
    -H "X-Forwarded-For: 127.0.0.1" \
    -H "X-Forwarded-Proto: https")

INBOUND_UUID=$(echo "$INBOUNDS_RESPONSE" | jq -r '.response[0].uuid')

if [ -z "$INBOUND_UUID" ] || [ "$INBOUND_UUID" == "null" ]; then
    print_error "Failed to get inbound UUID"
    echo "Response: $INBOUNDS_RESPONSE"
    exit 1
fi

print_success "Inbound UUID received: $INBOUND_UUID"

# Create host
echo "Creating host..."

HOST_DATA=$(cat <<EOF
{
    "inboundUuid": "$INBOUND_UUID",
    "remark": "Steal",
    "address": "$SELFSTEAL_DOMAIN",
    "port": 443,
    "path": "",
    "sni": "$SELFSTEAL_DOMAIN",
    "host": "$SELFSTEAL_DOMAIN",
    "alpn": null,
    "fingerprint": "chrome",
    "allowInsecure": false,
    "isDisabled": false
}
EOF
)

HOST_RESPONSE=$(curl -s -X POST "http://127.0.0.1:3000/api/hosts" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "Host: $PANEL_DOMAIN" \
    -H "X-Forwarded-For: 127.0.0.1" \
    -H "X-Forwarded-Proto: https" \
    -d "$HOST_DATA")

if echo "$HOST_RESPONSE" | jq -e '.response.uuid' > /dev/null; then
    HOST_UUID=$(echo "$HOST_RESPONSE" | jq -r '.response.uuid')
    print_success "Host created successfully"
    echo "Host UUID: $HOST_UUID"
else
    print_error "Failed to create host"
    echo "Response: $HOST_RESPONSE"
    exit 1
fi

# Save node configuration
cat > /opt/remnawave/node_info.txt <<EOL
========================================
NODE CONFIGURATION
========================================
Created: $(date)

Node Information:
- UUID: $NODE_UUID
- Name: Steal
- Address: $NODE_ADDRESS
- Port: 2222

Inbound Information:
- UUID: $INBOUND_UUID
- Tag: Steal

Host Information:
- UUID: $HOST_UUID
- Address: $SELFSTEAL_DOMAIN
- Port: 443

Reality Keys:
- Public Key: $PUBLIC_KEY
- Private Key: $PRIVATE_KEY
- Short ID: $SHORT_ID

SSL Certificate for Node:
SSL_CERT="$PUBLIC_KEY"

========================================
EOL

chmod 600 /opt/remnawave/node_info.txt

print_success "Node information saved to /opt/remnawave/node_info.txt"

# Restart containers to apply changes
echo "Restarting containers..."

cd /opt/remnawave

docker compose down

sleep 5

docker compose up -d

sleep 10

docker compose ps

print_success "Containers restarted"

echo "===================================="

print_success "Xray configuration completed successfully!"
echo ""
echo "IMPORTANT: This configuration is for external node connections."
echo "To connect an external node, use the following SSL certificate:"
echo "SSL_CERT=\"$PUBLIC_KEY\""
echo ""
echo "The external node should connect to this panel using the domain: $SELFSTEAL_DOMAIN"
