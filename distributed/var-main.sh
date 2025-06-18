#!/bin/bash

# Remnawave environment variables setup script
# Section 1: Environment Variables

set -e

echo "========================================="
echo "Remnawave Environment Variables Setup"
echo "========================================="
echo

# Create variables file
cat > remnawave-vars.sh << 'EOF'
# remnawave-vars.sh
export PANEL_DOMAIN=""
export SUB_DOMAIN=""
export SELFSTEAL_DOMAIN=""
export CLOUDFLARE_API_KEY=""
export CLOUDFLARE_EMAIL=""

# Генерируемые переменные
export SUPERADMIN_USERNAME=$(tr -dc 'a-zA-Z' < /dev/urandom | fold -w 8 | head -n 1)

# Правильная генерация пароля
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
EOF

echo "File remnawave-vars.sh created."
echo
echo "Opening nano editor..."
sleep 2

nano remnawave-vars.sh

echo
echo "Loading environment variables..."
source remnawave-vars.sh

echo
echo "✓ Environment variables configured!"
echo
