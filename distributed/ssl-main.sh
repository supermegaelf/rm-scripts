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

# Extract base domain from subdomain
extract_domain() {
    local SUBDOMAIN=$1
    echo "$SUBDOMAIN" | awk -F'.' '{if (NF > 2) {print $(NF-1)"."$NF} else {print $0}}'
}

# Check DNS configuration
check_domain() {
    local domain="$1"
    local domain_ip=$(dig +short A "$domain" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1)
    local server_ip=$(curl -s -4 ifconfig.me || curl -s -4 api.ipify.org || curl -s -4 ipinfo.io/ip)

    if [ -z "$domain_ip" ] || [ -z "$server_ip" ]; then
        print_warning "Could not verify DNS for $domain"
        return 1
    fi

    # Check if it's a Cloudflare IP (basic check)
    if [[ "$domain_ip" =~ ^(104\.|173\.|198\.|131\.|141\.) ]]; then
        print_warning "Domain $domain is proxied through Cloudflare"
        return 0
    fi

    if [ "$domain_ip" != "$server_ip" ]; then
        print_warning "Domain $domain points to $domain_ip, but server IP is $server_ip"
        return 1
    fi

    return 0
}

# Check Cloudflare API credentials
check_cloudflare_api() {
    local attempts=3
    local attempt=1

    while [ $attempt -le $attempts ]; do
        if [[ $CLOUDFLARE_API_KEY =~ [A-Z] ]]; then
            api_response=$(curl --silent --request GET --url https://api.cloudflare.com/client/v4/zones --header "Authorization: Bearer ${CLOUDFLARE_API_KEY}" --header "Content-Type: application/json")
        else
            api_response=$(curl --silent --request GET --url https://api.cloudflare.com/client/v4/zones --header "X-Auth-Key: ${CLOUDFLARE_API_KEY}" --header "X-Auth-Email: ${CLOUDFLARE_EMAIL}" --header "Content-Type: application/json")
        fi

        if echo "$api_response" | grep -q '"success":true'; then
            print_success "Cloudflare API credentials are valid"
            return 0
        else
            print_error "Invalid Cloudflare API credentials (attempt $attempt of $attempts)"
            if [ $attempt -lt $attempts ]; then
                print_input "Enter your Cloudflare API key: "
                read -s CLOUDFLARE_API_KEY
                echo
                print_input "Enter your Cloudflare email: "
                read CLOUDFLARE_EMAIL
            fi
            attempt=$((attempt + 1))
        fi
    done
    return 1
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

# Check if certbot is installed
if ! command -v certbot &> /dev/null; then
    print_error "Certbot is not installed. Please run prep-main.sh first."
    exit 1
fi

# Prompt for domain variables
print_input "Enter your Panel Domain (e.g., panel.example.com): "
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

# Check DNS for domains
print_warning "Checking DNS configuration..."
check_domain "$PANEL_DOMAIN"
check_domain "$SUB_DOMAIN"

# Extract base domains
PANEL_BASE_DOMAIN=$(extract_domain "$PANEL_DOMAIN")
SUB_BASE_DOMAIN=$(extract_domain "$SUB_DOMAIN")

print_success "Panel base domain: $PANEL_BASE_DOMAIN"
print_success "Sub base domain: $SUB_BASE_DOMAIN"

# Get Cloudflare credentials
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

# Validate Cloudflare API
if ! check_cloudflare_api; then
    print_error "Failed to validate Cloudflare API after 3 attempts"
    exit 1
fi

# Create credentials file
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

print_success "Cloudflare credentials configured"

# Determine which certificates we need
declare -A unique_domains
unique_domains["$PANEL_BASE_DOMAIN"]=1
unique_domains["$SUB_BASE_DOMAIN"]=1

# Get certificates for each unique base domain
for domain in "${!unique_domains[@]}"; do
    # Check if certificate already exists
    if [ -d "/etc/letsencrypt/live/$domain" ]; then
        print_warning "Certificate already exists for $domain, skipping..."
        continue
    fi

    print_warning "Obtaining wildcard certificate for $domain..."
    
    certbot certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials ~/.secrets/certbot/cloudflare.ini \
        --dns-cloudflare-propagation-seconds 10 \
        -d "$domain" \
        -d "*.$domain" \
        --email "$CLOUDFLARE_EMAIL" \
        --agree-tos \
        --non-interactive \
        --key-type ecdsa \
        --elliptic-curve secp384r1

    if [[ $? -eq 0 ]]; then
        print_success "SSL certificate obtained successfully for $domain and *.$domain"
        
        # Add renewal hook
        echo "renew_hook = sh -c 'cd /opt/remnawave && docker compose down remnawave-nginx && docker compose up -d remnawave-nginx'" >> /etc/letsencrypt/renewal/$domain.conf
        print_success "Renewal hook added for $domain"
    else
        print_error "Failed to obtain SSL certificate for $domain"
        exit 1
    fi
done

# Configure cron for certificate renewal
mkdir -p /usr/local/remnawave_reverse/
if ! crontab -u root -l 2>/dev/null | grep -q "/usr/bin/certbot renew --quiet"; then
    (crontab -l 2>/dev/null; echo "0 5 1 */2 * /usr/bin/certbot renew --quiet >> /usr/local/remnawave_reverse/cron_jobs.log 2>&1") | crontab -
    print_success "Automatic certificate renewal cron job configured"
else
    print_warning "Cron job for certificate renewal already exists"
fi

# Display certificate information
print_warning "Certificate status:"
for domain in "${!unique_domains[@]}"; do
    if certbot certificates | grep -A 10 "$domain"; then
        print_success "Certificate found for $domain"
    fi
done

print_success "SSL certificate setup completed successfully!"
print_warning "Certificates location:"
for domain in "${!unique_domains[@]}"; do
    echo "  - /etc/letsencrypt/live/$domain/"
done
