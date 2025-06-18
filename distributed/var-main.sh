#!/bin/bash

# Remnawave environment variables setup script
# Section 1: Environment Variables

set -e

echo "========================================="
echo "Remnawave Environment Variables Setup"
echo "========================================="
echo

# Generate random values
echo "Generating random values..."
SUPERADMIN_USERNAME=$(tr -dc 'a-zA-Z' < /dev/urandom | fold -w 8 | head -n 1)

# Generate password
password=""
password+=$(head /dev/urandom | tr -dc 'A-Z' | head -c 1)
password+=$(head /dev/urandom | tr -dc 'a-z' | head -c 1)
password+=$(head /dev/urandom | tr -dc '0-9' | head -c 1)
password+=$(head /dev/urandom | tr -dc '!@#%^&*()_+' | head -c 3)
password+=$(head /dev/urandom | tr -dc 'A-Za-z0-9!@#%^&*()_+' | head -c $((24 - 6)))
SUPERADMIN_PASSWORD=$(echo "$password" | fold -w1 | shuf | tr -d '\n')

cookies_random1=$(tr -dc 'a-zA-Z' < /dev/urandom | fold -w 8 | head -n 1)
cookies_random2=$(tr -dc 'a-zA-Z' < /dev/urandom | fold -w 8 | head -n 1)
METRICS_USER=$(tr -dc 'a-zA-Z' < /dev/urandom | fold -w 8 | head -n 1)
METRICS_PASS=$(tr -dc 'a-zA-Z' < /dev/urandom | fold -w 8 | head -n 1)
JWT_AUTH_SECRET=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 64)
JWT_API_TOKENS_SECRET=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 64)

# Create temporary file with placeholders
cat > remnawave-vars-temp.sh << 'EOF'
# remnawave-vars.sh
export PANEL_DOMAIN=""
export SUB_DOMAIN=""
export SELFSTEAL_DOMAIN=""
export CLOUDFLARE_API_KEY=""
export CLOUDFLARE_EMAIL=""

# Generated variables (DO NOT REGENERATE)
EOF

# Append generated values as fixed exports
cat >> remnawave-vars-temp.sh << EOF
export SUPERADMIN_USERNAME="$SUPERADMIN_USERNAME"
export SUPERADMIN_PASSWORD="$SUPERADMIN_PASSWORD"
export cookies_random1="$cookies_random1"
export cookies_random2="$cookies_random2"
export METRICS_USER="$METRICS_USER"
export METRICS_PASS="$METRICS_PASS"
export JWT_AUTH_SECRET="$JWT_AUTH_SECRET"
export JWT_API_TOKENS_SECRET="$JWT_API_TOKENS_SECRET"
EOF

# Move temp file to final location
mv remnawave-vars-temp.sh remnawave-vars.sh

echo "File remnawave-vars.sh created with generated values."
echo
echo "Opening nano editor..."
echo
sleep 2

nano remnawave-vars.sh

echo
echo "Loading environment variables..."
source remnawave-vars.sh

# Save credentials to a separate file for reference
cat > remnawave-credentials.txt << EOF
========================================
Remnawave Credentials
========================================
Panel URL: https://${PANEL_DOMAIN}/auth/login?${cookies_random1}=${cookies_random2}

Username: $SUPERADMIN_USERNAME
Password: $SUPERADMIN_PASSWORD
========================================

IMPORTANT: Keep this file secure!
EOF

echo
echo "✓ Environment variables configured!"
echo
