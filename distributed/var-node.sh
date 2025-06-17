#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Node Variables Setup ===${NC}"
echo -e "${YELLOW}Enter required parameters for node configuration:${NC}"
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

# Function to request multiline input for certificate
ask_certificate() {
    echo -e "${GREEN}Enter the CERTIFICATE (SSL_CERT=\"your_public_key_here\"):${NC}"
    echo -e "${YELLOW}Paste the complete certificate including SSL_CERT= part${NC}"
    echo -e "${YELLOW}Press Ctrl+D when finished${NC}"
    echo
    
    CERTIFICATE=$(cat)
    
    if [ -z "$CERTIFICATE" ]; then
        echo -e "${RED}Certificate cannot be empty!${NC}"
        ask_certificate
    fi
}

# Request parameters
ask_input "SELFSTEAL_DOMAIN (e.g: selfsteal.example.com)" SELFSTEAL_DOMAIN
ask_input "PANEL_IP (e.g: 192.168.1.100)" PANEL_IP
ask_input "CLOUDFLARE_API_KEY" CLOUDFLARE_API_KEY
ask_input "CLOUDFLARE_EMAIL" CLOUDFLARE_EMAIL

echo
ask_certificate

echo
echo -e "${YELLOW}Generating node variables file...${NC}"

# Create variables file
cat > node-vars.sh << EOF
# node-vars.sh
export SELFSTEAL_DOMAIN="$SELFSTEAL_DOMAIN"
export PANEL_IP="$PANEL_IP"
export CLOUDFLARE_API_KEY="$CLOUDFLARE_API_KEY"
export CLOUDFLARE_EMAIL="$CLOUDFLARE_EMAIL"
# Certificate from panel (complete, including SSL_CERT=)
export CERTIFICATE='$CERTIFICATE'
EOF

# Make file executable
chmod +x node-vars.sh

echo -e "${GREEN}✓ File node-vars.sh created successfully!${NC}"
echo
echo -e "${YELLOW}Loading environment variables...${NC}"

# Load environment variables
source node-vars.sh

echo -e "${GREEN}✓ Environment variables loaded!${NC}"
