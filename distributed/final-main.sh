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

# Check if install_vars.sh exists
if [[ ! -f "/opt/remnawave/install_vars.sh" ]]; then
    print_error "install_vars.sh not found. Please run previous setup scripts first."
    exit 1
fi

# Load variables
source /opt/remnawave/install_vars.sh

# Create masking page
print_warning "Installing masking page..."
mkdir -p /var/www/html

TEMPLATE_URL="https://github.com/eGamesAPI/simple-web-templates/archive/refs/heads/main.zip"

cd /opt/
if wget -q --timeout=30 --tries=10 --retry-connrefused "$TEMPLATE_URL" -O main.zip; then
    unzip -q -o main.zip
    rm -f main.zip

    cd simple-web-templates-main/
    rm -rf assets ".gitattributes" "README.md" "_config.yml" 2>/dev/null

    TEMPLATES=($(find . -maxdepth 1 -type d -not -path . | sed 's|./||'))
    if [ ${#TEMPLATES[@]} -gt 0 ]; then
        RANDOM_TEMPLATE="${TEMPLATES[$RANDOM % ${#TEMPLATES[@]}]}"
        print_success "Selected template: $RANDOM_TEMPLATE"

        rm -rf /var/www/html/*
        cp -a "${RANDOM_TEMPLATE}"/. "/var/www/html/"
        
        cd /opt/
        rm -rf simple-web-templates-main/
        print_success "Masking page installed"
    else
        print_warning "No templates found in archive"
    fi
else
    print_warning "Failed to download masking page templates"
fi

# Check panel accessibility
echo -e "\n=== PANEL ACCESSIBILITY CHECK ==="

echo "Checking control panel..."
PANEL_CHECK=$(curl -s -o /dev/null -w "%{http_code}" -k "https://$PANEL_DOMAIN" 2>/dev/null || echo "000")

if [ "$PANEL_CHECK" == "404" ]; then
    print_success "Panel is protected (returns 404 without authorization)"
elif [ "$PANEL_CHECK" == "000" ]; then
    print_error "Panel is not accessible"
else
    print_warning "Unexpected response code: $PANEL_CHECK"
fi

echo "Checking access with authorization..."
AUTH_CHECK=$(curl -s -o /dev/null -w "%{http_code}" -k \
    -H "Cookie: ${COOKIES_RANDOM1}=${COOKIES_RANDOM2}" \
    "https://$PANEL_DOMAIN" 2>/dev/null || echo "000")

if [ "$AUTH_CHECK" == "200" ]; then
    print_success "Authorization works correctly"
elif [ "$AUTH_CHECK" == "000" ]; then
    print_error "Panel is not accessible with authorization"
else
    print_warning "Authorization issue, code: $AUTH_CHECK"
fi

# Create test user
echo -e "\n=== CREATING TEST USER ==="

if [ -f "/opt/remnawave/admin_token.txt" ]; then
    TOKEN=$(cat /opt/remnawave/admin_token.txt)
    
    # Get inbound UUID for test user
    INBOUNDS_RESPONSE=$(curl -s -X GET "http://127.0.0.1:3000/api/inbounds" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Host: $PANEL_DOMAIN" \
        -H "X-Forwarded-For: 127.0.0.1" \
        -H "X-Forwarded-Proto: https" \
        -H "X-Real-IP: 127.0.0.1" \
        -H "X-Forwarded-Host: $PANEL_DOMAIN" \
        -H "X-Forwarded-Port: 443")

    INBOUND_UUID=$(echo "$INBOUNDS_RESPONSE" | jq -r '.response[0].uuid // empty' 2>/dev/null)

    if [ -n "$INBOUND_UUID" ] && [ "$INBOUND_UUID" != "null" ]; then
        # Calculate expiration date (30 days from now)
        EXPIRE_AT=$(date -d "+30 days" --utc +"%Y-%m-%dT%H:%M:%S.000Z")

        TEST_USER_DATA=$(cat <<EOF
{
    "username": "testuser",
    "role": "USER",
    "expireAt": "$EXPIRE_AT",
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
            -H "X-Real-IP: 127.0.0.1" \
            -H "X-Forwarded-Host: $PANEL_DOMAIN" \
            -H "X-Forwarded-Port: 443" \
            -d "$TEST_USER_DATA")

        if echo "$USER_RESPONSE" | jq -e '.response.uuid' > /dev/null 2>&1; then
            USER_UUID=$(echo "$USER_RESPONSE" | jq -r '.response.uuid')
            USER_SUB_URL=$(echo "$USER_RESPONSE" | jq -r '.response.shortUuid')
            print_success "Test user created"
            echo "  - UUID: $USER_UUID"
            echo "  - Subscription URL: https://$SUB_DOMAIN/sub/$USER_SUB_URL"
        else
            print_warning "Failed to create test user (may already exist)"
        fi
    else
        print_warning "No inbounds found, skipping test user creation"
    fi
else
    print_warning "Admin token not found, skipping test user creation"
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
        docker image prune -f
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

# Create symlink if it doesn't exist
if [ ! -f /usr/local/bin/remnawave-manage ]; then
    ln -sf /opt/remnawave/manage.sh /usr/local/bin/remnawave-manage
fi

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

# Create list of files to backup
BACKUP_FILES=".env docker-compose.yml nginx.conf"

# Add optional files if they exist
for file in credentials.txt panel_access.txt admin_token.txt install_vars.sh deployment_info.txt .env-node; do
    if [ -f "$file" ]; then
        BACKUP_FILES="$BACKUP_FILES $file"
    fi
done

# Stop containers
docker compose down

# Create backup
tar -czf "$BACKUP_FILE" $BACKUP_FILES

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

# Add to cron if not already there
if ! crontab -l 2>/dev/null | grep -q "/opt/remnawave/backup.sh"; then
    (crontab -l 2>/dev/null; echo "0 3 * * * /opt/remnawave/backup.sh > /opt/remnawave/backup.log 2>&1") | crontab -
    print_success "Backup script created and added to cron (daily at 3:00 AM)"
else
    print_success "Backup script created (cron job already exists)"
fi

# Final system check
echo -e "\n========================================="
echo "FINAL SYSTEM CHECK"
echo "========================================="

echo -e "\n--- Containers ---"
cd /opt/remnawave
docker compose ps --format "table {{.Service}}\t{{.Status}}"

echo -e "\n--- Network Ports ---"
ss -tlnp | grep -E ":(3000|3010|6767|443|80)" | awk '{print $4}' | while read port; do
    echo "✓ Port active: $port"
done

echo -e "\n--- Service Availability ---"
# Check backend API
if curl -s -f "http://127.0.0.1:3000/" > /dev/null 2>&1; then
    echo "✓ Backend API: OK"
else
    echo "✗ Backend API: FAIL"
fi

# Check subscription page
if nc -z 127.0.0.1 3010 2>/dev/null; then
    echo "✓ Subscription Page: OK"
else
    echo "✗ Subscription Page: FAIL"
fi

# Check HTTPS
if curl -s -f -k "https://$PANEL_DOMAIN" > /dev/null 2>&1; then
    echo "✓ Panel HTTPS: OK"
else
    echo "✗ Panel HTTPS: FAIL"
fi

if curl -s -f -k "https://$SUB_DOMAIN" > /dev/null 2>&1; then
    echo "✓ Subscription HTTPS: OK"
else
    echo "✗ Subscription HTTPS: FAIL"
fi

echo -e "\n--- Disk Space ---"
df -h /opt/remnawave | tail -1 | awk '{print "Used: " $3 " of " $2 " (" $5 ")"}'

echo -e "\n--- Memory ---"
free -h | grep Mem | awk '{print "Used: " $3 " of " $2}'

# Get password from credentials file
ADMIN_PASSWORD=$(grep "Password:" /opt/remnawave/credentials.txt 2>/dev/null | awk '{print $2}' || echo "Check credentials.txt")

# Final information
echo -e "\n========================================="
echo "INSTALLATION COMPLETED!"
echo "========================================="

cat <<EOL

PANEL ACCESS:
- URL: https://$PANEL_DOMAIN/auth/login?${COOKIES_RANDOM1}=${COOKIES_RANDOM2}
- Login: $SUPERADMIN_USERNAME
- Password: $ADMIN_PASSWORD

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

# Create FINAL_INFO.txt with installation summary
cat > /opt/remnawave/FINAL_INFO.txt <<EOL
========================================
REMNAWAVE INSTALLATION SUMMARY
========================================
Installation completed: $(date)

PANEL ACCESS:
- URL: https://$PANEL_DOMAIN/auth/login?${COOKIES_RANDOM1}=${COOKIES_RANDOM2}
- Login: $SUPERADMIN_USERNAME
- Password: $ADMIN_PASSWORD

SUBSCRIPTION PAGE:
- URL: https://$SUB_DOMAIN

MANAGEMENT:
- Start/Stop: remnawave-manage {start|stop|restart}
- Logs: remnawave-manage logs
- Update: remnawave-manage update
- Backup: /opt/remnawave/backup.sh

IMPORTANT FILES:
- Configuration: /opt/remnawave/
- Credentials: /opt/remnawave/credentials.txt
- Logs: docker compose logs -f
- Backup: /opt/remnawave/backups/
========================================
EOL

# Cleanup and security
chmod 600 /opt/remnawave/.env 2>/dev/null || true
chmod 600 /opt/remnawave/credentials.txt 2>/dev/null || true
chmod 600 /opt/remnawave/admin_token.txt 2>/dev/null || true
chmod 600 /opt/remnawave/.env-node 2>/dev/null || true
chmod 600 /opt/remnawave/FINAL_INFO.txt

# Create .gitignore
cat > /opt/remnawave/.gitignore <<EOL
.env
.env-node
credentials.txt
admin_token.txt
*.log
backups/
install_vars.sh
deployment_info.txt
panel_access.txt
FINAL_INFO.txt
EOL

print_success "Installation completely finished!"
print_warning "Check FINAL_INFO.txt for all access details"
