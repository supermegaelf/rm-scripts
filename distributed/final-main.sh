#!/bin/bash

# Remnawave node, host creation and final setup script
# Section 7: Creating node, host and final configuration

set -e

# Trap for Ctrl+C to show credentials
trap 'echo; echo "========================================"; echo "Remnawave URL:"; echo "https://${PANEL_DOMAIN}/auth/login?${cookies_random1}=${cookies_random2}"; echo; echo "Credentials:"; echo "Username: $SUPERADMIN_USERNAME"; echo "Password: $SUPERADMIN_PASSWORD"; echo; exit 0' INT

echo "========================================="
echo "Remnawave Final Setup"
echo "========================================="
echo

# Create node
echo
echo "Creating node..."
node_data=$(cat <<EOF
{
    "name": "VLESS Reality Steal Oneself",
    "address": "$SELFSTEAL_DOMAIN",
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

node_response=$(curl -s -X POST "http://$domain_url/api/nodes" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -H "Host: $PANEL_DOMAIN" \
    -H "X-Forwarded-For: 127.0.0.1" \
    -H "X-Forwarded-Proto: https" \
    -d "$node_data")

# Get inbound UUID
echo
echo "Getting inbound UUID..."
inbounds_response=$(curl -s -X GET "http://$domain_url/api/inbounds" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -H "Host: $PANEL_DOMAIN" \
    -H "X-Forwarded-For: 127.0.0.1" \
    -H "X-Forwarded-Proto: https")

inbound_uuid=$(echo "$inbounds_response" | jq -r '.response[0].uuid')

# Create host
echo
echo "Creating host..."
host_data=$(cat <<EOF
{
    "inboundUuid": "$inbound_uuid",
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

host_response=$(curl -s -X POST "http://$domain_url/api/hosts" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -H "Host: $PANEL_DOMAIN" \
    -H "X-Forwarded-For: 127.0.0.1" \
    -H "X-Forwarded-Proto: https" \
    -d "$host_data")

# Restart containers
echo
echo "Restarting containers..."
cd /opt/remnawave
docker compose down
sleep 1
docker compose up -d

# Install alias
echo
echo "Installing remnawave_reverse alias..."
mkdir -p /usr/local/remnawave_reverse/
wget -q -O /usr/local/remnawave_reverse/remnawave_reverse "https://raw.githubusercontent.com/eGamesAPI/remnawave-reverse-proxy/refs/heads/main/install_remnawave.sh"
chmod +x /usr/local/remnawave_reverse/remnawave_reverse
ln -sf /usr/local/remnawave_reverse/remnawave_reverse /usr/local/bin/remnawave_reverse

bashrc_file="/etc/bash.bashrc"
alias_line="alias rr='remnawave_reverse'"
echo "$alias_line" >> "$bashrc_file"

# Display results BEFORE logs
echo
echo "========================================="
echo "Remnawave URL:"
echo "https://${PANEL_DOMAIN}/auth/login?${cookies_random1}=${cookies_random2}"
echo
echo "Credentials:"
echo "Username: $SUPERADMIN_USERNAME"
echo "Password: $SUPERADMIN_PASSWORD"
echo "========================================="
echo
echo "✓ Remnawave setup completed successfully!"
echo
echo "To check logs, use: cd /opt/remnawave && docker compose logs -f"
