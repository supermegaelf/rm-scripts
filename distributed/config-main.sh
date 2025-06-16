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
print_input "Panel Domain (e.g., example.com): "
read PANEL_DOMAIN
if [[ -z "$PANEL_DOMAIN" ]]; then
    print_error "Panel Domain cannot be empty"
    exit 1
fi

print_input "Sub Domain (e.g., sub.example.com): "
read SUB_DOMAIN
if [[ -z "$SUB_DOMAIN" ]]; then
    print_error "Sub Domain cannot be empty"
    exit 1
fi

cd /opt/remnawave

# Generate random credentials
SUPERADMIN_USERNAME=$(tr -dc 'a-zA-Z' < /dev/urandom | fold -w 8 | head -n 1)
SUPERADMIN_PASSWORD=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9!@#%^&*()_+' | fold -w 24 | head -n 1)
COOKIES_RANDOM1=$(tr -dc 'a-zA-Z' < /dev/urandom | fold -w 8 | head -n 1)
COOKIES_RANDOM2=$(tr -dc 'a-zA-Z' < /dev/urandom | fold -w 8 | head -n 1)
METRICS_USER=$(tr -dc 'a-zA-Z' < /dev/urandom | fold -w 8 | head -n 1)
METRICS_PASS=$(tr -dc 'a-zA-Z' < /dev/urandom | fold -w 8 | head -n 1)
JWT_AUTH_SECRET=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 64)
JWT_API_TOKENS_SECRET=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 64)

# Create credentials file
echo "=== ВАЖНО: СОХРАНИТЕ ЭТИ ДАННЫЕ ===" > credentials.txt
echo "Panel URL: https://$PANEL_DOMAIN/auth/login?${COOKIES_RANDOM1}=${COOKIES_RANDOM2}" >> credentials.txt
echo "Username: $SUPERADMIN_USERNAME" >> credentials.txt
echo "Password: $SUPERADMIN_PASSWORD" >> credentials.txt
echo "===================================" >> credentials.txt

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

print_success ".env file created successfully"

# Define certificate domain (use panel domain as base)
CERT_DOMAIN="$PANEL_DOMAIN"

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
      - /etc/letsencrypt/live/$CERT_DOMAIN/fullchain.pem:/etc/nginx/ssl/$PANEL_DOMAIN/fullchain.pem:ro
      - /etc/letsencrypt/live/$CERT_DOMAIN/privkey.pem:/etc/nginx/ssl/$PANEL_DOMAIN/privkey.pem:ro
      - /etc/letsencrypt/live/$CERT_DOMAIN/fullchain.pem:/etc/nginx/ssl/$SUB_DOMAIN/fullchain.pem:ro
      - /etc/letsencrypt/live/$CERT_DOMAIN/privkey.pem:/etc/nginx/ssl/$SUB_DOMAIN/privkey.pem:ro
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

print_success "docker-compose.yml file created successfully"

# Validate docker-compose.yml
if docker compose config --quiet; then
    print_success "docker-compose.yml is valid"
else
    print_error "Error in docker-compose.yml"
    exit 1
fi

# Export variables for next steps
export PANEL_DOMAIN
export SUB_DOMAIN
export COOKIES_RANDOM1
export COOKIES_RANDOM2
export SUPERADMIN_USERNAME
export SUPERADMIN_PASSWORD

# Save variables to file
cat > /opt/remnawave/install_vars.sh <<EOL
export PANEL_DOMAIN="$PANEL_DOMAIN"
export SUB_DOMAIN="$SUB_DOMAIN"
export COOKIES_RANDOM1="$COOKIES_RANDOM1"
export COOKIES_RANDOM2="$COOKIES_RANDOM2"
export SUPERADMIN_USERNAME="$SUPERADMIN_USERNAME"
export SUPERADMIN_PASSWORD="$SUPERADMIN_PASSWORD"
EOL

chmod 600 /opt/remnawave/install_vars.sh

print_success "Installation variables saved to install_vars.sh"

# Display credentials prominently
echo -e "\n========================================="
echo "IMPORTANT: SAVE THESE CREDENTIALS"
echo "========================================="
cat credentials.txt
echo "========================================="
print_success "Credentials generated and saved to credentials.txt"

# Check created files
ls -la /opt/remnawave/

print_success "Configuration files setup completed successfully!"
