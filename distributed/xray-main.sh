#!/bin/bash

# Remnawave registration and API configuration script
# Section 6: Registration and configuration via API

set -e

echo "========================================="
echo "Remnawave API Configuration"
echo "========================================="
echo

# Set API URL
domain_url="127.0.0.1:3000"

# Registration
echo "Registering superadmin user..."
register_response=$(curl -s -X POST "http://$domain_url/api/auth/register" \
    -H "Authorization: Bearer " \
    -H "Content-Type: application/json" \
    -H "Host: $PANEL_DOMAIN" \
    -H "X-Forwarded-For: 127.0.0.1" \
    -H "X-Forwarded-Proto: https" \
    -d "{\"username\":\"$SUPERADMIN_USERNAME\",\"password\":\"$SUPERADMIN_PASSWORD\"}")

# Extract token
token=$(echo "$register_response" | jq -r '.response.accessToken')

# Get public key
echo
echo "Getting public key..."
api_response=$(curl -s -X GET "http://$domain_url/api/keygen" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -H "Host: $PANEL_DOMAIN" \
    -H "X-Forwarded-For: 127.0.0.1" \
    -H "X-Forwarded-Proto: https")

# Extract public key
pubkey=$(echo "$api_response" | jq -r '.response.pubKey')

# Generate Xray keys
echo
echo "Generating Xray keys..."
docker run --rm ghcr.io/xtls/xray-core x25519 > /tmp/xray_keys.txt 2>&1
keys=$(cat /tmp/xray_keys.txt)
rm -f /tmp/xray_keys.txt
private_key=$(echo "$keys" | grep "Private key:" | awk '{print $3}')
public_key=$(echo "$keys" | grep "Public key:" | awk '{print $3}')

# Create Xray configuration
echo
echo "Creating Xray configuration..."
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

# Update Xray configuration via API
echo
echo "Updating Xray configuration..."
new_config=$(cat "$config_file")
update_response=$(curl -s -X PUT "http://$domain_url/api/xray" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -H "Host: $PANEL_DOMAIN" \
    -H "X-Forwarded-For: 127.0.0.1" \
    -H "X-Forwarded-Proto: https" \
    -d "$new_config")

# Remove temporary config file
rm -f "$config_file"

echo
echo "✓ API configuration completed!"
echo
