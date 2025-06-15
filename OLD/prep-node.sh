#!/bin/bash

read -p "Cloudflare email: " dns_cloudflare_email
read -p "Cloudflare API key: " dns_cloudflare_api_key
read -p "NODE_DOMAIN: " NODE_DOMAIN
read -p "Certbot email: " certbot_email

sudo apt update && sudo apt upgrade -y

sudo apt install python3-certbot-dns-cloudflare -y

sudo mkdir -p /root/.secrets/certbot/

cat <<EOL | sudo tee /root/.secrets/certbot/cloudflare.ini
dns_cloudflare_email = $dns_cloudflare_email
dns_cloudflare_api_key = $dns_cloudflare_api_key
EOL

sudo chmod 700 /root/.secrets/certbot/
sudo chmod 400 /root/.secrets/certbot/cloudflare.ini

sudo certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /root/.secrets/certbot/cloudflare.ini \
  -d "*.${NODE_DOMAIN}" -d "${NODE_DOMAIN}" \
  --non-interactive \
  --agree-tos \
  --email "${certbot_email}" \
  --no-eff-email

echo "0 3 * * * root /usr/bin/certbot renew --quiet --dns-cloudflare --dns-cloudflare-credentials /root/.secrets/certbot/cloudflare.ini -d '*.${NODE_DOMAIN},${NODE_DOMAIN}' --post-hook 'systemctl reload nginx'" | sudo tee -a /etc/crontab
