#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Remnawave Config Generator ===${NC}"
echo -e "${YELLOW}Generating configuration files...${NC}"
echo

# Function to load variables from remnawave-vars.sh
load_variables() {
    echo -e "${YELLOW}Loading environment variables...${NC}"
    
    if [ -f "remnawave-vars.sh" ]; then
        source remnawave-vars.sh
        echo -e "${GREEN}✓ Variables loaded from remnawave-vars.sh${NC}"
    else
        echo -e "${RED}remnawave-vars.sh not found!${NC}"
        echo -e "${YELLOW}Please run the setup script first to generate variables${NC}"
        exit 1
    fi
}

# Function to check if variables are set
check_variables() {
    echo -e "${YELLOW}Checking required variables...${NC}"
    
    local missing_vars=()
    
    # Check main variables
    [[ -z "$PANEL_DOMAIN" ]] && missing_vars+=("PANEL_DOMAIN")
    [[ -z "$SUB_DOMAIN" ]] && missing_vars+=("SUB_DOMAIN")
    [[ -z "$JWT_AUTH_SECRET" ]] && missing_vars+=("JWT_AUTH_SECRET")
    [[ -z "$JWT_API_TOKENS_SECRET" ]] && missing_vars+=("JWT_API_TOKENS_SECRET")
    [[ -z "$SUPERADMIN_USERNAME" ]] && missing_vars+=("SUPERADMIN_USERNAME")
    [[ -z "$SUPERADMIN_PASSWORD" ]] && missing_vars+=("SUPERADMIN_PASSWORD")
    [[ -z "$METRICS_USER" ]] && missing_vars+=("METRICS_USER")
    [[ -z "$METRICS_PASS" ]] && missing_vars+=("METRICS_PASS")
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        echo -e "${RED}Missing variables: ${missing_vars[*]}${NC}"
        echo -e "${RED}Please run remnawave-vars.sh first to generate variables!${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ All required variables found${NC}"
}

# Function to get base domain
get_base_domain() {
    local domain="$1"
    echo "$domain" | sed 's/^[^.]*\.//'
}

# Function to create directory
create_directory() {
    echo -e "${YELLOW}Creating /opt/remnawave directory...${NC}"
    mkdir -p /opt/remnawave
    echo -e "${GREEN}✓ Directory created${NC}"
}

# Function to create .env file
create_env_file() {
    echo -e "${YELLOW}Creating .env file...${NC}"
    
    local panel_base_domain=$(get_base_domain "$PANEL_DOMAIN")
    local sub_base_domain=$(get_base_domain "$SUB_DOMAIN")
    
    cat > /opt/remnawave/.env <<EOL
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

    echo -e "${GREEN}✓ .env file created in /opt/remnawave/${NC}"
}

# Function to create docker-compose.yml file
create_docker_compose() {
    echo -e "${YELLOW}Creating docker-compose.yml file...${NC}"
    
    local panel_base_domain=$(get_base_domain "$PANEL_DOMAIN")
    local sub_base_domain=$(get_base_domain "$SUB_DOMAIN")
    
    cat > /opt/remnawave/docker-compose.yml <<EOL
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
      - /etc/letsencrypt/live/$panel_base_domain/fullchain.pem:/etc/nginx/ssl/$PANEL_DOMAIN/fullchain.pem:ro
      - /etc/letsencrypt/live/$panel_base_domain/privkey.pem:/etc/nginx/ssl/$PANEL_DOMAIN/privkey.pem:ro
      - /etc/letsencrypt/live/$sub_base_domain/fullchain.pem:/etc/nginx/ssl/$SUB_DOMAIN/fullchain.pem:ro
      - /etc/letsencrypt/live/$sub_base_domain/privkey.pem:/etc/nginx/ssl/$SUB_DOMAIN/privkey.pem:ro
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

    echo -e "${GREEN}✓ docker-compose.yml file created in /opt/remnawave/${NC}"
}

# Function to download index.html
download_index_html() {
    echo -e "${YELLOW}Downloading index.html...${NC}"
    
    # Download index.html
    if wget -P /opt/remnawave/ https://raw.githubusercontent.com/supermegaelf/rm-pages/main/index.html >/dev/null 2>&1; then
        echo -e "${GREEN}✓ index.html downloaded to /opt/remnawave/${NC}"
    else
        echo -e "${RED}Failed to download index.html${NC}"
        echo -e "${YELLOW}You may need to download it manually from:${NC}"
        echo -e "${BLUE}https://raw.githubusercontent.com/supermegaelf/rm-pages/main/index.html${NC}"
    fi
}

# Main execution
load_variables
echo
check_variables
echo
create_directory
echo
create_env_file
echo
create_docker_compose
echo
download_index_html
echo
echo -e "${GREEN}=== All configuration files created successfully! ===${NC}"
