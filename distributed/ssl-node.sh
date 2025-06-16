#!/bin/bash

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_input() {
    echo -n -e "${GREEN}$1${NC}"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

# Change to working directory
cd /opt/remnawave

# Collect necessary information
print_info "=== NODE CONFIGURATION SETUP ==="
echo ""

# Request selfsteal domain
print_input "Enter the selfsteal domain for the node (specified during panel installation): "
read SELFSTEAL_DOMAIN

if [[ -z "$SELFSTEAL_DOMAIN" ]]; then
    print_error "Domain cannot be empty"
    exit 1
fi

# Save domain
echo "SELFSTEAL_DOMAIN=$SELFSTEAL_DOMAIN" > /opt/remnawave/node_vars.sh
print_success "Domain saved: $SELFSTEAL_DOMAIN"

# Check DNS and domain availability
print_info "Checking domain $SELFSTEAL_DOMAIN..."

# Get node server IP
NODE_IP=$(curl -s -4 ifconfig.me || curl -s -4 api.ipify.org || curl -s -4 ipinfo.io/ip)
if [[ -z "$NODE_IP" ]]; then
    print_error "Failed to determine server IP"
    exit 1
fi
print_info "This server IP: $NODE_IP"

# Check DNS record
DOMAIN_IP=$(dig +short A "$SELFSTEAL_DOMAIN" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1)
if [[ -z "$DOMAIN_IP" ]]; then
    print_warning "Failed to resolve domain IP"
    print_warning "Make sure DNS is configured correctly"
else
    print_info "Domain $SELFSTEAL_DOMAIN points to: $DOMAIN_IP"
    
    # Check if it's Cloudflare IP
    if [[ "$DOMAIN_IP" =~ ^(104\.|173\.|198\.|131\.|141\.) ]]; then
        print_error "Domain is proxied through Cloudflare!"
        print_error "Selfsteal domain MUST NOT have Cloudflare proxy enabled!"
        print_error "Please disable proxy (set to 'DNS only') and wait for propagation"
        exit 1
    fi
    
    # Check match
    if [ "$DOMAIN_IP" = "$NODE_IP" ]; then
        print_success "Domain correctly points to this server"
    else
        print_warning "WARNING: Domain points to different IP!"
        print_warning "Expected: $NODE_IP, Got: $DOMAIN_IP"
        print_input "Continue installation anyway? (y/n): "
        read CONTINUE
        if [[ "$CONTINUE" != "y" && "$CONTINUE" != "Y" ]]; then
            print_error "Installation aborted"
            exit 1
        fi
    fi
fi

# Request panel IP
while true; do
    print_input "Enter the panel server IP address: "
    read PANEL_IP
    
    # Validate IP address
    if echo "$PANEL_IP" | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' >/dev/null && \
       [[ $(echo "$PANEL_IP" | tr '.' '\n' | wc -l) -eq 4 ]] && \
       [[ ! $(echo "$PANEL_IP" | tr '.' '\n' | grep -vE '^[0-9]{1,3}$') ]] && \
       [[ ! $(echo "$PANEL_IP" | tr '.' '\n' | grep -E '^(25[6-9]|2[6-9][0-9]|[3-9][0-9]{2})$') ]]; then
        print_success "IP address valid: $PANEL_IP"
        break
    else
        print_error "Invalid IP address. Please try again."
    fi
done

# Save panel IP
echo "PANEL_IP=$PANEL_IP" >> /opt/remnawave/node_vars.sh

# Get SSL certificate from panel
echo ""
print_info "=== OBTAINING SSL CERTIFICATE ==="
echo "On the panel server, run the following command:"
echo ""
echo -e "${YELLOW}cat /opt/remnawave/.env-node${NC}"
echo ""
echo "Copy the entire content, including the SSL_CERT= line"
print_input "Paste it below and press Enter twice: "

# Read certificate
CERTIFICATE=""
while IFS= read -r line; do
    if [ -z "$line" ]; then
        if [ -n "$CERTIFICATE" ]; then
            break
        fi
    else
        CERTIFICATE="$CERTIFICATE$line\n"
    fi
done

# Verify certificate
if echo -e "$CERTIFICATE" | grep -q "SSL_CERT="; then
    print_success "Certificate received"
else
    print_error "Error: certificate must contain SSL_CERT= line"
    exit 1
fi

# Create .env-node file
echo -e "$CERTIFICATE" | sed 's/\\n$//' > /opt/remnawave/.env-node
chmod 600 /opt/remnawave/.env-node

# Show content for verification
echo ""
print_info "Content of .env-node:"
cat /opt/remnawave/.env-node
echo ""

print_input "Is the certificate correct? (y/n): "
read CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    print_error "Installation aborted"
    exit 1
fi

# Setup SSL certificates
source /opt/remnawave/node_vars.sh

echo ""
print_info "=== SSL CERTIFICATE SETUP ==="
print_info "Domain for certificates: $SELFSTEAL_DOMAIN"

# Check existing certificates
SKIP_CERT_GENERATION=false
if [ -d "/etc/letsencrypt/live/$SELFSTEAL_DOMAIN" ]; then
    print_success "Certificates already exist for $SELFSTEAL_DOMAIN"
    
    # Check expiry
    if openssl x509 -in "/etc/letsencrypt/live/$SELFSTEAL_DOMAIN/fullchain.pem" -noout -checkend 0 > /dev/null 2>&1; then
        CERT_EXPIRY=$(openssl x509 -in "/etc/letsencrypt/live/$SELFSTEAL_DOMAIN/fullchain.pem" -noout -enddate | sed 's/notAfter=//')
        print_info "Valid until: $CERT_EXPIRY"
        
        print_input "Use existing certificates? (y/n): "
        read USE_EXISTING
        
        if [[ "$USE_EXISTING" == "y" || "$USE_EXISTING" == "Y" ]]; then
            SKIP_CERT_GENERATION=true
        fi
    else
        print_warning "Existing certificate is expired or invalid"
    fi
fi

# Certificate generation if needed
if [ "$SKIP_CERT_GENERATION" = false ]; then
    echo ""
    print_info "=== OBTAINING SSL CERTIFICATES VIA CLOUDFLARE ==="
    
    print_input "Enter Cloudflare registered email: "
    read CF_EMAIL
    
    print_input "Enter Cloudflare API key (Global API Key or API Token): "
    read -s CF_API_KEY
    echo ""
    
    # Create Cloudflare configuration
    mkdir -p ~/.secrets/certbot
    if [[ $CF_API_KEY =~ [A-Z] ]]; then
        cat > ~/.secrets/certbot/cloudflare.ini <<EOL
dns_cloudflare_api_token = $CF_API_KEY
EOL
    else
        cat > ~/.secrets/certbot/cloudflare.ini <<EOL
dns_cloudflare_email = $CF_EMAIL
dns_cloudflare_api_key = $CF_API_KEY
EOL
    fi
    chmod 600 ~/.secrets/certbot/cloudflare.ini
    
    # Get certificate
    print_info "Obtaining certificate via Cloudflare DNS..."
    if certbot certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials ~/.secrets/certbot/cloudflare.ini \
        --dns-cloudflare-propagation-seconds 10 \
        -d "$SELFSTEAL_DOMAIN" \
        --email "$CF_EMAIL" \
        --agree-tos \
        --non-interactive \
        --key-type ecdsa \
        --elliptic-curve secp384r1; then
        print_success "Certificate obtained successfully"
    else
        print_error "Failed to obtain certificate"
        exit 1
    fi
fi

# Verify certificates
echo ""
print_info "=== VERIFYING CERTIFICATES ==="

CERT_DIR="/etc/letsencrypt/live/$SELFSTEAL_DOMAIN"

if [ -d "$CERT_DIR" ]; then
    print_success "Certificate directory found"
    
    # Check all necessary files
    for file in cert.pem chain.pem fullchain.pem privkey.pem; do
        if [ -f "$CERT_DIR/$file" ]; then
            print_success "$file exists"
        else
            print_error "$file not found!"
            exit 1
        fi
    done
    
    # Check certificate validity
    if openssl x509 -in "$CERT_DIR/fullchain.pem" -noout -checkend 0; then
        print_success "Certificate is valid"
    else
        print_error "Certificate is expired or invalid!"
        exit 1
    fi
else
    print_error "Certificates not found!"
    exit 1
fi

# Setup automatic certificate renewal
if [ -f "/etc/letsencrypt/renewal/$SELFSTEAL_DOMAIN.conf" ]; then
    # Check for renew hook
    if ! grep -q "renew_hook" "/etc/letsencrypt/renewal/$SELFSTEAL_DOMAIN.conf"; then
        echo "renew_hook = sh -c 'cd /opt/remnawave && docker compose restart remnawave-nginx'" >> "/etc/letsencrypt/renewal/$SELFSTEAL_DOMAIN.conf"
        print_success "Renewal hook added"
    else
        print_info "Renewal hook already exists"
    fi
else
    print_warning "Renewal configuration file not found"
fi

# Add cron job for renewal
if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
    (crontab -l 2>/dev/null; echo "0 5 1 */2 * /usr/bin/certbot renew --quiet") | crontab -
    print_success "Cron job for certificate renewal added"
else
    print_info "Cron job already exists"
fi

# Setup firewall for panel
echo ""
print_info "=== FIREWALL CONFIGURATION ==="
print_info "Opening port 2222 for panel connection..."

ufw allow from $PANEL_IP to any port 2222 proto tcp comment "Remnawave panel connection"
ufw reload

print_success "Port 2222 opened only for panel IP: $PANEL_IP"

# Show current rules
echo ""
print_info "Current firewall rules:"
ufw status numbered

# Save configuration
cat >> /opt/remnawave/node_vars.sh <<EOL
CERT_DIR="/etc/letsencrypt/live/$SELFSTEAL_DOMAIN"
NODE_IP="$NODE_IP"
export SELFSTEAL_DOMAIN PANEL_IP CERT_DIR NODE_IP
EOL

# Create summary file
cat > /opt/remnawave/node_config_summary.txt <<EOL
=================================================
            NODE CONFIGURATION SUMMARY
=================================================
Date: $(date)

Node domain: $SELFSTEAL_DOMAIN
Node IP: $NODE_IP
Panel IP: $PANEL_IP

Certificates: $CERT_DIR
- fullchain.pem
- privkey.pem

Ports:
- 443: HTTPS/Reality (open to all)
- 2222: Panel connection (open only to $PANEL_IP)

Configuration files:
- /opt/remnawave/.env-node (panel certificate)
- /opt/remnawave/node_vars.sh (variables)
=================================================
EOL

echo ""
print_success "Configuration saved"
cat /opt/remnawave/node_config_summary.txt

echo ""
print_success "Certificate and firewall configuration completed!"
print_warning "Next step: Create Docker and Nginx configuration files"
