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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

# Check OS version (Ubuntu only)
check_os() {
    if ! grep -q "jammy" /etc/os-release && ! grep -q "noble" /etc/os-release; then
        print_error "Supported only Ubuntu 22.04/24.04"
        exit 1
    fi
}

check_os
print_success "OS check passed"

# Update system and install base packages
print_warning "Updating system and installing base packages..."
apt-get update -y

apt-get install -y \
    ca-certificates \
    curl \
    jq \
    ufw \
    wget \
    gnupg \
    unzip \
    nano \
    dialog \
    git \
    certbot \
    python3-certbot-dns-cloudflare \
    unattended-upgrades \
    locales \
    dnsutils \
    coreutils \
    grep \
    gawk \
    cron

if [[ $? -eq 0 ]]; then
    print_success "Base packages installed successfully"
else
    print_error "Failed to install base packages"
    exit 1
fi

# Configure localization
print_info "Configuring localization..."
if ! grep -q "^en_US.UTF-8 UTF-8" /etc/locale.gen; then
    if grep -q "^# en_US.UTF-8 UTF-8" /etc/locale.gen; then
        sed -i 's/^# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    else
        echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    fi
fi
locale-gen
update-locale LANG=en_US.UTF-8
print_success "Localization configured"

# Install Docker
print_warning "Installing Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | tee /etc/apt/keyrings/docker.asc > /dev/null
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

if [[ $? -eq 0 ]]; then
    print_success "Docker installed successfully"
else
    print_error "Failed to install Docker"
    exit 1
fi

# Configure BBR
print_info "Configuring BBR..."
if ! grep -q "net.core.default_qdisc = fq" /etc/sysctl.conf; then
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
fi
if ! grep -q "net.ipv4.tcp_congestion_control = bbr" /etc/sysctl.conf; then
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
fi

if ! sysctl -p > /dev/null 2>&1; then
    print_warning "Failed to apply sysctl settings, but continuing..."
else
    print_success "BBR configured"
fi

# Configure UFW
print_warning "Configuring firewall..."
ufw --force reset
ufw allow 22/tcp comment 'SSH'
ufw allow 443/tcp comment 'HTTPS'
ufw --force enable
print_success "UFW firewall configured"
print_info "Port 2222 will be opened later only for panel IP"

# Configure automatic updates
print_info "Configuring automatic updates..."
echo 'Unattended-Upgrade::Mail "root";' >> /etc/apt/apt.conf.d/50unattended-upgrades
echo unattended-upgrades unattended-upgrades/enable_auto_updates boolean true | debconf-set-selections
dpkg-reconfigure -f noninteractive unattended-upgrades
systemctl restart unattended-upgrades
print_success "Automatic updates configured"

# Configure cron service
if ! dpkg -l | grep -q '^ii.*cron '; then
    apt-get install -y cron
fi

if ! systemctl is-active --quiet cron; then
    systemctl start cron || {
        print_error "Failed to start cron service"
    }
fi

if ! systemctl is-enabled --quiet cron; then
    systemctl enable cron || {
        print_error "Failed to enable cron service"
    }
fi
print_success "Cron service configured"

# Create working directories
mkdir -p /opt/remnawave
mkdir -p /var/www/html
cd /opt/remnawave
print_success "Working directories created"

# Create setup information file
cat > /opt/remnawave/node_setup_info.txt <<EOL
=================================================
        NODE INSTALLATION INFORMATION
=================================================

Prepare the following information:

1. Selfsteal domain (specified during panel installation)
   Example: node.example.com

2. Panel server IP address
   Example: 192.168.1.100

3. SSL certificate from panel
   Located in /opt/remnawave/.env-node on panel server
   In line SSL_CERT="..."

This information will be required in the next installation steps.
=================================================
EOL

# System readiness check
print_warning "Checking system readiness..."
echo ""
echo "=== System Status ==="

# Docker check
if command -v docker &> /dev/null; then
    echo -e "✓ Docker installed: $(docker --version)"
else
    echo -e "✗ Docker not installed"
fi

# Docker Compose check
if docker compose version &> /dev/null; then
    echo -e "✓ Docker Compose installed: $(docker compose version)"
else
    echo -e "✗ Docker Compose not installed"
fi

# Firewall check
if ufw status | grep -q "Status: active"; then
    echo -e "✓ Firewall active"
else
    echo -e "✗ Firewall not active"
fi

# Port check
echo -e "\n=== Port Status ==="
if ss -tlnp | grep -E ":(443|2222)" > /dev/null; then
    echo -e "⚠ Warning: Some required ports are already in use:"
    ss -tlnp | grep -E ":(443|2222)"
else
    echo -e "✓ Required ports are free"
fi

# Directory check
echo -e "\n=== Directory Status ==="
[ -d "/opt/remnawave" ] && echo "✓ Working directory created" || echo "✗ Working directory not created"
[ -d "/var/www/html" ] && echo "✓ Web content directory created" || echo "✗ Web content directory not created"

echo ""
print_success "System preparation completed!"
print_info "Review the information in /opt/remnawave/node_setup_info.txt"
print_warning "Next step: run SSL certificate setup script"
