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

# Prompt for domain variables
print_input "Enter your Panel Domain (e.g., example.com): "
read PANEL_DOMAIN
if [[ -z "$PANEL_DOMAIN" ]]; then
    print_error "Panel Domain cannot be empty"
    exit 1
fi

print_input "Enter your Sub Domain (e.g., sub.example.com): "
read SUB_DOMAIN

if [[ -z "$SUB_DOMAIN" ]]; then
    print_error "Sub Domain cannot be empty"
    exit 1
fi

print_input "Enter your Cloudflare email: "
read CLOUDFLARE_EMAIL
if [[ -z "$CLOUDFLARE_EMAIL" ]]; then
    print_error "Cloudflare email cannot be empty"
    exit 1
fi

print_input "Enter your Cloudflare API key: "
read -s CLOUDFLARE_API_KEY
echo
if [[ -z "$CLOUDFLARE_API_KEY" ]]; then
    print_error "Cloudflare API key cannot be empty"
    exit 1
fi

mkdir -p /root/.secrets/certbot/

cat > /root/.secrets/certbot/cloudflare.ini << EOF
dns_cloudflare_email = "$CLOUDFLARE_EMAIL"
dns_cloudflare_api_key = "$CLOUDFLARE_API_KEY"
EOF

chmod 600 /root/.secrets/certbot/cloudflare.ini

print_success "Cloudflare credentials configured successfully"

# Check if certbot is installed
if ! command -v certbot &> /dev/null; then
    print_error "Certbot is not installed. Please install it first."
    exit 1
fi

certbot certonly \
    --dns-cloudflare \
    --dns-cloudflare-credentials /root/.secrets/certbot/cloudflare.ini \
    --dns-cloudflare-propagation-seconds 10 \
    -d "$PANEL_DOMAIN" \
    -d "*.$PANEL_DOMAIN" \
    --email "$CLOUDFLARE_EMAIL" \
    --agree-tos \
    --non-interactive \
    --key-type ecdsa \
    --elliptic-curve secp384r1

if [[ $? -eq 0 ]]; then
    print_success "SSL certificate obtained successfully for $PANEL_DOMAIN"
else
    print_error "Failed to obtain SSL certificate for $PANEL_DOMAIN"
    exit 1
fi

certbot certonly \
    --dns-cloudflare \
    --dns-cloudflare-credentials /root/.secrets/certbot/cloudflare.ini \
    --dns-cloudflare-propagation-seconds 10 \
    -d "$SUB_DOMAIN" \
    -d "*.$SUB_DOMAIN" \
    --email "$CLOUDFLARE_EMAIL" \
    --agree-tos \
    --non-interactive \
    --key-type ecdsa \
    --elliptic-curve secp384r1

if [[ $? -eq 0 ]]; then
    print_success "SSL certificate obtained successfully for $SUB_DOMAIN"
else
    print_error "Failed to obtain SSL certificate for $SUB_DOMAIN"
    exit 1
fi

echo "renew_hook = sh -c 'cd /opt/remnawave && docker compose down remnawave-nginx && docker compose up -d remnawave-nginx'" >> /etc/letsencrypt/renewal/$PANEL_DOMAIN.conf

# Check if SUB_DOMAIN certificate config exists, if not, it might be a wildcard covered by PANEL_DOMAIN
if [[ -f "/etc/letsencrypt/renewal/$SUB_DOMAIN.conf" ]]; then
    echo "renew_hook = sh -c 'cd /opt/remnawave && docker compose down remnawave-nginx && docker compose up -d remnawave-nginx'" >> /etc/letsencrypt/renewal/$SUB_DOMAIN.conf
    print_success "Renewal hook added for $SUB_DOMAIN"
else
    print_warning "Certificate config for $SUB_DOMAIN not found. It might be covered by the wildcard certificate."
fi

print_success "Renewal hook added for $PANEL_DOMAIN"

mkdir -p /usr/local/remnawave_reverse/

(crontab -l 2>/dev/null; echo "0 5 1 */2 * /usr/bin/certbot renew --quiet >> /usr/local/remnawave_reverse/cron_jobs.log 2>&1") | crontab -

print_success "Automatic certificate renewal cron job configured"

certbot certificates | grep -A 10 "$PANEL_DOMAIN" || true

print_success "SSL certificate setup completed successfully!"
