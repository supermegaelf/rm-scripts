#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Remnawave Node setup script
echo
echo -e "${PURPLE}=======================${NC}"
echo -e "${NC}REMNAWAVE PANNEL SETUP${NC}"
echo -e "${PURPLE}=======================${NC}"
echo

set -e

echo -e "${GREEN}=========================${NC}"
echo -e "${NC}1. Environment variables${NC}"
echo -e "${GREEN}=========================${NC}"
echo

# Interactive input for variables
echo -e "${CYAN}Please enter the required information:${NC}"
echo

# Self-steal domain
read -p "Self-steal domain (e.g., example.com): " SELFSTEAL_DOMAIN
while [[ -z "$SELFSTEAL_DOMAIN" ]]; do
    echo -e "${RED}Self-steal domain cannot be empty!${NC}"
    read -p "Self-steal domain (e.g., example.com): " SELFSTEAL_DOMAIN
done

# Panel IP
read -p "Panel IP address: " PANEL_IP
while [[ -z "$PANEL_IP" ]]; do
    echo -e "${RED}Panel IP cannot be empty!${NC}"
    read -p "Panel IP address: " PANEL_IP
done

# Cloudflare API Key
read -p "Cloudflare API Key: " CLOUDFLARE_API_KEY
while [[ -z "$CLOUDFLARE_API_KEY" ]]; do
    echo -e "${RED}Cloudflare API Key cannot be empty!${NC}"
    read -p "Cloudflare API Key: " CLOUDFLARE_API_KEY
done

# Cloudflare Email
read -p "Cloudflare Email: " CLOUDFLARE_EMAIL
while [[ -z "$CLOUDFLARE_EMAIL" ]]; do
    echo -e "${RED}Cloudflare Email cannot be empty!${NC}"
    read -p "Cloudflare Email: " CLOUDFLARE_EMAIL
done

# Certificate from panel
echo
echo -e "${YELLOW}Please paste the certificate from the panel:${NC}"
echo -e "${CYAN}(Include the entire SSL_CERT=\"...\" line)${NC}"
echo -e "${CYAN}Press Enter when done:${NC}"
read -r CERTIFICATE
while [[ -z "$CERTIFICATE" ]]; do
    echo -e "${RED}Certificate cannot be empty!${NC}"
    echo -e "${CYAN}Please paste the entire SSL_CERT=\"...\" line:${NC}"
    read -r CERTIFICATE
done

# Create variables file for persistence
cat > node-vars.sh << 'EOF'
# node-vars.sh
export SELFSTEAL_DOMAIN="${SELFSTEAL_DOMAIN}"
export PANEL_IP="${PANEL_IP}"
export CLOUDFLARE_API_KEY="${CLOUDFLARE_API_KEY}"
export CLOUDFLARE_EMAIL="${CLOUDFLARE_EMAIL}"
# Certificate from the panel
export CERTIFICATE='${CERTIFICATE}'
EOF

# Replace placeholders with actual values
sed -i "s|\${SELFSTEAL_DOMAIN}|$SELFSTEAL_DOMAIN|g" node-vars.sh
sed -i "s|\${PANEL_IP}|$PANEL_IP|g" node-vars.sh
sed -i "s|\${CLOUDFLARE_API_KEY}|$CLOUDFLARE_API_KEY|g" node-vars.sh
sed -i "s|\${CLOUDFLARE_EMAIL}|$CLOUDFLARE_EMAIL|g" node-vars.sh
# For certificate, we need to escape it properly
escaped_cert=$(printf '%s\n' "$CERTIFICATE" | sed 's/[[\.*^$()+?{|]/\\&/g')
sed -i "s|\${CERTIFICATE}|$escaped_cert|g" node-vars.sh

echo
echo -e "${GREEN}Variables saved to node-vars.sh${NC}"
echo
echo -e "${GREEN}Summary of configuration:${NC}"
echo -e "Self-steal domain: ${CYAN}$SELFSTEAL_DOMAIN${NC}"
echo -e "Panel IP: ${CYAN}$PANEL_IP${NC}"
echo -e "Cloudflare email: ${CYAN}$CLOUDFLARE_EMAIL${NC}"
echo -e "Certificate: ${CYAN}[Loaded successfully]${NC}"
echo

# Load environment variables
source node-vars.sh

echo -e "${GREEN}------------------------------------${NC}"
echo -e "${NC}✓ Environment variables configured!${NC}"
echo -e "${GREEN}------------------------------------${NC}"
echo

# Rest of the script continues...

echo -e "${GREEN}=======================${NC}"
echo -e "${NC}2. Installing packages${NC}"
echo -e "${GREEN}=======================${NC}"
echo

# Update package list and install basic packages
echo "Installing basic packages..."
apt-get update -y
apt-get install -y ca-certificates curl jq ufw wget gnupg unzip nano dialog git certbot python3-certbot-dns-cloudflare unattended-upgrades locales dnsutils coreutils grep gawk

# Install and enable cron
echo
echo "Installing and enabling cron..."
apt-get install -y cron
systemctl start cron
systemctl enable cron

# Configure locales
echo
echo "Configuring locales..."
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8

# Set timezone
echo
echo "Setting timezone to Europe/Moscow..."
timedatectl set-timezone Europe/Moscow

# Add Docker repository
echo
echo "Adding Docker repository..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | tee /etc/apt/keyrings/docker.asc > /dev/null
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
echo
echo "Installing Docker..."
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Configure TCP BBR
echo
echo "Configuring TCP BBR..."
echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
sysctl -p

# Configure UFW firewall
echo
echo "Configuring UFW firewall..."
ufw --force reset
ufw allow 22/tcp comment 'SSH'
ufw allow 443/tcp comment 'HTTPS'
ufw --force enable

# Configure unattended upgrades
echo
echo "Configuring unattended upgrades..."
echo 'Unattended-Upgrade::Mail "root";' >> /etc/apt/apt.conf.d/50unattended-upgrades
echo unattended-upgrades unattended-upgrades/enable_auto_updates boolean true | debconf-set-selections
dpkg-reconfigure -f noninteractive unattended-upgrades
systemctl restart unattended-upgrades

echo
echo -e "${GREEN}----------------------------------${NC}"
echo -e "${NC}✓ Package installation completed!${NC}"
echo -e "${GREEN}----------------------------------${NC}"
echo

echo -e "${GREEN}=======================================${NC}"
echo -e "${NC}3. Creating structure and certificates${NC}"
echo -e "${GREEN}=======================================${NC}"
echo

# Create directory structure
echo "Creating directory structure..."
mkdir -p /opt/remnawave && cd /opt/remnawave

# Create .env file
echo "Creating .env file..."
cat > .env-node <<EOL
### APP ###
APP_PORT=2222

### XRAY ###
$(echo -e "$CERTIFICATE" | sed 's/\\n$//')
EOL

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
SELFSTEAL_BASE_DOMAIN=$(echo "$SELFSTEAL_DOMAIN" | awk -F'.' '{if (NF > 2) {print $(NF-1)"."$NF} else {print $0}}')

# Generate certificate for panel domain if not exists
echo
echo "Checking certificate for panel domain..."
if [ ! -d "/etc/letsencrypt/live/$SELFSTEAL_BASE_DOMAIN" ]; then
    echo "Generating certificate for $SELFSTEAL_BASE_DOMAIN..."
    certbot certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials ~/.secrets/certbot/cloudflare.ini \
        --dns-cloudflare-propagation-seconds 10 \
        -d "$SELFSTEAL_BASE_DOMAIN" \
        -d "*.$SELFSTEAL_BASE_DOMAIN" \
        --email "$CLOUDFLARE_EMAIL" \
        --agree-tos \
        --non-interactive \
        --key-type ecdsa \
        --elliptic-curve secp384r1
else
    echo "Certificate for $SELFSTEAL_BASE_DOMAIN already exists, skipping..."
fi

# Configure renewal hooks and cron
echo
echo "Configuring certificate renewal..."
echo "renew_hook = sh -c 'cd /opt/remnawave && docker compose down remnawave-nginx && docker compose up -d remnawave-nginx'" >> /etc/letsencrypt/renewal/$SELFSTEAL_BASE_DOMAIN.conf
(crontab -u root -l 2>/dev/null; echo "0 5 1 */2 * /usr/bin/certbot renew --quiet >> /usr/local/remnawave_reverse/cron_jobs.log 2>&1") | crontab -u root -

echo
echo -e "${GREEN}----------------------------------------------${NC}"
echo -e "${NC}✓ Structure and certificates setup completed!${NC}"
echo -e "${GREEN}----------------------------------------------${NC}"
echo

echo -e "${GREEN}================================${NC}"
echo -e "${NC}4. Creating configuration files${NC}"
echo -e "${GREEN}================================${NC}"

# Create docker-compose.yml file
echo
echo "Creating docker-compose.yml file..."
cat > docker-compose.yml <<EOL
services:
  remnawave-nginx:
    image: nginx:1.26
    container_name: remnawave-nginx
    hostname: remnawave-nginx
    restart: always
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - /etc/letsencrypt/live/$SELFSTEAL_BASE_DOMAIN/fullchain.pem:/etc/nginx/ssl/$SELFSTEAL_DOMAIN/fullchain.pem:ro
      - /etc/letsencrypt/live/$SELFSTEAL_BASE_DOMAIN/privkey.pem:/etc/nginx/ssl/$SELFSTEAL_DOMAIN/privkey.pem:ro
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

# Create nginx.conf file
echo
echo "Creating nginx.conf file..."
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

echo
echo -e "${GREEN}--------------------------------------------${NC}"
echo -e "${NC}✓ Configuration files created successfully!${NC}"
echo -e "${GREEN}--------------------------------------------${NC}"
echo

echo -e "${GREEN}===========================================${NC}"
echo -e "${NC}6. Configuring UFW and starting containers${NC}"
echo -e "${GREEN}===========================================${NC}"

# Configure UFW and start containers
echo
echo "Configuring UFW and starting containers..."
ufw allow from $PANEL_IP to any port 2222 proto tcp
ufw reload
cd /opt/remnawave
docker compose up -d
sleep 3

echo
echo -e "${GREEN}----------------------------------------${NC}"
echo -e "${NC}✓ UFW installed and containers started!${NC}"
echo -e "${GREEN}----------------------------------------${NC}"
echo

echo -e "${GREEN}====================================${NC}"
echo -e "${NC}7. Setting a random masking pattern${NC}"
echo -e "${GREEN}====================================${NC}"

# Set a random masking pattern
echo
echo "Setting a random masking pattern..."
cat > install_template.sh << 'EOF'
cd /opt/
rm -f main.zip 2>/dev/null
rm -rf simple-web-templates-main/ sni-templates-main/ 2>/dev/null

template_urls=(
    "https://github.com/eGamesAPI/simple-web-templates/archive/refs/heads/main.zip"
    "https://github.com/SmallPoppa/sni-templates/archive/refs/heads/main.zip"
)

selected_url=${template_urls[$RANDOM % ${#template_urls[@]}]}

while ! wget -q --timeout=30 --tries=10 --retry-connrefused "$selected_url"; do
    sleep 3
done

unzip -o main.zip &>/dev/null
rm -f main.zip

if [[ "$selected_url" == *"eGamesAPI"* ]]; then
    cd simple-web-templates-main/
    rm -rf assets ".gitattributes" "README.md" "_config.yml" 2>/dev/null
else
    cd sni-templates-main/
    rm -rf assets "README.md" "index.html" 2>/dev/null
fi

mapfile -t templates < <(find . -maxdepth 1 -type d -not -path . | sed 's|./||')
RandomHTML="${templates[$RANDOM % ${#templates[@]}]}"

if [[ "$selected_url" == *"SmallPoppa"* && "$RandomHTML" == "503 error pages" ]]; then
    cd "$RandomHTML"
    versions=("v1" "v2")
    RandomVersion="${versions[$RANDOM % ${#versions[@]}]}"
    RandomHTML="$RandomHTML/$RandomVersion"
    cd ..
fi

if [[ -d "${RandomHTML}" ]]; then
    if [[ ! -d "/var/www/html/" ]]; then
        mkdir -p "/var/www/html/"
    fi
    rm -rf /var/www/html/*
    cp -a "${RandomHTML}"/. "/var/www/html/"
fi

cd /opt/
rm -rf simple-web-templates-main/ sni-templates-main/

# Verifying node operation
if curl -s --fail --max-time 10 "https://$SELFSTEAL_DOMAIN" | grep -q "html"; then
    echo "Node successfully launched!"
else
    echo "Node is not accessible. Check configuration."
fi
EOF

chmod +x install_template.sh
./install_template.sh

echo
echo -e "${GREEN}-------------------------------------${NC}"
echo -e "${NC}✓ Node setup completed successfully!${NC}"
echo -e "${GREEN}-------------------------------------${NC}"
echo
