#!/bin/bash

# Remnawave structure and certificates creation script
# Section 3: Creating structure and certificates

set -e

echo "========================================="
echo "Remnawave Structure and Certificates Setup"
echo "========================================="
echo

# Load environment variables
if [ -f "remnawave-vars.sh" ]; then
    source remnawave-vars.sh
else
    echo "Error: remnawave-vars.sh not found!"
    echo "Please run var-main.sh first."
    exit 1
fi

# Create directory structure
echo "Creating directory structure..."
mkdir -p /opt/remnawave && cd /opt/remnawave

# Check Cloudflare API
echo
echo "Checking Cloudflare API..."
if [[ $CLOUDFLARE_API_KEY =~ [A-Z] ]]; then
    api_response=$(curl --silent --request GET --url https://api.cloudflare.com/client/v4/zones --header "Authorization: Bearer ${CLOUDFLARE_API_KEY}" --header "Content-Type: application/json")
else
    api_response=$(curl --silent --request GET --url https://api.cloudflare.com/client/v4/zones --header "X-Auth-Key: ${CLOUDFLARE_API_KEY}" --header "X-Auth-Email: ${CLOUDFLARE_EMAIL}" --header "Content-Type: application/json")
fi

# Generate certificates
echo
echo "Setting up Cloudflare credentials..."
mkdir -p ~/.secrets/certbot
if [[ $CLOUDFLARE_API_KEY =~ [A-Z] ]]; then
    cat > ~/.secrets/certbot/cloudflare.ini <<EOL
dns_cloudflare_api_token = $CLOUDFLARE_API_KEY
EOL
else
    cat > ~/.secrets/certbot/cloudflare.ini <<EOL
dns_cloudflare_email = $CLOUDFLARE_EMAIL
dns_cloudflare_api_key = $CLOUDFLARE_API_KEY
EOL
fi
chmod 600 ~/.secrets/certbot/cloudflare.ini

# Extract base domains
echo
echo "Extracting base domains..."
PANEL_BASE_DOMAIN=$(echo "$PANEL_DOMAIN" | awk -F'.' '{if (NF > 2) {print $(NF-1)"."$NF} else {print $0}}')
SUB_BASE_DOMAIN=$(echo "$SUB_DOMAIN" | awk -F'.' '{if (NF > 2) {print $(NF-1)"."$NF} else {print $0}}')

# Generate certificate for panel domain if not exists
echo
echo "Checking certificate for panel domain..."
if [ ! -d "/etc/letsencrypt/live/$PANEL_BASE_DOMAIN" ]; then
    echo "Generating certificate for $PANEL_BASE_DOMAIN..."
    certbot certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials ~/.secrets/certbot/cloudflare.ini \
        --dns-cloudflare-propagation-seconds 10 \
        -d "$PANEL_BASE_DOMAIN" \
        -d "*.$PANEL_BASE_DOMAIN" \
        --email "$CLOUDFLARE_EMAIL" \
        --agree-tos \
        --non-interactive \
        --key-type ecdsa \
        --elliptic-curve secp384r1
else
    echo "Certificate for $PANEL_BASE_DOMAIN already exists, skipping..."
fi

# Generate certificate for sub domain if not exists
echo
echo "Checking certificate for sub domain..."
if [ ! -d "/etc/letsencrypt/live/$SUB_BASE_DOMAIN" ]; then
    echo "Generating certificate for $SUB_BASE_DOMAIN..."
    certbot certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials ~/.secrets/certbot/cloudflare.ini \
        --dns-cloudflare-propagation-seconds 10 \
        -d "$SUB_BASE_DOMAIN" \
        -d "*.$SUB_BASE_DOMAIN" \
        --email "$CLOUDFLARE_EMAIL" \
        --agree-tos \
        --non-interactive \
        --key-type ecdsa \
        --elliptic-curve secp384r1
else
    echo "Certificate for $SUB_BASE_DOMAIN already exists, skipping..."
fi

# Configure renewal hooks and cron
echo
echo "Configuring certificate renewal..."
echo "renew_hook = sh -c 'cd /opt/remnawave && docker compose down remnawave-nginx && docker compose up -d remnawave-nginx'" >> /etc/letsencrypt/renewal/$PANEL_BASE_DOMAIN.conf
echo "renew_hook = sh -c 'cd /opt/remnawave && docker compose down remnawave-nginx && docker compose up -d remnawave-nginx'" >> /etc/letsencrypt/renewal/$SUB_BASE_DOMAIN.conf
(crontab -u root -l 2>/dev/null; echo "0 5 1 */2 * /usr/bin/certbot renew --quiet >> /usr/local/remnawave_reverse/cron_jobs.log 2>&1") | crontab -u root -

echo
echo "✓ Structure and certificates setup completed!"
echo
