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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

# Change to working directory
cd /opt/remnawave

# Load saved variables
if [ ! -f "/opt/remnawave/node_vars.sh" ]; then
    print_error "node_vars.sh not found. Please run previous setup scripts first."
    exit 1
fi

source /opt/remnawave/node_vars.sh

# Verify variables
print_info "=== VERIFYING VARIABLES ==="
echo "SELFSTEAL_DOMAIN: $SELFSTEAL_DOMAIN"
echo "PANEL_IP: $PANEL_IP"
echo "CERT_DIR: $CERT_DIR"
echo "NODE_IP: $NODE_IP"

# Check .env-node file
if [ -f "/opt/remnawave/.env-node" ]; then
    print_success "File .env-node found"
else
    print_error "File .env-node not found!"
    exit 1
fi

# Create docker-compose.yml
print_info "Creating docker-compose.yml..."

cat > /opt/remnawave/docker-compose.yml <<EOL
services:
  remnawave-nginx:
    image: nginx:1.26
    container_name: remnawave-nginx
    hostname: remnawave-nginx
    restart: always
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - /etc/letsencrypt/live/$SELFSTEAL_DOMAIN/fullchain.pem:/etc/nginx/ssl/$SELFSTEAL_DOMAIN/fullchain.pem:ro
      - /etc/letsencrypt/live/$SELFSTEAL_DOMAIN/privkey.pem:/etc/nginx/ssl/$SELFSTEAL_DOMAIN/privkey.pem:ro
      - /dev/shm:/dev/shm:rw
      - /var/www/html:/var/www/html:ro
    command: sh -c 'rm -f /dev/shm/nginx.sock && nginx -g "daemon off;"'
    network_mode: host
    depends_on:
      - remnanode
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnanode:
    image: remnawave/node:latest
    container_name: remnanode
    hostname: remnanode
    restart: always
    network_mode: host
    env_file:
      - path: /opt/remnawave/.env-node
        required: false
    volumes:
      - /dev/shm:/dev/shm:rw
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'
EOL

print_success "docker-compose.yml created"

# Create nginx.conf for node
print_info "Creating nginx.conf..."

cat > /opt/remnawave/nginx.conf <<EOL
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ""      close;
}

ssl_protocols TLSv1.2 TLSv1.3;
ssl_ecdh_curve X25519:prime256v1:secp384r1;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers on;
ssl_session_timeout 1d;
ssl_session_cache shared:MozSSL:10m;

server {
    server_name $SELFSTEAL_DOMAIN;
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/$SELFSTEAL_DOMAIN/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$SELFSTEAL_DOMAIN/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$SELFSTEAL_DOMAIN/fullchain.pem";

    root /var/www/html;
    index index.html;
}

server {
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol default_server;
    server_name _;
    ssl_reject_handshake on;
    return 444;
}
EOL

print_success "nginx.conf created"

# Verify configuration files
print_info "Verifying configuration..."

# Check docker-compose.yml
if docker compose config > /dev/null 2>&1; then
    print_success "docker-compose.yml is valid"
else
    print_error "Error in docker-compose.yml"
    docker compose config
    exit 1
fi

# Check certificate paths in docker-compose.yml
if grep -q "$SELFSTEAL_DOMAIN" docker-compose.yml; then
    print_success "Certificate paths configured"
else
    print_error "Domain not found in docker-compose.yml"
    exit 1
fi

# Check nginx.conf
if grep -q "$SELFSTEAL_DOMAIN" nginx.conf; then
    print_success "Domain configured in nginx.conf"
else
    print_error "Domain not found in nginx.conf"
    exit 1
fi

# Install masking web page
print_info "Installing masking web page..."

cd /opt/

# Choose template source
echo ""
echo "Select template type:"
echo "1. Simple web templates"
echo "2. SNI templates"
read -p "Choose (1-2): " TEMPLATE_CHOICE

if [ "$TEMPLATE_CHOICE" == "1" ]; then
    TEMPLATE_URL="https://github.com/eGamesAPI/simple-web-templates/archive/refs/heads/main.zip"
    TEMPLATE_DIR="simple-web-templates-main"
elif [ "$TEMPLATE_CHOICE" == "2" ]; then
    TEMPLATE_URL="https://github.com/SmallPoppa/sni-templates/archive/refs/heads/main.zip"
    TEMPLATE_DIR="sni-templates-main"
else
    print_info "Using default template"
    TEMPLATE_URL="https://github.com/eGamesAPI/simple-web-templates/archive/refs/heads/main.zip"
    TEMPLATE_DIR="simple-web-templates-main"
fi

# Download templates
print_info "Downloading templates..."
if wget -q --timeout=30 --tries=10 --retry-connrefused "$TEMPLATE_URL" -O main.zip; then
    # Extract
    unzip -q -o main.zip
    rm -f main.zip

    # Navigate to templates directory
    cd "$TEMPLATE_DIR"

    # Remove unnecessary files
    rm -rf assets ".gitattributes" "README.md" "_config.yml" "index.html" 2>/dev/null

    # Get list of templates
    TEMPLATES=($(find . -maxdepth 1 -type d -not -path . | sed 's|./||'))

    if [ ${#TEMPLATES[@]} -eq 0 ]; then
        print_error "No templates found"
        cd /opt/
        rm -rf "$TEMPLATE_DIR"
        exit 1
    fi

    # Select random template
    RANDOM_TEMPLATE="${TEMPLATES[$RANDOM % ${#TEMPLATES[@]}]}"
    print_success "Selected template: $RANDOM_TEMPLATE"

    # Copy template
    rm -rf /var/www/html/*
    cp -a "${RANDOM_TEMPLATE}"/. "/var/www/html/"

    # Cleanup
    cd /opt/
    rm -rf "$TEMPLATE_DIR"

    print_success "Masking page installed"
else
    print_error "Failed to download templates"
    exit 1
fi

cd /opt/remnawave

# Create management scripts
print_info "Creating management scripts..."

# Log viewer script
cat > /opt/remnawave/logs.sh <<'EOL'
#!/bin/bash

echo "=== REMNAWAVE NODE LOGS ==="
echo "1. All containers"
echo "2. Node only"
echo "3. Nginx only"
echo "0. Exit"

read -p "Select option: " option

cd /opt/remnawave

case $option in
    1) docker compose logs -f --tail=100 ;;
    2) docker compose logs -f --tail=100 remnanode ;;
    3) docker compose logs -f --tail=100 remnawave-nginx ;;
    0) exit 0 ;;
    *) echo "Invalid option" ;;
esac
EOL

chmod +x /opt/remnawave/logs.sh

# Node management script
cat > /opt/remnawave/manage-node.sh <<'EOL'
#!/bin/bash

cd /opt/remnawave

case "$1" in
    start)
        echo "Starting node..."
        docker compose up -d
        ;;
    stop)
        echo "Stopping node..."
        docker compose down
        ;;
    restart)
        echo "Restarting node..."
        docker compose down
        sleep 3
        docker compose up -d
        ;;
    status)
        docker compose ps
        ;;
    update)
        echo "Updating node..."
        docker compose pull
        docker compose down
        docker compose up -d
        docker image prune -f
        ;;
    logs)
        /opt/remnawave/logs.sh
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|update|logs}"
        exit 1
        ;;
esac
EOL

chmod +x /opt/remnawave/manage-node.sh

# Create symbolic link
if [ ! -f /usr/local/bin/node-manage ]; then
    ln -sf /opt/remnawave/manage-node.sh /usr/local/bin/node-manage
fi

print_success "Management scripts created"
echo "  Usage: node-manage {start|stop|restart|status|update|logs}"

# Create final configuration file
cat > /opt/remnawave/node_final_config.txt <<EOL
=================================================
        REMNAWAVE NODE CONFIGURATION
=================================================
Created: $(date)

MAIN PARAMETERS:
- Domain: $SELFSTEAL_DOMAIN
- Node IP: $NODE_IP
- Panel IP: $PANEL_IP

CONFIGURATION FILES:
- docker-compose.yml: /opt/remnawave/docker-compose.yml
- nginx.conf: /opt/remnawave/nginx.conf
- .env-node: /opt/remnawave/.env-node

SSL CERTIFICATES:
- Path: $CERT_DIR
- Fullchain: $CERT_DIR/fullchain.pem
- Private key: $CERT_DIR/privkey.pem

CONTAINERS:
1. remnawave-nginx - web server for Reality
2. remnanode - Xray node

PORTS:
- 443: HTTPS/Reality (public)
- 2222: Panel connection (only for $PANEL_IP)

MANAGEMENT:
- Start: node-manage start
- Stop: node-manage stop
- Restart: node-manage restart
- Status: node-manage status
- Update: node-manage update
- Logs: node-manage logs

MASKING:
- Web content: /var/www/html/
- Template: $RANDOM_TEMPLATE

=================================================
EOL

# Protect files
chmod 600 /opt/remnawave/.env-node
chmod 644 /opt/remnawave/docker-compose.yml
chmod 644 /opt/remnawave/nginx.conf
chmod 600 /opt/remnawave/node_final_config.txt

print_success "Final configuration saved"

# Check readiness
print_info "Checking system readiness..."

echo ""
echo "File check:"
for file in docker-compose.yml nginx.conf .env-node; do
    if [ -f "/opt/remnawave/$file" ]; then
        print_success "$file exists"
    else
        print_error "$file not found!"
        exit 1
    fi
done

# Check Docker
if docker --version > /dev/null 2>&1; then
    print_success "Docker available"
else
    print_error "Docker not available!"
    exit 1
fi

# Check ports
echo ""
echo "Port check:"
if ss -tlnp | grep -q ":443"; then
    print_warning "Port 443 already in use"
else
    print_success "Port 443 is free"
fi

if ss -tlnp | grep -q ":2222"; then
    print_warning "Port 2222 already in use"
else
    print_success "Port 2222 is free"
fi

# Check web content
if [ -f "/var/www/html/index.html" ]; then
    print_success "Masking page installed"
else
    print_warning "Masking page not found"
fi

echo ""
print_success "System is ready to start the node!"
print_warning "Next step: Start the node and connect to panel"
