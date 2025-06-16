#!/bin/bash

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
LIGHT_GREEN='\033[1;32m'
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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

cd /opt/remnawave

# Load variables
source /opt/remnawave/install_vars.sh

# Create masking page
mkdir -p /var/www/html

echo "Installing masking page..."

TEMPLATE_URL="https://github.com/eGamesAPI/simple-web-templates/archive/refs/heads/main.zip"

cd /opt/
wget -q --timeout=30 --tries=10 --retry-connrefused "$TEMPLATE_URL" -O main.zip
unzip -q -o main.zip
rm -f main.zip

cd simple-web-templates-main/
rm -rf assets ".gitattributes" "README.md" "_config.yml" 2>/dev/null

TEMPLATES=($(find . -maxdepth 1 -type d -not -path . | sed 's|./||'))
RANDOM_TEMPLATE="${TEMPLATES[$RANDOM % ${#TEMPLATES[@]}]}"

print_success "Selected template: $RANDOM_TEMPLATE"

rm -rf /var/www/html/*
cp -a "${RANDOM_TEMPLATE}"/. "/var/www/html/"

cd /opt/
rm -rf simple-web-templates-main/

print_success "Masking page installed"

# Check panel accessibility
echo -e "\n=== PANEL ACCESSIBILITY CHECK ==="

echo "Checking control panel..."
PANEL_CHECK=$(curl -s -o /dev/null -w "%{http_code}" "https://$PANEL_DOMAIN")

if [ "$PANEL_CHECK" == "404" ]; then
    print_success "Panel is protected (returns 404 without authorization)"
else
    print_warning "Unexpected response code: $PANEL_CHECK"
fi

echo "Checking access with authorization..."
AUTH_CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Cookie: ${COOKIES_RANDOM1}=${COOKIES_RANDOM2}" \
    "https://$PANEL_DOMAIN")

if [ "$AUTH_CHECK" == "200" ]; then
    print_success "Authorization works correctly"
else
    print_warning "Authorization issue, code: $AUTH_CHECK"
fi

# Create test user
echo -e "\n=== CREATING TEST USER ==="

TOKEN=$(cat /opt/remnawave/admin_token.txt)

# Get inbound UUID for test user
INBOUNDS_RESPONSE=$(curl -s -X GET "http://127.0.0.1:3000/api/inbounds" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Host: $PANEL_DOMAIN" \
    -H "X-Forwarded-For: 127.0.0.1" \
    -H "X-Forwarded-Proto: https")

INBOUND_UUID=$(echo "$INBOUNDS_RESPONSE" | jq -r '.response[0].uuid')

TEST_USER_DATA=$(cat <<EOF
{
    "username": "testuser",
    "role": "USER",
    "userLimits": {
        "maxActiveInbounds": 1,
        "lifetimeDays": 30,
        "trafficLimitBytes": 107374182400,
        "periodicTrafficResetDays": 30,
        "periodicTrafficLimitBytes": 107374182400
    },
    "inboundUuids": ["$INBOUND_UUID"]
}
EOF
)

USER_RESPONSE=$(curl -s -X POST "http://127.0.0.1:3000/api/users" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "Host: $PANEL_DOMAIN" \
    -H "X-Forwarded-For: 127.0.0.1" \
    -H "X-Forwarded-Proto: https" \
    -d "$TEST_USER_DATA")

if echo "$USER_RESPONSE" | jq -e '.response.uuid' > /dev/null; then
    USER_UUID=$(echo "$USER_RESPONSE" | jq -r '.response.uuid')
    USER_SUB_URL=$(echo "$USER_RESPONSE" | jq -r '.response.shortUuid')
    print_success "Test user created"
    echo "  - UUID: $USER_UUID"
    echo "  - Subscription URL: https://$SUB_DOMAIN/sub/$USER_SUB_URL"
else
    print_error "Failed to create user"
    echo "Response: $USER_RESPONSE"
fi

# Setup log monitoring
echo -e "\n=== SETTING UP MONITORING ==="

cat > /opt/remnawave/logs.sh <<'EOL'
#!/bin/bash

echo "=== REMNAWAVE LOGS VIEWER ==="
echo "1. All containers"
echo "2. Backend only"
echo "3. Database only"
echo "4. Nginx only"
echo "5. Redis only"
echo "6. Subscription page only"
echo "0. Exit"

read -p "Select option: " option

cd /opt/remnawave

case $option in
    1) docker compose logs -f --tail=100 ;;
    2) docker compose logs -f --tail=100 remnawave ;;
    3) docker compose logs -f --tail=100 remnawave-db ;;
    4) docker compose logs -f --tail=100 remnawave-nginx ;;
    5) docker compose logs -f --tail=100 remnawave-redis ;;
    6) docker compose logs -f --tail=100 remnawave-subscription-page ;;
    0) exit 0 ;;
    *) echo "Invalid option" ;;
esac
EOL

chmod +x /opt/remnawave/logs.sh

print_success "Monitoring script created: /opt/remnawave/logs.sh"

# Create management script
cat > /opt/remnawave/manage.sh <<'EOL'
#!/bin/bash

cd /opt/remnawave

case "$1" in
    start)
        docker compose up -d
        ;;
    stop)
        docker compose down
        ;;
    restart)
        docker compose down
        sleep 5
        docker compose up -d
        ;;
    status)
        docker compose ps
        ;;
    update)
        docker compose pull
        docker compose down
        docker compose up -d
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

chmod +x /opt/remnawave/manage.sh

ln -sf /opt/remnawave/manage.sh /usr/local/bin/remnawave-manage

print_success "Management script created"
echo "  Usage: remnawave-manage {start|stop|restart|status|update|logs}"

# Create backup script
cat > /opt/remnawave/backup.sh <<'EOL'
#!/bin/bash

BACKUP_DIR="/opt/remnawave/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/remnawave_backup_$TIMESTAMP.tar.gz"

mkdir -p "$BACKUP_DIR"

echo "Creating backup..."

cd /opt/remnawave

# Stop containers
docker compose down

# Create backup
tar -czf "$BACKUP_FILE" \
    .env \
    .env-node \
    docker-compose.yml \
    nginx.conf \
    credentials.txt \
    panel_access.txt \
    admin_token.txt \
    xray_keys.txt \
    node_info.txt \
    install_vars.sh

# Backup database
docker compose up -d remnawave-db
sleep 10
docker exec remnawave-db pg_dump -U postgres postgres > "$BACKUP_DIR/db_backup_$TIMESTAMP.sql"

# Start containers
docker compose up -d

echo "✓ Backup created: $BACKUP_FILE"
echo "✓ DB Backup: $BACKUP_DIR/db_backup_$TIMESTAMP.sql"

# Remove old backups (older than 7 days)
find "$BACKUP_DIR" -name "remnawave_backup_*.tar.gz" -mtime +7 -delete
find "$BACKUP_DIR" -name "db_backup_*.sql" -mtime +7 -delete
EOL

chmod +x /opt/remnawave/backup.sh

(crontab -l 2>/dev/null; echo "0 3 * * * /opt/remnawave/backup.sh > /opt/remnawave/backup.log 2>&1") | crontab -

print_success "Backup script created and added to cron (daily at 3:00 AM)"

# Final system check
echo -e "\n========================================="
echo "FINAL SYSTEM CHECK"
echo "========================================="

print_status() {
    if [ "$2" == "OK" ]; then
        echo -e "✓ $1: OK"
    else
        echo -e "✗ $1: FAILED"
    fi
}

echo -e "\n--- Containers ---"
docker compose ps --format "table {{.Service}}\t{{.Status}}"

echo -e "\n--- Network Ports ---"
ss -tlnp | grep -E ":(3000|3010|6767|443|80)" | awk '{print $4}' | while read port; do
    echo "✓ Port active: $port"
done

echo -e "\n--- Service Availability ---"
curl -s -f "http://127.0.0.1:3000/api/health" > /dev/null && print_status "Backend API" "OK" || print_status "Backend API" "FAIL"
nc -z 127.0.0.1 3010 && print_status "Subscription Page" "OK" || print_status "Subscription Page" "FAIL"
curl -s -f -k "https://$PANEL_DOMAIN" > /dev/null && print_status "Panel HTTPS" "OK" || print_status "Panel HTTPS" "FAIL"
curl -s -f -k "https://$SUB_DOMAIN" > /dev/null && print_status "Subscription HTTPS" "OK" || print_status "Subscription HTTPS" "FAIL"

echo -e "\n--- Disk Space ---"
df -h /opt/remnawave | tail -1 | awk '{print "Used: " $3 " of " $2 " (" $5 ")"}'

echo -e "\n--- Memory ---"
free -h | grep Mem | awk '{print "Used: " $3 " of " $2}'

# Final information
echo -e "\n========================================="
echo "INSTALLATION COMPLETED!"
echo "========================================="

cat <<EOL

PANEL ACCESS:
- URL: https://$PANEL_DOMAIN/auth/login?${COOKIES_RANDOM1}=${COOKIES_RANDOM2}
- Login: $SUPERADMIN_USERNAME
- Password: see file /opt/remnawave/credentials.txt

SUBSCRIPTION PAGE:
- URL: https://$SUB_DOMAIN

MANAGEMENT:
- Start/Stop: remnawave-manage {start|stop|restart}
- Logs: remnawave-manage logs
- Update: remnawave-manage update
- Backup: /opt/remnawave/backup.sh

IMPORTANT FILES:
- Configuration: /opt/remnawave/
- Logs: docker compose logs -f
- Backup: /opt/remnawave/backups/

NEXT STEPS:
1. Login to panel using the provided link
2. Create users
3. Configure additional nodes if needed
4. Enable Telegram notifications (optional)

DOCUMENTATION:
https://remna.st/docs

========================================
EOL

cp /opt/remnawave/panel_access.txt /opt/remnawave/FINAL_INFO.txt
echo -e "\n\nInstallation completed: $(date)" >> /opt/remnawave/FINAL_INFO.txt

# Cleanup and security
chmod 600 /opt/remnawave/.env
chmod 600 /opt/remnawave/credentials.txt
chmod 600 /opt/remnawave/admin_token.txt
chmod 600 /opt/remnawave/xray_keys.txt
chmod 600 /opt/remnawave/node_info.txt

cat > /opt/remnawave/.gitignore <<EOL
.env
.env-node
credentials.txt
admin_token.txt
*.log
backups/
xray_keys.txt
node_info.txt
install_vars.sh
EOL

print_success "Installation completely finished!"
