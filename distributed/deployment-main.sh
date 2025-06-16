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
    print_error "install_vars.sh not found. Please run config setup script first."
    exit 1
fi

# Load variables
source /opt/remnawave/install_vars.sh

# Verify variables are loaded
if [[ -z "$PANEL_DOMAIN" || -z "$SUB_DOMAIN" || -z "$SUPERADMIN_USERNAME" || -z "$SUPERADMIN_PASSWORD" ]]; then
    print_error "Required variables not found. Please run config setup script first."
    exit 1
fi

print_success "Variables loaded successfully"

# Check Docker
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed"
    exit 1
fi

docker --version
docker compose version

# Validate docker-compose.yml
if docker compose config --quiet; then
    print_success "Docker Compose configuration is valid"
else
    print_error "Docker Compose configuration is invalid"
    exit 1
fi

# Pull Docker images
echo "Loading Docker images..."
docker compose pull

if [[ $? -eq 0 ]]; then
    print_success "Docker images pulled successfully"
else
    print_error "Failed to pull Docker images"
    exit 1
fi

# Start containers
echo "Starting containers..."
docker compose up -d

if [[ $? -eq 0 ]]; then
    print_success "Containers started successfully"
else
    print_error "Failed to start containers"
    exit 1
fi

docker compose ps

# Function to check service availability
check_service() {
    local service_url=$1
    local max_attempts=30
    local attempt=1
    
    echo "Checking availability of $service_url..."
    
    while [ $attempt -le $max_attempts ]; do
        # For backend API and subscription service, just check if connection is possible
        if [[ "$service_url" == *"3000"* ]] || [[ "$service_url" == *"3010"* ]]; then
            # Extract port from URL
            local port=$(echo "$service_url" | sed 's/.*:\([0-9]*\).*/\1/')
            if nc -z 127.0.0.1 "$port" 2>/dev/null; then
                echo "✓ Service is available!"
                return 0
            fi
        else
            # For other services, use original check
            if curl -s -f -X GET "$service_url" \
                --header 'X-Forwarded-For: 127.0.0.1' \
                --header 'X-Forwarded-Proto: https' \
                > /dev/null 2>&1; then
                echo "✓ Service is available!"
                return 0
            fi
        fi
        
        echo "Attempt $attempt of $max_attempts... Waiting..."
        sleep 5
        ((attempt++))
    done
    
    echo "✗ Service unavailable after $max_attempts attempts"
    return 1
}

# Wait for database
echo "Waiting for database to be ready..."
until docker exec remnawave-db pg_isready -U postgres > /dev/null 2>&1; do
    echo "Database is not ready yet..."
    sleep 3
done
print_success "Database is ready!"

# Wait for Redis
echo "Waiting for Redis to be ready..."
until docker exec remnawave-redis valkey-cli ping > /dev/null 2>&1; do
    echo "Redis is not ready yet..."
    sleep 3
done
print_success "Redis is ready!"

# Check services
if ! check_service "http://127.0.0.1:3000/api/auth/register"; then
    print_error "Backend service is not available"
    echo "Checking backend container logs..."
    docker compose logs remnawave --tail=20
    echo "Checking container status..."
    docker compose ps
    exit 1
fi

if ! check_service "http://127.0.0.1:3010"; then
    print_error "Subscription service is not available"
    exit 1
fi

# Register administrator
echo "Registering administrator..."

REGISTER_RESPONSE=$(curl -s -X POST "http://127.0.0.1:3000/api/auth/register" \
    -H "Content-Type: application/json" \
    -H "Host: $PANEL_DOMAIN" \
    -H "X-Forwarded-For: 127.0.0.1" \
    -H "X-Forwarded-Proto: https" \
    -d "{\"username\":\"$SUPERADMIN_USERNAME\",\"password\":\"$SUPERADMIN_PASSWORD\"}")

TOKEN=$(echo "$REGISTER_RESPONSE" | jq -r '.response.accessToken')

if [ -z "$TOKEN" ] || [ "$TOKEN" == "null" ]; then
    print_error "Registration failed!"
    echo "Server response: $REGISTER_RESPONSE"
    exit 1
fi

print_success "Administrator registered successfully!"
echo "Token received: ${TOKEN:0:20}..."

# Save token to file
echo "$TOKEN" > /opt/remnawave/admin_token.txt
chmod 600 /opt/remnawave/admin_token.txt

# Verify token was saved
if [[ -f "/opt/remnawave/admin_token.txt" ]] && [[ -s "/opt/remnawave/admin_token.txt" ]]; then
    print_success "Admin token saved successfully"
else
    print_error "Failed to save admin token"
    exit 1
fi

# Get public key
echo "Getting public key for nodes..."

PUBKEY_RESPONSE=$(curl -s -X GET "http://127.0.0.1:3000/api/keygen" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Host: $PANEL_DOMAIN" \
    -H "X-Forwarded-For: 127.0.0.1" \
    -H "X-Forwarded-Proto: https")

PUBKEY=$(echo "$PUBKEY_RESPONSE" | jq -r '.response.pubKey')

if [ -z "$PUBKEY" ] || [ "$PUBKEY" == "null" ]; then
    print_error "Failed to get public key!"
    echo "Server response: $PUBKEY_RESPONSE"
    exit 1
fi

print_success "Public key received!"
echo "Key: $PUBKEY"

# Create node environment file
cat > /opt/remnawave/.env-node <<EOL
### APP ###
APP_PORT=2222

### XRAY ###
SSL_CERT="$PUBKEY"
EOL

chmod 600 /opt/remnawave/.env-node

print_success "Node environment file created"

# Container status check
echo "=== Container Status ==="
docker compose ps

echo -e "\n=== Used Ports ==="
ss -tlnp | grep -E ":(3000|3010|6767|443)"

echo -e "\n=== Checking logs for errors ==="
if docker compose logs --tail=50 | grep -i error >/dev/null; then
    print_warning "Errors found in logs"
else
    print_success "No errors found in logs"
fi

# Check API functionality
echo "Checking API..."

CONFIG_RESPONSE=$(curl -s -X GET "http://127.0.0.1:3000/api/xray" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Host: $PANEL_DOMAIN" \
    -H "X-Forwarded-For: 127.0.0.1" \
    -H "X-Forwarded-Proto: https")

if echo "$CONFIG_RESPONSE" | jq -e '.response' > /dev/null; then
    print_success "API is working correctly"
else
    print_error "API issues detected"
    echo "Response: $CONFIG_RESPONSE"
fi

# Save deployment information
cat > /opt/remnawave/deployment_info.txt <<EOL
========================================
REMNAWAVE DEPLOYMENT INFORMATION
========================================
Deployment Date: $(date)
Server IP: $(curl -s -4 ifconfig.me || echo "N/A")

CONTAINERS STATUS:
$(docker compose ps)

ACCESS INFORMATION:
- Panel URL: https://$PANEL_DOMAIN/auth/login?${COOKIES_RANDOM1}=${COOKIES_RANDOM2}
- Subscription URL: https://$SUB_DOMAIN
- Admin Username: $SUPERADMIN_USERNAME
- Admin Password: [see credentials.txt]

PUBLIC KEY FOR NODES:
$PUBKEY

API ENDPOINTS:
- Main API: http://127.0.0.1:3000
- Subscription: http://127.0.0.1:3010
- PostgreSQL: 127.0.0.1:6767

IMPORTANT FILES:
- Credentials: /opt/remnawave/credentials.txt
- Admin Token: /opt/remnawave/admin_token.txt
- Node Config: /opt/remnawave/.env-node
- Variables: /opt/remnawave/install_vars.sh

========================================
EOL

chmod 600 /opt/remnawave/deployment_info.txt

print_success "Deployment information saved"

# Final status check
echo -e "\n========================================="
echo "DEPLOYMENT CHECK:"
echo "========================================="

check_status() {
    if [ $2 -eq 0 ]; then
        echo -e "✓ $1 - OK"
    else
        echo -e "✗ $1 - FAILED"
    fi
}

docker compose ps | grep -q "remnawave.*Up" && s1=0 || s1=1
docker compose ps | grep -q "remnawave-db.*Up" && s2=0 || s2=1
docker compose ps | grep -q "remnawave-redis.*Up" && s3=0 || s3=1
docker compose ps | grep -q "remnawave-nginx.*Up" && s4=0 || s4=1
docker compose ps | grep -q "remnawave-subscription-page.*Up" && s5=0 || s5=1

check_status "Backend container" $s1
check_status "Database" $s2
check_status "Redis" $s3
check_status "Nginx" $s4
check_status "Subscription page" $s5

[ -n "$TOKEN" ] && s6=0 || s6=1
[ -n "$PUBKEY" ] && s7=0 || s7=1

check_status "Administrator token" $s6
check_status "Public key" $s7

echo "========================================="

print_success "Deployment completed successfully!"
