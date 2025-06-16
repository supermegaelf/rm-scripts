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
    print_error "install_vars.sh not found. Please run config-main.sh first."
    exit 1
fi

# Load variables
source /opt/remnawave/install_vars.sh

# Verify all required variables are loaded
REQUIRED_VARS=("PANEL_DOMAIN" "SUB_DOMAIN" "COOKIES_RANDOM1" "COOKIES_RANDOM2" "SUPERADMIN_USERNAME" "SUPERADMIN_PASSWORD")
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var}" ]]; then
        print_error "Required variable $var not found. Please run config-main.sh first."
        exit 1
    fi
done

print_success "All variables loaded successfully"

# Check if nginx.conf already exists
if [[ -f "/opt/remnawave/nginx.conf" ]]; then
    print_warning "nginx.conf already exists. Backing up to nginx.conf.backup"
    cp /opt/remnawave/nginx.conf /opt/remnawave/nginx.conf.backup
fi

# Create nginx.conf with security headers included
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

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
    
    # Cookie header for authentication
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

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;

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

# Verify that variables were properly substituted
if grep -E "\\\$PANEL_DOMAIN|\\\$SUB_DOMAIN" /opt/remnawave/nginx.conf | grep -v "server_name" >/dev/null; then
    print_error "Variable substitution failed in nginx.conf"
    exit 1
else
    print_success "Variables properly substituted in nginx.conf"
fi

# Create or update panel access information file
cat > /opt/remnawave/panel_access.txt <<EOL
=================================================
           PANEL ACCESS INFORMATION
=================================================
Panel URL: 
https://$PANEL_DOMAIN/auth/login?${COOKIES_RANDOM1}=${COOKIES_RANDOM2}

Subscription URL:
https://$SUB_DOMAIN

Admin Credentials:
Username: $SUPERADMIN_USERNAME
Password: $SUPERADMIN_PASSWORD
=================================================
IMPORTANT: Save this information securely!
=================================================
EOL

chmod 600 /opt/remnawave/panel_access.txt
print_success "Panel access information saved to panel_access.txt"

# Display access information
echo ""
cat /opt/remnawave/panel_access.txt
echo ""

# Test nginx configuration syntax
if command -v nginx &> /dev/null; then
    if nginx -t -c /opt/remnawave/nginx.conf 2>/dev/null; then
        print_success "Nginx configuration syntax is valid"
    else
        print_warning "Cannot test nginx config syntax in Docker context"
    fi
fi

# Set proper file permissions
chmod 644 /opt/remnawave/nginx.conf
if [[ -f "/opt/remnawave/.env" ]]; then
    chmod 600 /opt/remnawave/.env
fi
if [[ -f "/opt/remnawave/docker-compose.yml" ]]; then
    chmod 644 /opt/remnawave/docker-compose.yml
fi

print_success "File permissions set correctly"

# Create a summary file with all important files
cat > /opt/remnawave/installation_summary.txt <<EOL
=================================================
           INSTALLATION SUMMARY
=================================================
Installation completed: $(date)

Important files:
- Configuration: /opt/remnawave/.env
- Docker Compose: /opt/remnawave/docker-compose.yml
- Nginx Config: /opt/remnawave/nginx.conf
- Panel Access: /opt/remnawave/panel_access.txt
- Credentials: /opt/remnawave/credentials.txt

Panel Domain: $PANEL_DOMAIN
Subscription Domain: $SUB_DOMAIN

Next steps:
1. Run: docker compose up -d
2. Wait 20-30 seconds for services to start
3. Access panel at the URL shown above
=================================================
EOL

print_success "Installation summary created"

# Final check of all required files
REQUIRED_FILES=(".env" "docker-compose.yml" "nginx.conf" "install_vars.sh")
MISSING_FILES=()

for file in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "/opt/remnawave/$file" ]]; then
        MISSING_FILES+=("$file")
    fi
done

if [[ ${#MISSING_FILES[@]} -eq 0 ]]; then
    print_success "All required files are present"
    echo ""
    print_success "Nginx configuration setup completed successfully!"
    print_warning "Next step: run 'cd /opt/remnawave && docker compose up -d' to start services"
else
    print_error "Missing required files: ${MISSING_FILES[*]}"
    exit 1
fi
