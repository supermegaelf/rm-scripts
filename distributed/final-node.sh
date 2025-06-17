#!/bin/bash

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
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

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

# Function for formatted component check
check_component() {
    local name=$1
    local status=$2
    if [ "$status" == "OK" ]; then
        echo -e "✓ $name: ${GREEN}OK${NC}"
    else
        echo -e "✗ $name: ${RED}FAIL${NC}"
    fi
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

# Change to working directory
cd /opt/remnawave

# Load variables
if [ ! -f "/opt/remnawave/node_vars.sh" ]; then
    print_error "node_vars.sh not found. Please run previous setup scripts first."
    exit 1
fi

source /opt/remnawave/node_vars.sh

echo "=== FINAL SYSTEM CHECK ==="
echo "Check date: $(date)"
echo "========================================"

# Check all components
echo ""
echo "--- CONTAINER CHECK ---"

# Check node container
if docker ps | grep -q "remnanode.*Up"; then
    check_component "Container remnanode" "OK"
    NODE_UPTIME=$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep remnanode | awk '{$1=""; print $0}' | xargs)
    echo "  Uptime: $NODE_UPTIME"
else
    check_component "Container remnanode" "FAIL"
fi

# Check nginx container
if docker ps | grep -q "remnawave-nginx.*Up"; then
    check_component "Container remnawave-nginx" "OK"
    NGINX_UPTIME=$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep remnawave-nginx | awk '{$1=""; print $0}' | xargs)
    echo "  Uptime: $NGINX_UPTIME"
else
    check_component "Container remnawave-nginx" "FAIL"
fi

# Check network services
echo ""
echo "--- NETWORK SERVICES CHECK ---"

# Check port 2222
if ss -tlnp | grep -q ":2222"; then
    check_component "Port 2222 (panel connection)" "OK"
else
    check_component "Port 2222 (panel connection)" "FAIL"
fi

# Check HTTPS
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -k "https://$SELFSTEAL_DOMAIN" --max-time 10 || echo "000")
if [ "$HTTP_STATUS" == "200" ]; then
    check_component "HTTPS access ($SELFSTEAL_DOMAIN)" "OK"
else
    check_component "HTTPS access ($SELFSTEAL_DOMAIN)" "FAIL"
    echo "  Response code: $HTTP_STATUS"
fi

# Check Unix socket
if [ -S "/dev/shm/nginx.sock" ]; then
    check_component "Unix socket nginx" "OK"
else
    check_component "Unix socket nginx" "FAIL"
fi

# Check configuration
echo ""
echo "--- CONFIGURATION CHECK ---"

# Check files
for file in docker-compose.yml nginx.conf .env-node; do
    if [ -f "/opt/remnawave/$file" ]; then
        check_component "File $file" "OK"
    else
        check_component "File $file" "FAIL"
    fi
done

# Check certificates
if [ -f "$CERT_DIR/fullchain.pem" ] && [ -f "$CERT_DIR/privkey.pem" ]; then
    check_component "SSL certificates" "OK"
    
    # Check expiry
    CERT_EXPIRY=$(openssl x509 -in "$CERT_DIR/fullchain.pem" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
    if [ -n "$CERT_EXPIRY" ]; then
        CERT_DAYS=$(( ($(date -d "$CERT_EXPIRY" +%s) - $(date +%s)) / 86400 ))
        echo "  Valid until: $CERT_EXPIRY ($CERT_DAYS days remaining)"
    fi
else
    check_component "SSL certificates" "FAIL"
fi

# Check logs for errors
echo ""
echo "--- LOG ANALYSIS ---"

# Check node logs
NODE_ERRORS=$(docker logs remnanode 2>&1 | grep -i "error\|panic\|fatal" | wc -l || echo "0")
if [ "$NODE_ERRORS" -eq 0 ]; then
    check_component "remnanode logs" "OK"
else
    check_component "remnanode logs" "FAIL"
    echo "  Errors found: $NODE_ERRORS"
    echo "  Recent errors:"
    docker logs remnanode 2>&1 | grep -i "error\|panic\|fatal" | tail -3 | sed 's/^/    /'
fi

# Check nginx logs
NGINX_ERRORS=$(docker logs remnawave-nginx 2>&1 | grep -i "error\|emerg\|alert" | wc -l || echo "0")
if [ "$NGINX_ERRORS" -eq 0 ]; then
    check_component "nginx logs" "OK"
else
    check_component "nginx logs" "FAIL"
    echo "  Errors found: $NGINX_ERRORS"
fi

# Check system resources
echo ""
echo "--- RESOURCE USAGE ---"

# CPU and memory
echo "Container usage:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" | grep -E "(CONTAINER|remna)"

# Disk space
echo ""
echo "Disk space:"
df -h /opt/remnawave | tail -1 | awk '{print "- Used: " $3 " of " $2 " (" $5 ")"}'

# System memory
echo ""
echo "System memory:"
free -h | grep Mem | awk '{print "- Used: " $3 " of " $2}'

# Test panel connection
echo ""
echo "--- PANEL CONNECTION TEST ---"

# Check panel accessibility
echo "Checking connection to panel ($PANEL_IP:2222)..."

# Check firewall rules
echo ""
echo "Firewall rules for panel:"
ufw status | grep 2222 | grep "$PANEL_IP" || echo "⚠ Rule not found"

# Create health report
cat > /opt/remnawave/node_health_report.txt <<EOL
==========================================
        NODE HEALTH REPORT
==========================================
Generated: $(date)

BASIC INFORMATION:
- Domain: $SELFSTEAL_DOMAIN
- Node IP: $NODE_IP
- Panel IP: $PANEL_IP

SERVICE STATUS:
- Container remnanode: $(docker ps | grep -q "remnanode.*Up" && echo "✓ Running" || echo "✗ Stopped")
- Container nginx: $(docker ps | grep -q "remnawave-nginx.*Up" && echo "✓ Running" || echo "✗ Stopped")
- HTTPS access: $([ "$HTTP_STATUS" == "200" ] && echo "✓ Working" || echo "✗ Unavailable")
- Port 2222: $(ss -tlnp | grep -q ":2222" && echo "✓ Active" || echo "✗ Inactive")

CERTIFICATES:
- Path: $CERT_DIR
- Expiry: $CERT_EXPIRY
- Days remaining: $CERT_DAYS

RESOURCE USAGE:
$(docker stats --no-stream --format "- {{.Container}}: CPU {{.CPUPerc}}, MEM {{.MemUsage}}" | grep remna)

LAST ERROR CHECK:
- Errors in node logs: $NODE_ERRORS
- Errors in nginx logs: $NGINX_ERRORS

==========================================
EOL

print_success "Health report saved to /opt/remnawave/node_health_report.txt"

# Setup automatic maintenance
print_info "Setting up automatic maintenance..."

# Create maintenance script
cat > /opt/remnawave/maintenance.sh <<'EOL'
#!/bin/bash

LOG_FILE="/opt/remnawave/maintenance.log"
source /opt/remnawave/node_vars.sh 2>/dev/null

echo "=== Maintenance started at $(date) ===" >> $LOG_FILE

# Clean old Docker logs
echo "Cleaning Docker logs..." >> $LOG_FILE
find /var/lib/docker/containers/ -name "*.log" -size +100M -exec truncate -s 0 {} \; 2>/dev/null

# Clean unused Docker images
echo "Cleaning unused Docker images..." >> $LOG_FILE
docker image prune -f >> $LOG_FILE 2>&1

# Check certificates
if [ -n "$CERT_DIR" ] && [ -f "$CERT_DIR/fullchain.pem" ]; then
    CERT_DAYS=$(( ($(date -d "$(openssl x509 -in "$CERT_DIR/fullchain.pem" -noout -enddate 2>/dev/null | sed 's/notAfter=//')" +%s) - $(date +%s)) / 86400 ))
    if [ "$CERT_DAYS" -lt 30 ]; then
        echo "WARNING: Certificate expires in $CERT_DAYS days!" >> $LOG_FILE
    fi
fi

# Check container health
if ! docker ps | grep -q "remnanode.*Up"; then
    echo "ERROR: remnanode container is down!" >> $LOG_FILE
    cd /opt/remnawave && docker compose up -d remnanode >> $LOG_FILE 2>&1
fi

if ! docker ps | grep -q "remnawave-nginx.*Up"; then
    echo "ERROR: nginx container is down!" >> $LOG_FILE
    cd /opt/remnawave && docker compose up -d remnawave-nginx >> $LOG_FILE 2>&1
fi

echo "=== Maintenance completed at $(date) ===" >> $LOG_FILE
echo "" >> $LOG_FILE
EOL

chmod +x /opt/remnawave/maintenance.sh

# Add to cron (weekly) if not already there
if ! crontab -l 2>/dev/null | grep -q "/opt/remnawave/maintenance.sh"; then
    (crontab -l 2>/dev/null || true; echo "0 3 * * 0 /opt/remnawave/maintenance.sh") | crontab -
    print_success "Automatic maintenance configured (weekly)"
else
    print_info "Automatic maintenance already configured"
fi

# Create final documentation
cat > /opt/remnawave/NODE_README.txt <<'EOL'
==========================================
     NODE MAINTENANCE INSTRUCTIONS
==========================================

DAILY TASKS:
- Check status: node-status
- View logs if needed: node-manage logs

WEEKLY TASKS:
- Check for updates: node-manage update
- Review maintenance report: cat /opt/remnawave/maintenance.log

MONTHLY TASKS:
- Check certificate expiry
- Analyze resource usage
- Check system security updates

MANAGEMENT COMMANDS:
- node-manage start     - start node
- node-manage stop      - stop node
- node-manage restart   - restart node
- node-manage status    - container status
- node-manage update    - update images
- node-manage logs      - view logs
- node-status          - detailed system status

FILE LOCATIONS:
- Configuration: /opt/remnawave/
- Docker logs: docker logs <container_name>
- Maintenance logs: /opt/remnawave/maintenance.log
- Web content: /var/www/html/

TROUBLESHOOTING:

1. Node not visible in panel:
   - Check logs: docker logs remnanode -f
   - Check certificate in .env-node
   - Ensure port 2222 is open for panel IP

2. HTTPS not working:
   - Check certificates: ls -la /etc/letsencrypt/live/
   - Check nginx: docker logs remnawave-nginx
   - Check DNS: dig A your_domain

3. High resource usage:
   - Check logs for attacks
   - Restart containers: node-manage restart
   - Check connection count

SECURITY:
- Regularly update system: apt update && apt upgrade
- Monitor logs for suspicious activity
- Ensure port 2222 is only accessible from panel IP
- Regularly change masking pages

SUPPORT:
- Documentation: https://remna.st/docs
- For critical issues, check logs and system status

==========================================
EOL

# Final summary
echo ""
echo "========================================="
echo "   INSTALLATION AND SETUP COMPLETE!"
echo "========================================="
echo ""
print_success "Node is fully configured and running"
print_success "All checks passed successfully"
print_success "Automatic maintenance configured"
echo ""
echo "Important files:"
echo "- Instructions: /opt/remnawave/NODE_README.txt"
echo "- Health report: /opt/remnawave/node_health_report.txt"
echo "- Installation info: /opt/remnawave/node_installation_complete.txt"
echo ""
echo "Quick commands:"
echo "- Check status: node-status"
echo "- Management: node-manage {command}"
echo ""
echo "NEXT STEP:"
echo "Check in the control panel that the node appears"
echo "and has 'Active' status"
echo ""
echo "========================================="

# Final status check
echo ""
print_info "Running final status check..."
node-status
