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

# Verify variables are loaded
if [[ -z "$PANEL_DOMAIN" || -z "$SUB_DOMAIN" || -z "$COOKIES_RANDOM1" || -z "$COOKIES_RANDOM2" ]]; then
    print_error "Required variables not found. Please run config setup script first."
    exit 1
fi

print_success "Variables loaded successfully"
echo "PANEL_DOMAIN: $PANEL_DOMAIN"
echo "SUB_DOMAIN: $SUB_DOMAIN"
echo "COOKIES_RANDOM1: $COOKIES_RANDOM1"
echo "COOKIES_RANDOM2: $COOKIES_RANDOM2"

# Create nginx.conf
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
    "~*${COOKIES_RANDOM1}=${COOKIES_RANDOM2}" 1;
}

map \$arg_${COOKIES_RANDOM1} \$auth_query {
    default 0;
    "${COOKIES_RANDOM2}" 1;
}

map "\$auth_cookie\$auth_query" \$authorized {
    "~1" 1;
    default 0;
}

map \$arg_${COOKIES_RANDOM1} \$set_cookie_header {
    "${COOKIES_RANDOM2}" "${COOKIES_RANDOM1}=${COOKIES_RANDOM2}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=31536000";
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

print_success "nginx.conf created successfully"

# Verify variables in nginx.conf
grep -E "COOKIES_RANDOM1|PANEL_DOMAIN|SUB_DOMAIN" /opt/remnawave/nginx.conf >/dev/null
if [[ $? -eq 0 ]]; then
    print_warning "Found placeholder variables in nginx.conf - this might be an error"
else
    print_success "Variables properly substituted in nginx.conf"
fi

# Create security headers file
cat > /opt/remnawave/security-headers.conf <<EOL
# Security headers
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;

# HSTS (включите только если уверены, что всегда будете использовать HTTPS)
# add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
EOL

print_success "Security headers configuration created"

# Create panel access information file
cat > /opt/remnawave/panel_access.txt <<EOL
================================================
PANEL ACCESS INFORMATION
================================================
Panel URL: https://$PANEL_DOMAIN/auth/login?${COOKIES_RANDOM1}=${COOKIES_RANDOM2}

Direct access (with cookie auth):
https://$PANEL_DOMAIN/auth/login?${COOKIES_RANDOM1}=${COOKIES_RANDOM2}

Subscription URL:
https://$SUB_DOMAIN

Username: $SUPERADMIN_USERNAME
Password: $SUPERADMIN_PASSWORD
================================================
EOL

chmod 600 /opt/remnawave/panel_access.txt

print_success "Panel access information saved to panel_access.txt"

# Display access information
cat /opt/remnawave/panel_access.txt

# Set proper file permissions
chmod 644 nginx.conf
chmod 600 .env
chmod 644 docker-compose.yml
chmod 644 security-headers.conf

print_success "File permissions set correctly"

# Final file check
ls -la /opt/remnawave/

print_success "Nginx configuration setup completed successfully!"
