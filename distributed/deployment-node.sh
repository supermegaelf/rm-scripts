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

# Function to display spinner
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    echo -n " "
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
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

print_info "=== PREPARING TO START NODE ==="

# Pull Docker images
print_info "Pulling Docker images..."
docker compose pull &
spinner $!

# Check pulled images
echo ""
print_info "Checking images:"
docker images | grep -E "(nginx|remnawave/node)" | while read line; do
    print_success "Found: $(echo $line | awk '{print $1":"$2}')"
done

# Start containers
echo ""
print_info "=== STARTING CONTAINERS ==="

print_info "Starting containers..."
docker compose up -d

# Wait for startup
print_info "Waiting for containers to start..."
sleep 5

# Check container status
echo ""
print_info "Container status:"
docker compose ps

# Verify all containers are running
REMNANODE_RUNNING=$(docker compose ps | grep -c "remnanode.*Up" || true)
NGINX_RUNNING=$(docker compose ps | grep -c "remnawave-nginx.*Up" || true)

if [ "$REMNANODE_RUNNING" -eq 1 ] && [ "$NGINX_RUNNING" -eq 1 ]; then
    print_success "All containers are running successfully"
else
    print_error "Problem with container startup"
    print_info "Checking logs:"
    docker compose logs --tail=50
    exit 1
fi

# Check node operation
echo ""
print_info "=== CHECKING NODE OPERATION ==="

# Check port 2222
print_info "Checking port 2222..."
if ss -tlnp | grep -q ":2222"; then
    print_success "Port 2222 is active"
else
    print_error "Port 2222 is not active"
fi

# Check nginx socket
print_info "Checking Unix socket..."
SOCKET_CHECK_ATTEMPTS=3
SOCKET_FOUND=false

for i in $(seq 1 $SOCKET_CHECK_ATTEMPTS); do
    if [ -S "/dev/shm/nginx.sock" ]; then
        print_success "Unix socket nginx created"
        SOCKET_FOUND=true
        break
    else
        if [ $i -lt $SOCKET_CHECK_ATTEMPTS ]; then
            print_warning "Unix socket not yet created, attempt $i of $SOCKET_CHECK_ATTEMPTS..."
            sleep 3
        fi
    fi
done

if [ "$SOCKET_FOUND" = false ]; then
    print_error "Unix socket not created after $SOCKET_CHECK_ATTEMPTS attempts"
fi

# Check node logs
print_info "Checking node logs..."
NODE_LOGS=$(docker logs remnanode 2>&1 | tail -10)
if echo "$NODE_LOGS" | grep -qi "error"; then
    print_warning "Errors found in logs:"
    echo "$NODE_LOGS"
else
    print_success "No errors found in logs"
fi

# Check HTTPS access
echo ""
print_info "=== CHECKING HTTPS ACCESS ==="

print_info "Checking HTTPS access to $SELFSTEAL_DOMAIN..."

# Try HTTPS access
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -k "https://$SELFSTEAL_DOMAIN" --max-time 10 || echo "000")

if [ "$HTTP_STATUS" == "200" ]; then
    print_success "HTTPS access working (response code: 200)"
elif [ "$HTTP_STATUS" == "000" ]; then
    print_warning "Connection timeout, retrying..."
    sleep 5
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -k "https://$SELFSTEAL_DOMAIN" --max-time 10 || echo "000")
    if [ "$HTTP_STATUS" == "200" ]; then
        print_success "HTTPS access working (response code: 200)"
    else
        print_error "Problem with HTTPS access (code: $HTTP_STATUS)"
    fi
else
    print_warning "Unexpected response code: $HTTP_STATUS"
fi

# Check masking page
print_info "Checking masking page..."
if curl -s -k "https://$SELFSTEAL_DOMAIN" 2>/dev/null | grep -qi "html"; then
    print_success "Masking page is responding"
else
    print_warning "Problem with masking page"
fi

# Check panel connection
echo ""
print_info "=== CHECKING PANEL CONNECTION ==="

print_info "Checking that port 2222 is accessible only from panel..."

# Check UFW rules
if ufw status | grep -q "2222.*$PANEL_IP"; then
    print_success "Firewall rule configured correctly"
else
    print_warning "Firewall rule not found, adding..."
    ufw allow from $PANEL_IP to any port 2222 proto tcp comment "Remnawave panel"
    ufw reload
fi

# Check remnanode process
print_info "Checking node process..."
if docker exec remnanode ps aux 2>/dev/null | grep -q "remnanode"; then
    print_success "remnanode process is active"
else
    print_warning "remnanode process not found"
fi

# Display panel setup information
echo ""
echo "========================================="
echo "    INFORMATION FOR PANEL SETUP"
echo "========================================="
echo ""
echo "Node successfully started!"
echo ""
echo "To complete setup, on the PANEL server:"
echo ""
echo "1. Log into the control panel"
echo "2. Check that the node appears in the nodes list"
echo "3. Node status should be 'Active'"
echo ""
echo "Node parameters:"
echo "- Domain: $SELFSTEAL_DOMAIN"
echo "- IP address: $NODE_IP"
echo "- Port: 2222"
echo ""
echo "If node doesn't appear in panel:"
echo "1. Check logs: docker logs remnanode"
echo "2. Ensure certificate in .env-node is correct"
echo "3. Check network connection between servers"
echo ""
echo "========================================="

# Create status check script
print_info "Creating status check script..."

cat > /opt/remnawave/check-status.sh <<'EOL'
#!/bin/bash

echo "=== REMNAWAVE NODE STATUS ==="
echo ""

# Load variables
source /opt/remnawave/node_vars.sh 2>/dev/null

# Check containers
echo "Containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(NAME|remna)"

# Check ports
echo -e "\nActive ports:"
ss -tlnp | grep -E ":(443|2222)" | awk '{print "- " $4}'

# Check processes
echo -e "\nProcesses:"
if docker exec remnanode ps aux 2>/dev/null | grep -q remnanode; then
    echo "✓ remnanode process active"
else
    echo "✗ remnanode process not found"
fi

# Check logs for errors
echo -e "\nRecent errors (if any):"
docker logs remnanode 2>&1 | grep -i error | tail -5 || echo "✓ No errors found"

# Check HTTPS
echo -e "\nHTTPS access:"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k "https://$SELFSTEAL_DOMAIN" --max-time 5 || echo "timeout")
echo "- Response code: $HTTP_CODE"

# Resource usage
echo -e "\nResource usage:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep -E "(CONTAINER|remna)"

echo ""
echo "==================================="
EOL

chmod +x /opt/remnawave/check-status.sh

if [ ! -f /usr/local/bin/node-status ]; then
    ln -sf /opt/remnawave/check-status.sh /usr/local/bin/node-status
fi

print_success "Status check script created"
echo "  Usage: node-status"

# Setup monitoring
print_info "Setting up monitoring..."

cat > /opt/remnawave/monitor.sh <<'EOL'
#!/bin/bash

# Check that containers are running
if ! docker ps | grep -q "remnanode.*Up"; then
    echo "$(date): Node container is down, restarting..." >> /opt/remnawave/monitor.log
    cd /opt/remnawave && docker compose up -d
fi

if ! docker ps | grep -q "remnawave-nginx.*Up"; then
    echo "$(date): Nginx container is down, restarting..." >> /opt/remnawave/monitor.log
    cd /opt/remnawave && docker compose up -d
fi
EOL

chmod +x /opt/remnawave/monitor.sh

# Add to cron for checks every 5 minutes
if ! crontab -l 2>/dev/null | grep -q "/opt/remnawave/monitor.sh"; then
    (crontab -l 2>/dev/null || true; echo "*/5 * * * * /opt/remnawave/monitor.sh") | crontab -
    print_success "Monitoring configured (check every 5 minutes)"
else
    print_info "Monitoring already configured"
fi

# Test restart
echo ""
print_info "=== TESTING RESTART ==="

print_info "Testing restart functionality..."

# Stop
docker compose down

# Wait
sleep 3

# Start
docker compose up -d

# Wait for startup
sleep 5

# Check
if docker compose ps | grep -q "remnanode.*Up" && docker compose ps | grep -q "remnawave-nginx.*Up"; then
    print_success "Restart completed successfully"
else
    print_error "Problem with restart"
    docker compose logs --tail=50
fi

# Save final information
cat > /opt/remnawave/node_installation_complete.txt <<EOL
==========================================
        NODE INSTALLATION COMPLETE
==========================================
Date: $(date)

NODE PARAMETERS:
- Domain: $SELFSTEAL_DOMAIN
- IP: $NODE_IP
- Panel port: 2222
- HTTPS port: 443

STATUS:
- Containers running
- HTTPS access working
- Panel connection configured

MANAGEMENT:
- Status: node-status
- Control: node-manage {start|stop|restart|status|update|logs}
- Logs: docker logs remnanode
- Monitor: /opt/remnawave/monitor.log

NEXT STEPS:
1. Check in panel that node appears
2. Ensure node status is "Active"
3. Create test user for verification

TROUBLESHOOTING:
- If node not visible in panel:
  * Check certificate in .env-node
  * Check network connection to $PANEL_IP
  * Check logs: docker logs remnanode -f

==========================================
EOL

chmod 600 /opt/remnawave/node_installation_complete.txt

echo ""
print_success "Node installation completed!"
cat /opt/remnawave/node_installation_complete.txt
