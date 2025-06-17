#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Remnawave Setup ===${NC}"
echo -e "${YELLOW}Enter required parameters:${NC}"
echo

# Function to request input with validation
ask_input() {
    local prompt="$1"
    local var_name="$2"
    local value=""
    
    while [ -z "$value" ]; do
        echo -e -n "${GREEN}$prompt: ${NC}"
        read -r value
        if [ -z "$value" ]; then
            echo -e "${RED}Value cannot be empty!${NC}"
        fi
    done
    
    eval "$var_name='$value'"
}

# Request parameters
ask_input "PANEL_DOMAIN (e.g: example.com)" PANEL_DOMAIN
ask_input "SUB_DOMAIN (e.g: example.com)" SUB_DOMAIN  
ask_input "SELFSTEAL_DOMAIN (e.g: example.com)" SELFSTEAL_DOMAIN
ask_input "CLOUDFLARE_API_KEY" CLOUDFLARE_API_KEY
ask_input "CLOUDFLARE_EMAIL" CLOUDFLARE_EMAIL

echo
echo -e "${YELLOW}Generating environment variables file...${NC}"

# Create variables file
cat > remnawave-vars.sh << EOF
# remnawave-vars.sh
export PANEL_DOMAIN="$PANEL_DOMAIN"
export SUB_DOMAIN="$SUB_DOMAIN"
export SELFSTEAL_DOMAIN="$SELFSTEAL_DOMAIN"
export CLOUDFLARE_API_KEY="$CLOUDFLARE_API_KEY"
export CLOUDFLARE_EMAIL="$CLOUDFLARE_EMAIL"

# Generated variables
export SUPERADMIN_USERNAME=\$(tr -dc 'a-zA-Z' < /dev/urandom | fold -w 8 | head -n 1)

# Proper password generation
password=""
password+=\$(head /dev/urandom | tr -dc 'A-Z' | head -c 1)
password+=\$(head /dev/urandom | tr -dc 'a-z' | head -c 1)
password+=\$(head /dev/urandom | tr -dc '0-9' | head -c 1)
password+=\$(head /dev/urandom | tr -dc '!@#%^&*()_+' | head -c 3)
password+=\$(head /dev/urandom | tr -dc 'A-Za-z0-9!@#%^&*()_+' | head -c \$((24 - 6)))
export SUPERADMIN_PASSWORD=\$(echo "\$password" | fold -w1 | shuf | tr -d '\n')

export cookies_random1=\$(tr -dc 'a-zA-Z' < /dev/urandom | fold -w 8 | head -n 1)
export cookies_random2=\$(tr -dc 'a-zA-Z' < /dev/urandom | fold -w 8 | head -n 1)
export METRICS_USER=\$(tr -dc 'a-zA-Z' < /dev/urandom | fold -w 8 | head -n 1)
export METRICS_PASS=\$(tr -dc 'a-zA-Z' < /dev/urandom | fold -w 8 | head -n 1)
export JWT_AUTH_SECRET=\$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 64)
export JWT_API_TOKENS_SECRET=\$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 64)
EOF

# Make file executable
chmod +x remnawave-vars.sh

echo -e "${GREEN}✓ File remnawave-vars.sh created successfully!${NC}"
echo
echo -e "${YELLOW}Loading environment variables...${NC}"

# Load environment variables
source remnawave-vars.sh

echo -e "${GREEN}✓ Environment variables loaded!${NC}"
