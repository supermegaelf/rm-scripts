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

cd /opt/remnawave

# Check if install_vars.sh exists
if [[ ! -f "/opt/remnawave/install_vars.sh" ]]; then
    print_error "install_vars.sh not found. Please run config setup script first."
    exit 1
fi

# Load variables
source /opt/remnawave/install_vars.sh

# Verify all required variables are loaded
REQUIRED_VARS=("PANEL_DOMAIN" "SUB_DOMAIN" "SUPERADMIN_USERNAME" "SUPERADMIN_PASSWORD" "COOKIES_RANDOM1" "COOKIES_RANDOM2")
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var}" ]]; then
        print_error "Required variable $var not found. Please run config setup script first."
        exit 1
    fi
done

print_success "All variables loaded successfully"

# Check Docker
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed"
    exit 1
fi

print_success "Docker version: $(docker --version)"
print_success "Docker Compose version: $(docker compose version)"

# Validate docker-compose.yml
if docker compose config --quiet; then
    print_success "Docker Compose configuration is valid"
else
    print_error "Docker Compose configuration is invalid"
    docker compose config
    exit 1
fi

# Check if containers are already running
if docker compose ps --services --filter "status=running" | grep -q .; then
    print_warning "Some containers are already running"
    echo "Current container status:"
    docker compose ps
    echo ""
    read -p "Do you want to restart all containers? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Stopping existing containers..."
        docker compose down
        sleep 5
    else
        print_warning "Continuing with existing containers..."
    fi
fi

# Pull Docker images
print_warning "Pulling Docker images..."
docker compose pull &
spinner $!
if [[ $? -eq 0 ]]; then
    print_success "Docker images pulled successfully"
else
    print_error "Failed to pull Docker images"
    exit 1
fi

# Start containers
print_warning "Starting containers..."
docker compose up -d
if [[ $? -eq 0 ]]; then
    print_success "Containers started successfully"
else
    print_error "Failed to start containers"
    exit 1
fi

# Wait for database
print_warning "Waiting for database to be ready..."
until docker exec remnawave-db pg_isready -U postgres > /dev/null 2>&1; do
    echo -n "."
    sleep 2
done
echo
print_success "Database is ready!"

# Wait for Redis
print_warning "Waiting for Redis to be ready..."
until docker exec remnawave-redis valkey-cli ping > /dev/null 2>&1; do
    echo -n "."
    sleep 2
done
echo
print_success "Redis is ready!"

# Wait for backend to be fully ready
print_warning "Waiting for backend service to be ready..."
max_attempts=30
attempt=1
while [ $attempt -le $max_attempts ]; do
    if curl -s -f "http://127.0.0.1:3000/api/auth/register" \
        -H "X-Forwarded-For: 127.0.0.1" \
        -H "X-Forwarded-Proto: https" > /dev/null 2>&1; then
        print_success "Backend service is ready!"
        break
    fi
    echo "Attempt $attempt of $max_attempts..."
    sleep 3
    ((attempt++))
done

if [ $attempt -gt $max_attempts ]; then
    print_error "Backend service failed to start"
    echo "Checking logs..."
    docker compose logs remnawave --tail=50
    exit 1
fi

# Wait for subscription service
print_warning "Waiting for subscription service..."
attempt=1
while [ $attempt -le 10 ]; do
    if nc -z 127.0.0.1 3010 2>/dev/null; then
        print_success "Subscription service is ready!"
        break
    fi
    echo "Attempt $attempt of 10..."
    sleep 2
    ((attempt++))
done

# Register administrator (handle case where admin already exists)
print_warning "Registering administrator..."

REGISTER_RESPONSE=$(curl -s -X POST "http://127.0.0.1:3000/api/auth/register" \
    -H "Content-Type: application/json" \
    -H "Host: $PANEL_DOMAIN" \
    -H "X-Forwarded-For: 127.0.0.1" \
    -H "X-Forwarded-Proto: https" \
    -d "{\"username\":\"$SUPERADMIN_USERNAME\",\"password\":\"$SUPERADMIN_PASSWORD\"}")

TOKEN=$(echo "$REGISTER_RESPONSE" | jq -r '.response.accessToken // empty')

# If registration failed, try to login
if [ -z "$TOKEN" ]; then
    print_warning "Registration failed, trying to login..."
    
    LOGIN_RESPONSE=$(curl -s -X POST "http://127.0.0.1:3000/api/auth/login" \
        -H "Content-Type: application/json" \
        -H "Host: $PANEL_DOMAIN" \
        -H "X-Forwarded-For: 127.0.0.1" \
        -H "X-Forwarded-Proto: https" \
        -d "{\"username\":\"$SUPERADMIN_USERNAME\",\"password\":\"$SUPERADMIN_PASSWORD\"}")
    
    TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.response.accessToken // empty')
    
    if [ -z "$TOKEN" ]; then
        print_error "Both registration and login failed!"
        echo "Register response: $REGISTER_RESPONSE"
        echo "Login response: $LOGIN_RESPONSE"
        exit 1
    else
        print_success "Successfully logged in with existing admin account"
    fi
else
    print_success "Administrator registered successfully!"
fi

# Save token
echo "$TOKEN" > /opt/remnawave/admin_token.txt
chmod 600 /opt/remnawave/admin_token.txt
print_success "Admin token saved"

# Get public key
print_warning "Getting public key for nodes..."

PUBKEY_RESPONSE=$(curl -s -X GET "http://127.0.0.1:3000/api/keygen" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Host: $PANEL_DOMAIN" \
    -H "X-Forwarded-For: 127.0.0.1" \
    -H "X-Forwarded-Proto: https")

PUBKEY=$(echo "$PUBKEY_RESPONSE" | jq -r '.response.pubKey // empty')

if [ -z "$PUBKEY" ]; then
    print_error "Failed to get public key!"
    echo "Server response: $PUBKEY_RESPONSE"
    exit 1
fi

print_success "Public key received!"

# Create node environment file
cat > /opt/remnawave/.env-node <<EOL
### APP ###
APP_PORT=2222

### XRAY ###
SSL_CERT="$PUBKEY"
EOL

chmod 600 /opt/remnawave/.env-node
print_success "Node environment file created"

# Wait for Nginx to be ready
print_warning "Waiting for Nginx to be ready..."
sleep 5

# Container status check (compatible with new docker compose)
echo -e "\n=== Container Status ==="
docker compose ps

# Check if all required containers are running
print_warning "Checking container health..."
required_containers=("remnawave" "remnawave-db" "remnawave-redis" "remnawave-nginx" "remnawave-subscription-page")
all_running=true

for container in "${required_containers[@]}"; do
    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "^${container}.*Up"; then
        print_success "$container is running"
    else
        print_error "$container is not running"
        all_running=false
    fi
done

if [ "$all_running" = false ]; then
    print_error "Not all required containers are running"
    docker compose logs --tail=50
    exit 1
fi

# Check ports
echo -e "\n=== Checking ports ==="
for port in 3000 3010 6767; do
    if ss -tlnp | grep -q ":$port "; then
        print_success "Port $port is listening"
    else
        print_warning "Port $port is not listening"
    fi
done

# Check HTTPS access (allow some time for nginx to start)
sleep 3
echo -e "\n=== Checking HTTPS access ==="
if curl -k -s -I "https://$PANEL_DOMAIN" 2>/dev/null | head -n 1 | grep -q "404"; then
    print_success "Panel domain is responding (auth required)"
else
    print_warning "Panel domain may not be accessible yet"
fi

if curl -k -s -I "https://$SUB_DOMAIN" 2>/dev/null | head -n 1 | grep -q "200\|404"; then
    print_success "Subscription domain is responding"
else
    print_warning "Subscription domain may not be accessible yet"
fi

# Test API
print_warning "Testing API functionality..."
CONFIG_RESPONSE=$(curl -s -X GET "http://127.0.0.1:3000/api/xray" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Host: $PANEL_DOMAIN" \
    -H "X-Forwarded-For: 127.0.0.1" \
    -H "X-Forwarded-Proto: https")

if echo "$CONFIG_RESPONSE" | jq -e '.response' > /dev/null 2>&1; then
    print_success "API is working correctly"
else
    print_warning "API may need more time to initialize"
fi

# Save deployment information
cat > /opt/remnawave/deployment_info.txt <<EOL
=================================================
         REMNAWAVE DEPLOYMENT INFORMATION
=================================================
Deployment Date: $(date)
Server IP: $(curl -s -4 ifconfig.me || echo "N/A")

CONTAINERS:
$(docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}")

ACCESS URLS:
- Panel: https://$PANEL_DOMAIN/auth/login?${COOKIES_RANDOM1}=${COOKIES_RANDOM2}
- Subscription: https://$SUB_DOMAIN

ADMIN CREDENTIALS:
- Username: $SUPERADMIN_USERNAME
- Password: [see credentials.txt]

NODE PUBLIC KEY:
$PUBKEY

SERVICE ENDPOINTS:
- Backend API: http://127.0.0.1:3000
- Subscription: http://127.0.0.1:3010
- PostgreSQL: 127.0.0.1:6767

FILES:
- /opt/remnawave/credentials.txt
- /opt/remnawave/admin_token.txt
- /opt/remnawave/.env-node
- /opt/remnawave/install_vars.sh
=================================================
EOL

chmod 600 /opt/remnawave/deployment_info.txt

# Final summary
echo ""
echo "================================================="
echo -e "${GREEN}    DEPLOYMENT COMPLETED SUCCESSFULLY!${NC}"
echo "================================================="
echo ""
echo "Panel Access:"
echo -e "${YELLOW}https://$PANEL_DOMAIN/auth/login?${COOKIES_RANDOM1}=${COOKIES_RANDOM2}${NC}"
echo ""
echo "Username: $SUPERADMIN_USERNAME"
echo "Password: Check credentials.txt"
echo ""
echo "All information saved in:"
echo "- /opt/remnawave/deployment_info.txt"
echo "- /opt/remnawave/credentials.txt"
echo "================================================="

print_success "Deployment completed! Panel should be accessible now."
