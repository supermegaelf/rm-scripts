#!/bin/bash

# Remnawave Installation Script
# Main installation script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Cleanup function
cleanup() {
    if [[ $? -ne 0 ]]; then
        echo ""
        error "Installation interrupted or failed!"
        echo "You can try running the script again."
        if [[ -d "/opt/remnawave" ]]; then
            echo "Partial installation found at /opt/remnawave"
            echo "You may need to clean it up before retrying."
        fi
    fi
}

# Trap cleanup on exit
trap cleanup EXIT

# Signal handlers
handle_interrupt() {
    echo ""
    warning "Installation interrupted by user (Ctrl+C)"
    echo "Cleaning up..."
    if [[ -d "/opt/remnawave" ]] && [[ -f "/opt/remnawave/docker-compose.yml" ]]; then
        cd /opt/remnawave
        docker compose down 2>/dev/null || true
    fi
    exit 1
}

trap handle_interrupt SIGINT SIGTERM

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# Function to check if Remnawave is already installed
check_existing_installation() {
    if [[ -d "/opt/remnawave" ]]; then
        log "Existing Remnawave installation detected"
        
        if docker ps | grep -q "remnawave"; then
            echo -e "${GREEN}Remnawave is currently running${NC}"
        else
            echo -e "${YELLOW}Remnawave is installed but not running${NC}"
        fi
        
        echo ""
        echo "What would you like to do?"
        echo "1) Continue with fresh installation (will backup existing config)"
        echo "2) Update/repair existing installation"
        echo "3) Exit"
        
        read -p "Select option (1-3): " existing_choice
        
        case $existing_choice in
            1)
                log "Creating backup of existing installation..."
                backup_dir="/opt/remnawave_backup_$(date +%Y%m%d_%H%M%S)"
                cp -r /opt/remnawave "$backup_dir"
                log "Backup created at $backup_dir"
                ;;
            2)
                log "Updating/repairing existing installation..."
                cd /opt/remnawave
                if [[ -f "remnawave-vars.sh" ]]; then
                    source remnawave-vars.sh
                    log "Loaded existing configuration"
                    # Skip to container restart
                    restart_containers
                    display_results
                    exit 0
                else
                    warning "Configuration file not found, continuing with fresh setup..."
                fi
                ;;
            3)
                log "Installation cancelled by user"
                exit 0
                ;;
            *)
                error "Invalid option selected"
                ;;
        esac
    fi
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root"
fi

# Function to check DNS records
check_dns_records() {
    log "Checking DNS records..."
    
    # Get server IP
    SERVER_IP=$(curl -s https://ipinfo.io/ip 2>/dev/null || curl -s https://ifconfig.me 2>/dev/null)
    if [[ -z "$SERVER_IP" ]]; then
        warning "Could not determine server IP address"
        return
    fi
    
    log "Server IP: $SERVER_IP"
    
    # Check panel domain
    log "Checking DNS for $PANEL_DOMAIN..."
    PANEL_IP=$(dig +short "$PANEL_DOMAIN" @8.8.8.8 | tail -n1)
    if [[ "$PANEL_IP" == "$SERVER_IP" ]]; then
        log "✅ $PANEL_DOMAIN resolves correctly to $PANEL_IP"
    else
        warning "❌ $PANEL_DOMAIN resolves to $PANEL_IP, but server IP is $SERVER_IP"
        echo "Please update your DNS records in Cloudflare:"
        echo "Type: A, Name: $(echo $PANEL_DOMAIN | cut -d'.' -f1), Content: $SERVER_IP"
    fi
    
    # Check subscription domain
    log "Checking DNS for $SUB_DOMAIN..."
    SUB_IP=$(dig +short "$SUB_DOMAIN" @8.8.8.8 | tail -n1)
    if [[ "$SUB_IP" == "$SERVER_IP" ]]; then
        log "✅ $SUB_DOMAIN resolves correctly to $SUB_IP"
    else
        warning "❌ $SUB_DOMAIN resolves to $SUB_IP, but server IP is $SERVER_IP"
        echo "Please update your DNS records in Cloudflare:"
        echo "Type: A, Name: $(echo $SUB_DOMAIN | cut -d'.' -f1), Content: $SERVER_IP"
    fi
    
    # Check reality domain
    log "Checking DNS for $SELFSTEAL_DOMAIN..."
    STEAL_IP=$(dig +short "$SELFSTEAL_DOMAIN" @8.8.8.8 | tail -n1)
    if [[ -n "$STEAL_IP" ]]; then
        log "✅ $SELFSTEAL_DOMAIN resolves to $STEAL_IP"
    else
        warning "❌ $SELFSTEAL_DOMAIN does not resolve"
        echo "This might be intentional if using an existing domain for Reality"
    fi
    
    # Ask user if they want to continue with incorrect DNS
    if [[ "$PANEL_IP" != "$SERVER_IP" ]] || [[ "$SUB_IP" != "$SERVER_IP" ]]; then
        echo ""
        warning "Some DNS records don't point to this server."
        echo "SSL certificate generation may fail if DNS is not configured correctly."
        read -p "Continue anyway? (y/N): " continue_with_wrong_dns
        if [[ $continue_with_wrong_dns != [yY] && $continue_with_wrong_dns != [yY][eE][sS] ]]; then
            error "Please fix DNS records and try again"
        fi
    fi
    
    echo ""
}

# Function to validate domain format
validate_domain() {
    local domain="$1"
    if [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate email format
validate_email() {
    local email="$1"
    if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to collect user input for environment variables
collect_user_input() {
    log "Collecting configuration information..."
    echo ""
    
    # Panel domain
    while true; do
        echo -e "${BLUE}Enter the domain for Remnawave panel:${NC}"
        echo "Example: panel.yourdomain.com"
        read -p "Panel domain: " PANEL_DOMAIN
        if validate_domain "$PANEL_DOMAIN"; then
            break
        else
            error "Invalid domain format. Please try again."
        fi
    done
    
    # Subscription domain
    while true; do
        echo ""
        echo -e "${BLUE}Enter the domain for subscriptions:${NC}"
        echo "Example: sub.yourdomain.com"
        read -p "Subscription domain: " SUB_DOMAIN
        if validate_domain "$SUB_DOMAIN"; then
            break
        else
            error "Invalid domain format. Please try again."
        fi
    done
    
    # Self-steal domain
    while true; do
        echo ""
        echo -e "${BLUE}Enter the domain for Reality self-steal:${NC}"
        echo "Example: steal.yourdomain.com or any existing domain"
        read -p "Reality domain: " SELFSTEAL_DOMAIN
        if validate_domain "$SELFSTEAL_DOMAIN"; then
            break
        else
            error "Invalid domain format. Please try again."
        fi
    done
    
    # Cloudflare email
    while true; do
        echo ""
        echo -e "${BLUE}Enter your Cloudflare account email:${NC}"
        read -p "Cloudflare email: " CLOUDFLARE_EMAIL
        if validate_email "$CLOUDFLARE_EMAIL"; then
            break
        else
            error "Invalid email format. Please try again."
        fi
    done
    
    # Cloudflare API key
    echo ""
    echo -e "${BLUE}Enter your Cloudflare API key:${NC}"
    echo "You can use either:"
    echo "1. Global API Key (starts with lowercase letters/numbers)"
    echo "2. API Token (starts with uppercase letters)"
    echo "Get it from: https://dash.cloudflare.com/profile/api-tokens"
    while true; do
        read -s -p "Cloudflare API key: " CLOUDFLARE_API_KEY
        echo ""
        if [[ -n "$CLOUDFLARE_API_KEY" && ${#CLOUDFLARE_API_KEY} -ge 32 ]]; then
            break
        else
            error "API key seems too short. Please check and try again."
        fi
    done
    
    log "Configuration collected successfully"
}

# Function to create environment variables
create_env_vars() {
    log "Creating environment variables..."
    
    # Check if we're in interactive mode or if vars file exists
    if [[ -f "remnawave-vars.sh" ]]; then
        log "Found existing remnawave-vars.sh file"
        read -p "Do you want to use existing configuration? (Y/n): " use_existing
        if [[ $use_existing != [nN] && $use_existing != [nN][oO] ]]; then
            source remnawave-vars.sh
            # Validate required variables
            if [[ -z "$PANEL_DOMAIN" || -z "$SUB_DOMAIN" || -z "$SELFSTEAL_DOMAIN" || -z "$CLOUDFLARE_API_KEY" || -z "$CLOUDFLARE_EMAIL" ]]; then
                warning "Existing configuration is incomplete. Collecting new configuration..."
                collect_user_input
            else
                log "Using existing configuration"
                return
            fi
        else
            collect_user_input
        fi
    else
        collect_user_input
    fi
    
    # Generate random variables
    export SUPERADMIN_USERNAME=$(tr -dc 'a-zA-Z' < /dev/urandom | fold -w 8 | head -n 1)
    
    # Proper password generation
    password=""
    password+=$(head /dev/urandom | tr -dc 'A-Z' | head -c 1)
    password+=$(head /dev/urandom | tr -dc 'a-z' | head -c 1)
    password+=$(head /dev/urandom | tr -dc '0-9' | head -c 1)
    password+=$(head /dev/urandom | tr -dc '!@#%^&*()_+' | head -c 3)
    password+=$(head /dev/urandom | tr -dc 'A-Za-z0-9!@#%^&*()_+' | head -c $((24 - 6)))
    export SUPERADMIN_PASSWORD=$(echo "$password" | fold -w1 | shuf | tr -d '\n')
    
    export cookies_random1=$(tr -dc 'a-zA-Z' < /dev/urandom | fold -w 8 | head -n 1)
    export cookies_random2=$(tr -dc 'a-zA-Z' < /dev/urandom | fold -w 8 | head -n 1)
    export METRICS_USER=$(tr -dc 'a-zA-Z' < /dev/urandom | fold -w 8 | head -n 1)
    export METRICS_PASS=$(tr -dc 'a-zA-Z' < /dev/urandom | fold -w 8 | head -n 1)
    export JWT_AUTH_SECRET=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 64)
    export JWT_API_TOKENS_SECRET=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 64)
    
    # Save to file
    cat > remnawave-vars.sh << EOF
# remnawave-vars.sh
export PANEL_DOMAIN="$PANEL_DOMAIN"
export SUB_DOMAIN="$SUB_DOMAIN"
export SELFSTEAL_DOMAIN="$SELFSTEAL_DOMAIN"
export CLOUDFLARE_API_KEY="$CLOUDFLARE_API_KEY"
export CLOUDFLARE_EMAIL="$CLOUDFLARE_EMAIL"

# Generated variables
export SUPERADMIN_USERNAME="$SUPERADMIN_USERNAME"
export SUPERADMIN_PASSWORD="$SUPERADMIN_PASSWORD"
export cookies_random1="$cookies_random1"
export cookies_random2="$cookies_random2"
export METRICS_USER="$METRICS_USER"
export METRICS_PASS="$METRICS_PASS"
export JWT_AUTH_SECRET="$JWT_AUTH_SECRET"
export JWT_API_TOKENS_SECRET="$JWT_API_TOKENS_SECRET"
EOF
    
    chmod 600 remnawave-vars.sh
    log "Environment variables saved to remnawave-vars.sh"
}

# Function to check system requirements
check_system_requirements() {
    log "Checking system requirements..."
    
    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        error "Cannot determine OS version"
    fi
    
    source /etc/os-release
    log "Operating System: $PRETTY_NAME"
    
    if [[ "$ID" != "ubuntu" ]]; then
        warning "This script is optimized for Ubuntu. Your OS: $ID"
        read -p "Continue anyway? (y/N): " continue_anyway
        if [[ $continue_anyway != [yY] && $continue_anyway != [yY][eE][sS] ]]; then
            exit 1
        fi
    fi
    
    # Check architecture
    ARCH=$(uname -m)
    log "Architecture: $ARCH"
    if [[ "$ARCH" != "x86_64" && "$ARCH" != "amd64" ]]; then
        warning "Unsupported architecture: $ARCH. Recommended: x86_64/amd64"
    fi
    
    # Check memory
    TOTAL_MEM=$(free -m | grep ^Mem | awk '{print $2}')
    log "Total Memory: ${TOTAL_MEM}MB"
    if [[ $TOTAL_MEM -lt 512 ]]; then
        error "Insufficient memory. Minimum 512MB required, 1GB+ recommended."
    elif [[ $TOTAL_MEM -lt 1024 ]]; then
        warning "Low memory detected (${TOTAL_MEM}MB). 1GB+ recommended for optimal performance."
    fi
    
    # Check disk space
    AVAILABLE_SPACE=$(df / | tail -1 | awk '{print $4}')
    AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))
    log "Available disk space: ${AVAILABLE_GB}GB"
    if [[ $AVAILABLE_SPACE -lt 2097152 ]]; then # 2GB in KB
        error "Insufficient disk space. At least 2GB required."
    fi
    
    # Check internet connection
    log "Checking internet connectivity..."
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        error "No internet connection available"
    fi
    
    # Check if ports are available
    log "Checking port availability..."
    for port in 80 443 22; do
        if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
            warning "Port $port is already in use"
        fi
    done
    
    log "System requirements check completed"
}

# Function to install packages
install_packages() {
    log "Updating system and installing packages..."
    
    # Update package list
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y || error "Failed to update package list"
    
    # Install essential packages first
    log "Installing essential packages..."
    apt-get install -y ca-certificates curl jq wget gnupg unzip || error "Failed to install essential packages"
    
    # Install additional packages
    log "Installing additional packages..."
    apt-get install -y ufw nano dialog git certbot python3-certbot-dns-cloudflare \
        unattended-upgrades locales dnsutils coreutils grep gawk net-tools || \
        error "Failed to install additional packages"
    
    # Install and enable cron
    log "Setting up cron service..."
    apt-get install -y cron || error "Failed to install cron"
    systemctl start cron
    systemctl enable cron
    
    # Set locale
    log "Configuring system locale..."
    if ! grep -q "en_US.UTF-8 UTF-8" /etc/locale.gen; then
        echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    fi
    locale-gen
    update-locale LANG=en_US.UTF-8
    
    log "Packages installed successfully"
}

# Function to install Docker
install_docker() {
    log "Installing Docker..."
    
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | tee /etc/apt/keyrings/docker.asc > /dev/null
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    log "Docker installed successfully"
}

# Function to configure system
configure_system() {
    log "Configuring system settings..."
    
    # Configure BBR
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    sysctl -p
    
    # Configure UFW
    ufw --force reset
    ufw allow 22/tcp comment 'SSH'
    ufw allow 443/tcp comment 'HTTPS'
    ufw --force enable
    
    # Configure unattended upgrades
    echo 'Unattended-Upgrade::Mail "root";' >> /etc/apt/apt.conf.d/50unattended-upgrades
    echo unattended-upgrades unattended-upgrades/enable_auto_updates boolean true | debconf-set-selections
    dpkg-reconfigure -f noninteractive unattended-upgrades
    systemctl restart unattended-upgrades
    
    log "System configured successfully"
}

# Function to check if SSL certificates exist
check_existing_certificates() {
    local domain="$1"
    local cert_path="/etc/letsencrypt/live/$domain"
    
    if [[ -d "$cert_path" && -f "$cert_path/fullchain.pem" && -f "$cert_path/privkey.pem" ]]; then
        return 0
    else
        return 1
    fi
}

# Function to setup SSL certificates
setup_ssl() {
    log "Setting up SSL certificates..."
    
    # Create directory structure
    mkdir -p /opt/remnawave && cd /opt/remnawave
    
    # Verify Cloudflare API
    log "Verifying Cloudflare API credentials..."
    if [[ $CLOUDFLARE_API_KEY =~ [A-Z] ]]; then
        api_response=$(curl --silent --request GET --url https://api.cloudflare.com/client/v4/zones --header "Authorization: Bearer ${CLOUDFLARE_API_KEY}" --header "Content-Type: application/json")
    else
        api_response=$(curl --silent --request GET --url https://api.cloudflare.com/client/v4/zones --header "X-Auth-Key: ${CLOUDFLARE_API_KEY}" --header "X-Auth-Email: ${CLOUDFLARE_EMAIL}" --header "Content-Type: application/json")
    fi
    
    if ! echo "$api_response" | jq -e '.success' > /dev/null 2>&1; then
        error "Failed to verify Cloudflare API credentials. Please check your API key and email."
    fi
    log "Cloudflare API credentials verified successfully"
    
    # Setup Cloudflare credentials for certbot
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
    PANEL_BASE_DOMAIN=$(echo "$PANEL_DOMAIN" | awk -F'.' '{if (NF > 2) {print $(NF-1)"."$NF} else {print $0}}')
    SUB_BASE_DOMAIN=$(echo "$SUB_DOMAIN" | awk -F'.' '{if (NF > 2) {print $(NF-1)"."$NF} else {print $0}}')
    
    # Check and generate certificate for panel domain
    if check_existing_certificates "$PANEL_BASE_DOMAIN"; then
        log "SSL certificate for $PANEL_BASE_DOMAIN already exists, skipping generation"
        
        # Check certificate validity
        cert_expiry=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$PANEL_BASE_DOMAIN/fullchain.pem" | cut -d= -f2)
        cert_expiry_epoch=$(date -d "$cert_expiry" +%s)
        current_epoch=$(date +%s)
        days_until_expiry=$(( (cert_expiry_epoch - current_epoch) / 86400 ))
        
        if [[ $days_until_expiry -lt 30 ]]; then
            warning "Certificate for $PANEL_BASE_DOMAIN expires in $days_until_expiry days. Consider renewal."
        else
            log "Certificate for $PANEL_BASE_DOMAIN is valid for $days_until_expiry more days"
        fi
    else
        log "Generating SSL certificate for $PANEL_BASE_DOMAIN..."
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
        
        if [[ $? -eq 0 ]]; then
            log "SSL certificate for $PANEL_BASE_DOMAIN generated successfully"
        else
            error "Failed to generate SSL certificate for $PANEL_BASE_DOMAIN"
        fi
    fi
    
    # Check and generate certificate for subscription domain (only if different from panel domain)
    if [[ "$SUB_BASE_DOMAIN" != "$PANEL_BASE_DOMAIN" ]]; then
        if check_existing_certificates "$SUB_BASE_DOMAIN"; then
            log "SSL certificate for $SUB_BASE_DOMAIN already exists, skipping generation"
            
            # Check certificate validity
            cert_expiry=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$SUB_BASE_DOMAIN/fullchain.pem" | cut -d= -f2)
            cert_expiry_epoch=$(date -d "$cert_expiry" +%s)
            current_epoch=$(date +%s)
            days_until_expiry=$(( (cert_expiry_epoch - current_epoch) / 86400 ))
            
            if [[ $days_until_expiry -lt 30 ]]; then
                warning "Certificate for $SUB_BASE_DOMAIN expires in $days_until_expiry days. Consider renewal."
            else
                log "Certificate for $SUB_BASE_DOMAIN is valid for $days_until_expiry more days"
            fi
        else
            log "Generating SSL certificate for $SUB_BASE_DOMAIN..."
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
            
            if [[ $? -eq 0 ]]; then
                log "SSL certificate for $SUB_BASE_DOMAIN generated successfully"
            else
                error "Failed to generate SSL certificate for $SUB_BASE_DOMAIN"
            fi
        fi
    else
        log "Subscription domain uses same base domain as panel, certificate already covered"
    fi
    
    # Setup renewal hooks (only if not already present)
    if ! grep -q "renew_hook.*remnawave-nginx" "/etc/letsencrypt/renewal/$PANEL_BASE_DOMAIN.conf" 2>/dev/null; then
        echo "renew_hook = sh -c 'cd /opt/remnawave && docker compose down remnawave-nginx && docker compose up -d remnawave-nginx'" >> /etc/letsencrypt/renewal/$PANEL_BASE_DOMAIN.conf
        log "Added renewal hook for $PANEL_BASE_DOMAIN"
    fi
    
    if [[ "$SUB_BASE_DOMAIN" != "$PANEL_BASE_DOMAIN" ]] && ! grep -q "renew_hook.*remnawave-nginx" "/etc/letsencrypt/renewal/$SUB_BASE_DOMAIN.conf" 2>/dev/null; then
        echo "renew_hook = sh -c 'cd /opt/remnawave && docker compose down remnawave-nginx && docker compose up -d remnawave-nginx'" >> /etc/letsencrypt/renewal/$SUB_BASE_DOMAIN.conf
        log "Added renewal hook for $SUB_BASE_DOMAIN"
    fi
    
    # Setup cron job for renewal (only if not already present)
    if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
        (crontab -u root -l 2>/dev/null; echo "0 5 1 */2 * /usr/bin/certbot renew --quiet >> /usr/local/remnawave_reverse/cron_jobs.log 2>&1") | crontab -u root -
        log "Added cron job for certificate renewal"
    else
        log "Certificate renewal cron job already exists"
    fi
    
    log "SSL certificates configuration completed successfully"
}

# Function to create configuration files
create_configs() {
    log "Creating configuration files..."
    
    cd /opt/remnawave
    
    # Create .env file
    cat > .env <<EOL
### APP ###
APP_PORT=3000
METRICS_PORT=3001

### API ###
# Possible values: max (start instances on all cores), number (start instances on number of cores), -1 (start instances on all cores - 1)
# !!! Do not set this value more than physical cores count in your machine !!!
# Review documentation: https://remna.st/docs/install/environment-variables#scaling-api
API_INSTANCES=1

### DATABASE ###
# FORMAT: postgresql://{user}:{password}@{host}:{port}/{database}
DATABASE_URL="postgresql://postgres:postgres@remnawave-db:5432/postgres"

### REDIS ###
REDIS_HOST=remnawave-redis
REDIS_PORT=6379

### JWT ###
JWT_AUTH_SECRET=$JWT_AUTH_SECRET
JWT_API_TOKENS_SECRET=$JWT_API_TOKENS_SECRET

### TELEGRAM NOTIFICATIONS ###
IS_TELEGRAM_NOTIFICATIONS_ENABLED=false
TELEGRAM_BOT_TOKEN=change_me
TELEGRAM_NOTIFY_USERS_CHAT_ID=change_me
TELEGRAM_NOTIFY_NODES_CHAT_ID=change_me

### Telegram Oauth (Login with Telegram)
### Docs https://remna.st/docs/features/telegram-oauth
### true/false
TELEGRAM_OAUTH_ENABLED=false
### Array of Admin Chat Ids. These ids will be allowed to login.
TELEGRAM_OAUTH_ADMIN_IDS=[123, 321]

# Optional
# Only set if you want to use topics
TELEGRAM_NOTIFY_USERS_THREAD_ID=
TELEGRAM_NOTIFY_NODES_THREAD_ID=

### FRONT_END ###
# Used by CORS, you can leave it as * or place your domain there
FRONT_END_DOMAIN=$PANEL_DOMAIN

### SUBSCRIPTION PUBLIC DOMAIN ###
### DOMAIN, WITHOUT HTTP/HTTPS, DO NOT ADD / AT THE END ###
### Used in "profile-web-page-url" response header and in UI/API ###
### Review documentation: https://remna.st/docs/install/environment-variables#domains
SUB_PUBLIC_DOMAIN=$SUB_DOMAIN

### If CUSTOM_SUB_PREFIX is set in @remnawave/subscription-page, append the same path to SUB_PUBLIC_DOMAIN. Example: SUB_PUBLIC_DOMAIN=sub-page.example.com/sub ###

### SWAGGER ###
SWAGGER_PATH=/docs
SCALAR_PATH=/scalar
IS_DOCS_ENABLED=true

### PROMETHEUS ###
### Metrics are available at /api/metrics
METRICS_USER=$METRICS_USER
METRICS_PASS=$METRICS_PASS

### WEBHOOK ###
WEBHOOK_ENABLED=false
### Only https:// is allowed
WEBHOOK_URL=https://webhook.site/1234567890
### This secret is used to sign the webhook payload, must be exact 64 characters. Only a-z, 0-9, A-Z are allowed.
WEBHOOK_SECRET_HEADER=vsmu67Kmg6R8FjIOF1WUY8LWBHie4scdEqrfsKmyf4IAf8dY3nFS0wwYHkhh6ZvQ

### HWID DEVICE DETECTION AND LIMITATION ###
# Don't enable this if you don't know what you are doing.
# Review documentation before enabling this feature.
# https://remna.st/docs/features/hwid-device-limit/
HWID_DEVICE_LIMIT_ENABLED=false
HWID_FALLBACK_DEVICE_LIMIT=5
HWID_MAX_DEVICES_ANNOUNCE="You have reached the maximum number of devices for your subscription."

### HWID DEVICE DETECTION PROVIDER ID ###
# Apps, which currently support this feature:
# - Happ
PROVIDER_ID="123456"

### Bandwidth usage reached notifications
BANDWIDTH_USAGE_NOTIFICATIONS_ENABLED=false
# Only in ASC order (example: [60, 80]), must be valid array of integer(min: 25, max: 95) numbers. No more than 5 values.
BANDWIDTH_USAGE_NOTIFICATIONS_THRESHOLD=[60, 80]

### CLOUDFLARE ###
# USED ONLY FOR docker-compose-prod-with-cf.yml
# NOT USED BY THE APP ITSELF
CLOUDFLARE_TOKEN=ey...

### Database ###
### For Postgres Docker container ###
# NOT USED BY THE APP ITSELF
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=postgres
EOL

    # Create docker-compose.yml
    cat > docker-compose.yml <<EOL
services:
  remnawave-db:
    image: postgres:17
    container_name: 'remnawave-db'
    hostname: remnawave-db
    restart: always
    env_file:
      - .env
    environment:
      - POSTGRES_USER=\${POSTGRES_USER}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
      - POSTGRES_DB=\${POSTGRES_DB}
      - TZ=UTC
    ports:
      - '127.0.0.1:6767:5432'
    volumes:
      - remnawave-db-data:/var/lib/postgresql/data
    networks:
      - remnawave-network
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U \$\${POSTGRES_USER} -d \$\${POSTGRES_DB}']
      interval: 3s
      timeout: 10s
      retries: 3
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnawave:
    image: remnawave/backend:latest
    container_name: remnawave
    hostname: remnawave
    restart: always
    env_file:
      - .env
    ports:
      - '127.0.0.1:3000:3000'
    networks:
      - remnawave-network
    depends_on:
      remnawave-db:
        condition: service_healthy
      remnawave-redis:
        condition: service_healthy
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnawave-redis:
    image: valkey/valkey:8.1.1-alpine
    container_name: remnawave-redis
    hostname: remnawave-redis
    restart: always
    networks:
      - remnawave-network
    volumes:
      - remnawave-redis-data:/data
    healthcheck:
      test: [ "CMD", "valkey-cli", "ping" ]
      interval: 3s
      timeout: 10s
      retries: 3
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnawave-nginx:
    image: nginx:1.26
    container_name: remnawave-nginx
    hostname: remnawave-nginx
    restart: always
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - /etc/letsencrypt/live/$PANEL_BASE_DOMAIN/fullchain.pem:/etc/nginx/ssl/$PANEL_DOMAIN/fullchain.pem:ro
      - /etc/letsencrypt/live/$PANEL_BASE_DOMAIN/privkey.pem:/etc/nginx/ssl/$PANEL_DOMAIN/privkey.pem:ro
      - /etc/letsencrypt/live/$SUB_BASE_DOMAIN/fullchain.pem:/etc/nginx/ssl/$SUB_DOMAIN/fullchain.pem:ro
      - /etc/letsencrypt/live/$SUB_BASE_DOMAIN/privkey.pem:/etc/nginx/ssl/$SUB_DOMAIN/privkey.pem:ro
    network_mode: host
    depends_on:
      - remnawave
      - remnawave-subscription-page
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnawave-subscription-page:
    image: remnawave/subscription-page:latest
    container_name: remnawave-subscription-page
    hostname: remnawave-subscription-page
    restart: always
    environment:
      - REMNAWAVE_PANEL_URL=http://remnawave:3000
      - APP_PORT=3010
      - META_TITLE=Remnawave Subscription
      - META_DESCRIPTION=page
    ports:
      - '127.0.0.1:3010:3010'
    networks:
      - remnawave-network
    volumes:
      - ./index.html:/opt/app/frontend/index.html
      - ./assets:/opt/app/frontend/assets
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

networks:
  remnawave-network:
    name: remnawave-network
    driver: bridge
    external: false

volumes:
  remnawave-db-data:
    driver: local
    external: false
    name: remnawave-db-data
  remnawave-redis-data:
    driver: local
    external: false
    name: remnawave-redis-data
EOL

    # Download subscription page template
    wget -P /opt/remnawave/ https://raw.githubusercontent.com/supermegaelf/rm-pages/main/index.html
    
    log "Configuration files created successfully"
}

# Function to create nginx configuration
create_nginx_config() {
    log "Creating nginx configuration..."
    
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
    "~*${cookies_random1}=${cookies_random2}" 1;
}

map \$arg_${cookies_random1} \$auth_query {
    default 0;
    "${cookies_random2}" 1;
}

map "\$auth_cookie\$auth_query" \$authorized {
    "~1" 1;
    default 0;
}

map \$arg_${cookies_random1} \$set_cookie_header {
    "${cookies_random2}" "${cookies_random1}=${cookies_random2}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=31536000";
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

    log "Nginx configuration created successfully"
}

# Function to start containers
start_containers() {
    log "Starting Docker containers..."
    
    cd /opt/remnawave
    
    # Pull latest images
    log "Pulling latest Docker images..."
    docker compose pull || warning "Failed to pull some images, continuing with existing ones"
    
    # Start containers
    log "Starting containers..."
    if docker compose up -d; then
        log "Containers started successfully"
    else
        error "Failed to start containers. Check docker compose logs for details."
    fi
    
    # Show container status
    log "Container status:"
    docker compose ps
    
    # Wait for services to be ready
    log "Waiting for services to be ready..."
    
    # Wait for database
    log "Waiting for database..."
    for i in {1..60}; do
        if docker compose exec -T remnawave-db pg_isready -U postgres >/dev/null 2>&1; then
            log "Database is ready"
            break
        fi
        if [[ $i -eq 60 ]]; then
            error "Database failed to start within 60 seconds"
        fi
        sleep 1
    done
    
    # Wait for Redis
    log "Waiting for Redis..."
    for i in {1..30}; do
        if docker compose exec -T remnawave-redis valkey-cli ping >/dev/null 2>&1; then
            log "Redis is ready"
            break
        fi
        if [[ $i -eq 30 ]]; then
            error "Redis failed to start within 30 seconds"
        fi
        sleep 1
    done
    
    # Wait for main application
    log "Waiting for Remnawave application..."
    for i in {1..120}; do
        if curl -s "http://127.0.0.1:3000/api/auth/register" \
            --header 'X-Forwarded-For: 127.0.0.1' \
            --header 'X-Forwarded-Proto: https' \
            --connect-timeout 5 > /dev/null 2>&1; then
            log "Remnawave application is ready"
            break
        fi
        if [[ $i -eq 120 ]]; then
            error "Remnawave application failed to start within 120 seconds"
        fi
        sleep 1
        if [[ $((i % 10)) -eq 0 ]]; then
            log "Still waiting for application... ($i/120)"
        fi
    done
    
    log "All services are ready"
}

# Function to configure via API
configure_api() {
    log "Configuring via API..."
    
    domain_url="127.0.0.1:3000"
    
    # Register admin user
    log "Registering admin user..."
    register_response=$(curl -s -X POST "http://$domain_url/api/auth/register" \
        -H "Authorization: Bearer " \
        -H "Content-Type: application/json" \
        -H "Host: $PANEL_DOMAIN" \
        -H "X-Forwarded-For: 127.0.0.1" \
        -H "X-Forwarded-Proto: https" \
        -d "{\"username\":\"$SUPERADMIN_USERNAME\",\"password\":\"$SUPERADMIN_PASSWORD\"}")
    
    token=$(echo "$register_response" | jq -r '.response.accessToken')
    
    if [[ "$token" == "null" ]]; then
        error "Failed to register admin user"
    fi
    
    # Get public key
    log "Getting public key..."
    api_response=$(curl -s -X GET "http://$domain_url/api/keygen" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -H "Host: $PANEL_DOMAIN" \
        -H "X-Forwarded-For: 127.0.0.1" \
        -H "X-Forwarded-Proto: https")
    
    pubkey=$(echo "$api_response" | jq -r '.response.pubKey')
    
    # Generate Xray keys
    log "Generating Xray keys..."
    docker run --rm ghcr.io/xtls/xray-core x25519 > /tmp/xray_keys.txt 2>&1
    keys=$(cat /tmp/xray_keys.txt)
    rm -f /tmp/xray_keys.txt
    private_key=$(echo "$keys" | grep "Private key:" | awk '{print $3}')
    public_key=$(echo "$keys" | grep "Public key:" | awk '{print $3}')
    
    # Create Xray configuration
    log "Creating Xray configuration..."
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

    # Update Xray configuration
    new_config=$(cat "$config_file")
    update_response=$(curl -s -X PUT "http://$domain_url/api/xray" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -H "Host: $PANEL_DOMAIN" \
        -H "X-Forwarded-For: 127.0.0.1" \
        -H "X-Forwarded-Proto: https" \
        -d "$new_config")
    
    rm -f "$config_file"
    
    # Create node
    log "Creating node..."
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
    log "Getting inbound UUID..."
    inbounds_response=$(curl -s -X GET "http://$domain_url/api/inbounds" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -H "Host: $PANEL_DOMAIN" \
        -H "X-Forwarded-For: 127.0.0.1" \
        -H "X-Forwarded-Proto: https")
    
    inbound_uuid=$(echo "$inbounds_response" | jq -r '.response[0].uuid')
    
    # Create host
    log "Creating host..."
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
    
    log "API configuration completed successfully"
}

# Function to restart containers
restart_containers() {
    log "Restarting containers..."
    
    cd /opt/remnawave
    docker compose down
    sleep 2
    
    log "Starting containers in background..."
    if docker compose up -d; then
        log "Containers started successfully in background"
        
        # Brief wait to ensure services are starting
        sleep 5
        
        # Show container status
        log "Container status:"
        docker compose ps
        
        # Check if containers are running
        if docker compose ps | grep -q "Up"; then
            log "✅ All containers are running"
        else
            warning "Some containers may not be running properly"
            log "You can check logs with: cd /opt/remnawave && docker compose logs -f"
        fi
    else
        error "Failed to restart containers"
    fi
}

# Function to setup aliases
setup_aliases() {
    log "Setting up aliases..."
    
    mkdir -p /usr/local/remnawave_reverse/
    wget -q -O /usr/local/remnawave_reverse/remnawave_reverse "https://raw.githubusercontent.com/eGamesAPI/remnawave-reverse-proxy/refs/heads/main/install_remnawave.sh"
    chmod +x /usr/local/remnawave_reverse/remnawave_reverse
    ln -sf /usr/local/remnawave_reverse/remnawave_reverse /usr/local/bin/remnawave_reverse
    
    bashrc_file="/etc/bash.bashrc"
    alias_line="alias rr='remnawave_reverse'"
    echo "$alias_line" >> "$bashrc_file"
    
    log "Aliases configured successfully"
}

# Function to configure timezone
configure_timezone() {
    log "Configuring timezone..."
    timedatectl set-timezone Europe/Moscow
    log "Timezone set to Europe/Moscow"
}

# Function to display results
display_results() {
    clear
    echo -e "${GREEN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                    INSTALLATION COMPLETED!                    ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    echo -e "${BLUE}🎉 Remnawave has been successfully installed!${NC}"
    echo ""
    
    echo -e "${YELLOW}📋 ACCESS INFORMATION:${NC}"
    echo "================================================="
    echo -e "${GREEN}Panel URL:${NC}"
    echo "https://${PANEL_DOMAIN}/auth/login?${cookies_random1}=${cookies_random2}"
    echo ""
    echo -e "${GREEN}Login Credentials:${NC}"
    echo "Username: $SUPERADMIN_USERNAME"
    echo "Password: $SUPERADMIN_PASSWORD"
    echo ""
    echo -e "${GREEN}Subscription URL:${NC}"
    echo "https://${SUB_DOMAIN}/"
    echo ""
    
    echo -e "${YELLOW}🔧 MANAGEMENT COMMANDS:${NC}"
    echo "================================================="
    echo "View logs:             cd /opt/remnawave && docker compose logs -f"
    echo "Restart services:      cd /opt/remnawave && docker compose restart"
    echo "Stop services:         cd /opt/remnawave && docker compose down"
    echo "Start services:        cd /opt/remnawave && docker compose up -d"
    echo "Quick manager:         remnawave_reverse"
    echo "Quick alias:           rr"
    echo ""
    
    echo -e "${YELLOW}📁 IMPORTANT FILES:${NC}"
    echo "================================================="
    echo "Configuration:         /opt/remnawave/remnawave-vars.sh"
    echo "Docker compose:        /opt/remnawave/docker-compose.yml"
    echo "Nginx config:          /opt/remnawave/nginx.conf"
    echo "SSL certificates:      /etc/letsencrypt/live/"
    echo ""
    
    # Check services status
    echo -e "${YELLOW}📊 SERVICES STATUS:${NC}"
    echo "================================================="
    cd /opt/remnawave
    
    if docker compose ps | grep -q "remnawave.*Up"; then
        echo "Remnawave Panel: ✅ Running"
    else
        echo "Remnawave Panel: ❌ Not running"
    fi
    
    if docker compose ps | grep -q "remnawave-db.*Up"; then
        echo "Database: ✅ Running"
    else
        echo "Database: ❌ Not running"
    fi
    
    if docker compose ps | grep -q "remnawave-redis.*Up"; then
        echo "Redis: ✅ Running"
    else
        echo "Redis: ❌ Not running"
    fi
    
    if docker compose ps | grep -q "remnawave-nginx.*Up"; then
        echo "Nginx: ✅ Running"
    else
        echo "Nginx: ❌ Not running"
    fi
    
    if docker compose ps | grep -q "remnawave-subscription-page.*Up"; then
        echo "Subscription Page: ✅ Running"
    else
        echo "Subscription Page: ❌ Not running"
    fi
    echo ""
    
    # Check certificate status
    echo -e "${YELLOW}🔒 CERTIFICATE STATUS:${NC}"
    echo "================================================="
    PANEL_BASE_DOMAIN=$(echo "$PANEL_DOMAIN" | awk -F'.' '{if (NF > 2) {print $(NF-1)"."$NF} else {print $0}}')
    SUB_BASE_DOMAIN=$(echo "$SUB_DOMAIN" | awk -F'.' '{if (NF > 2) {print $(NF-1)"."$NF} else {print $0}}')
    
    if check_existing_certificates "$PANEL_BASE_DOMAIN"; then
        cert_expiry=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$PANEL_BASE_DOMAIN/fullchain.pem" | cut -d= -f2 | cut -d' ' -f1-3)
        echo "Panel certificate: ✅ Valid until $cert_expiry"
    else
        echo "Panel certificate: ❌ Not found"
    fi
    
    if [[ "$SUB_BASE_DOMAIN" != "$PANEL_BASE_DOMAIN" ]] && check_existing_certificates "$SUB_BASE_DOMAIN"; then
        cert_expiry=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$SUB_BASE_DOMAIN/fullchain.pem" | cut -d= -f2 | cut -d' ' -f1-3)
        echo "Subscription certificate: ✅ Valid until $cert_expiry"
    fi
    echo ""
    
    echo -e "${YELLOW}🛡️ SECURITY RECOMMENDATIONS:${NC}"
    echo "================================================="
    echo "1. 💾 Save these credentials in a secure password manager"
    echo "2. 🔑 Configure SSH key authentication (recommended)"
    echo "3. 🚪 Change SSH port from default 22"
    echo "4. 🔄 Regularly update your system: apt update && apt upgrade"
    echo "5. 📊 Monitor logs for suspicious activity"
    echo "6. 💾 Setup automated backups of /opt/remnawave/ directory"
    echo ""
    
    echo -e "${YELLOW}🌐 NEXT STEPS:${NC}"
    echo "================================================="
    echo "1. 🔗 Access your panel using the URL above"
    echo "2. 🛡️ Run SSH security script for better security"
    echo "3. 🌍 Install WARP proxy for bypassing restrictions"
    echo "4. 👥 Create user accounts in the panel"
    echo "5. 📱 Generate subscription links for clients"
    echo ""
    
    echo -e "${YELLOW}📋 USEFUL COMMANDS:${NC}"
    echo "================================================="
    echo "Check logs:            cd /opt/remnawave && docker compose logs"
    echo "Follow logs:           cd /opt/remnawave && docker compose logs -f"
    echo "Container status:      cd /opt/remnawave && docker compose ps"
    echo "Restart all:           cd /opt/remnawave && docker compose restart"
    echo "Update images:         cd /opt/remnawave && docker compose pull && docker compose up -d"
    echo ""
    
    echo -e "${RED}⚠️  IMPORTANT NOTES:${NC}"
    echo "================================================="
    echo "🔴 SAVE YOUR CREDENTIALS NOW - They won't be shown again!"
    echo "🔴 Test the panel access before closing this terminal!"
    echo "🔴 Services are running in background - check logs if needed!"
    echo "🔴 Configure additional security measures!"
    echo ""
    
    # Final status check
    log "Performing final connectivity test..."
    if curl -s --connect-timeout 5 "http://127.0.0.1:3000/api/auth/register" \
        --header 'X-Forwarded-For: 127.0.0.1' \
        --header 'X-Forwarded-Proto: https' > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Panel is responding on localhost${NC}"
    else
        echo -e "${YELLOW}⚠️  Panel may still be starting up - wait a moment and try accessing${NC}"
        echo -e "${BLUE}💡 If issues persist, check logs: cd /opt/remnawave && docker compose logs -f${NC}"
    fi
    echo ""
    
    # Wait for user confirmation
    echo -e "${GREEN}Press Enter after saving your credentials...${NC}"
    read
    
    echo -e "${BLUE}🎊 Installation completed successfully!${NC}"
    echo "📞 For support, check the documentation or community forums."
    echo "🔍 Logs are available in background: cd /opt/remnawave && docker compose logs -f"
    echo ""
}echo "Username: $SUPERADMIN_USERNAME"
    echo "Password: $SUPERADMIN_PASSWORD"
    echo "-------------------------------------------------"
    echo "To relaunch the manager, use the following command:"
    echo "remnawave_reverse"
    echo "================================================="
    echo ""
    echo "Save these credentials in a secure place!"
    echo ""
}

# Main installation function
main() {
    log "Starting Remnawave installation..."
    
    # System checks
    check_system_requirements
    
    # Check for existing installation
    check_existing_installation
    
    # Show configuration summary before starting
    echo ""
    echo -e "${BLUE}Installation Configuration Summary:${NC}"
    echo "=================================="
    
    collect_user_input
    
    echo ""
    echo "Panel Domain: $PANEL_DOMAIN"
    echo "Subscription Domain: $SUB_DOMAIN"
    echo "Reality Domain: $SELFSTEAL_DOMAIN"
    echo "Cloudflare Email: $CLOUDFLARE_EMAIL"
    echo "API Key: ${CLOUDFLARE_API_KEY:0:8}..."
    echo ""
    
    read -p "Continue with this configuration? (Y/n): " confirm_config
    if [[ $confirm_config == [nN] || $confirm_config == [nN][oO] ]]; then
        log "Installation cancelled by user"
        exit 0
    fi
    
    create_env_vars
    check_dns_records
    install_packages
    install_docker
    configure_system
    setup_ssl
    create_configs
    create_nginx_config
    start_containers
    configure_api
    restart_containers
    setup_aliases
    configure_timezone
    display_results
    
    log "Installation completed successfully!"
}

# Run main function
main "$@"
