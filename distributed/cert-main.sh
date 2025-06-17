#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print status messages
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if command succeeded
check_status() {
    if [ $? -eq 0 ]; then
        print_success "$1"
    else
        print_error "$1 failed!"
        exit 1
    fi
}

echo -e "${BLUE}=== Certificate Setup Script ===${NC}"
echo -e "${YELLOW}This script will create directory structure and generate SSL certificates${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

# Check if required environment variables are set
if [ -z "$PANEL_DOMAIN" ] || [ -z "$SUB_DOMAIN" ] || [ -z "$CLOUDFLARE_API_KEY" ] || [ -z "$CLOUDFLARE_EMAIL" ]; then
    print_error "Required environment variables are not set!"
    echo -e "${YELLOW}Please ensure the following variables are exported:${NC}"
    echo -e "• PANEL_DOMAIN"
    echo -e "• SUB_DOMAIN"
    echo -e "• CLOUDFLARE_API_KEY"
    echo -e "• CLOUDFLARE_EMAIL"
    echo
    echo -e "${YELLOW}Run the variables setup script first or source your variables file${NC}"
    exit 1
fi

print_status "Step 1: Creating directory structure..."
mkdir -p /opt/remnawave && cd /opt/remnawave
check_status "Directory structure creation"

print_status "Step 2: Testing Cloudflare API connectivity..."
if [[ $CLOUDFLARE_API_KEY =~ [A-Z] ]]; then
    print_status "Using API Token authentication"
    api_response=$(curl --silent --request GET --url https://api.cloudflare.com/client/v4/zones --header "Authorization: Bearer ${CLOUDFLARE_API_KEY}" --header "Content-Type: application/json")
else
    print_status "Using Global API Key authentication"
    api_response=$(curl --silent --request GET --url https://api.cloudflare.com/client/v4/zones --header "X-Auth-Key: ${CLOUDFLARE_API_KEY}" --header "X-Auth-Email: ${CLOUDFLARE_EMAIL}" --header "Content-Type: application/json")
fi

# Check if API response is successful
if echo "$api_response" | grep -q '"success":true'; then
    print_success "Cloudflare API connection successful"
else
    print_error "Cloudflare API connection failed"
    echo -e "${RED}API Response:${NC} $api_response"
    exit 1
fi

print_status "Step 3: Creating Cloudflare credentials file..."
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
check_status "Cloudflare credentials file creation"

print_status "Step 4: Extracting base domains..."
PANEL_BASE_DOMAIN=$(echo "$PANEL_DOMAIN" | awk -F'.' '{if (NF > 2) {print $(NF-1)"."$NF} else {print $0}}')
SUB_BASE_DOMAIN=$(echo "$SUB_DOMAIN" | awk -F'.' '{if (NF > 2) {print $(NF-1)"."$NF} else {print $0}}')

print_status "Panel base domain: $PANEL_BASE_DOMAIN"
print_status "Sub base domain: $SUB_BASE_DOMAIN"

# Check if certificates already exist
check_cert_exists() {
    local domain="$1"
    if [ -d "/etc/letsencrypt/live/$domain" ] && [ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]; then
        return 0
    else
        return 1
    fi
}

print_status "Step 5: Checking existing certificates..."

# Check panel certificate
if check_cert_exists "$PANEL_BASE_DOMAIN"; then
    print_warning "Certificate for $PANEL_BASE_DOMAIN already exists, skipping..."
else
    print_status "Generating certificate for $PANEL_BASE_DOMAIN..."
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
    check_status "Panel certificate generation"
fi

# Check sub certificate
if check_cert_exists "$SUB_BASE_DOMAIN"; then
    print_warning "Certificate for $SUB_BASE_DOMAIN already exists, skipping..."
else
    print_status "Generating certificate for $SUB_BASE_DOMAIN..."
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
    check_status "Sub certificate generation"
fi

print_status "Step 6: Configuring certificate renewal..."

# Add renewal hooks only if certificates were generated or if config doesn't exist
if [ -f "/etc/letsencrypt/renewal/$PANEL_BASE_DOMAIN.conf" ]; then
    if ! grep -q "renew_hook" "/etc/letsencrypt/renewal/$PANEL_BASE_DOMAIN.conf"; then
        echo "renew_hook = sh -c 'cd /opt/remnawave && docker compose down remnawave-nginx && docker compose up -d remnawave-nginx'" >> /etc/letsencrypt/renewal/$PANEL_BASE_DOMAIN.conf
        print_success "Added renewal hook for $PANEL_BASE_DOMAIN"
    else
        print_warning "Renewal hook for $PANEL_BASE_DOMAIN already exists"
    fi
fi

if [ -f "/etc/letsencrypt/renewal/$SUB_BASE_DOMAIN.conf" ]; then
    if ! grep -q "renew_hook" "/etc/letsencrypt/renewal/$SUB_BASE_DOMAIN.conf"; then
        echo "renew_hook = sh -c 'cd /opt/remnawave && docker compose down remnawave-nginx && docker compose up -d remnawave-nginx'" >> /etc/letsencrypt/renewal/$SUB_BASE_DOMAIN.conf
        print_success "Added renewal hook for $SUB_BASE_DOMAIN"
    else
        print_warning "Renewal hook for $SUB_BASE_DOMAIN already exists"
    fi
fi

# Add cron job for certificate renewal
if ! crontab -u root -l 2>/dev/null | grep -q "certbot renew"; then
    (crontab -u root -l 2>/dev/null; echo "0 5 1 */2 * /usr/bin/certbot renew --quiet >> /usr/local/remnawave_reverse/cron_jobs.log 2>&1") | crontab -u root -
    check_status "Certificate renewal cron job setup"
else
    print_warning "Certificate renewal cron job already exists"
fi

echo
echo -e "${GREEN}=== Certificate Setup Complete! ===${NC}"
echo -e "${YELLOW}Summary:${NC}"
echo -e "${GREEN}✓${NC} Directory structure created: /opt/remnawave"
echo -e "${GREEN}✓${NC} Cloudflare API connectivity verified"
echo -e "${GREEN}✓${NC} Cloudflare credentials configured"
echo -e "${GREEN}✓${NC} Base domains extracted:"
echo -e "  • Panel: $PANEL_BASE_DOMAIN"
echo -e "  • Sub: $SUB_BASE_DOMAIN"

# Check certificate status
if check_cert_exists "$PANEL_BASE_DOMAIN"; then
    echo -e "${GREEN}✓${NC} Panel certificate: Available"
else
    echo -e "${RED}✗${NC} Panel certificate: Failed"
fi

if check_cert_exists "$SUB_BASE_DOMAIN"; then
    echo -e "${GREEN}✓${NC} Sub certificate: Available"
else
    echo -e "${RED}✗${NC} Sub certificate: Failed"
fi

echo
echo -e "${GREEN}=== Certificates Setup Complete! ===${NC}"
