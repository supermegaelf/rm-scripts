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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

# Update system and install base packages
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
grep -q "^en_US.UTF-8 UTF-8" /etc/locale.gen || echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8

print_success "Localization configured"

# Install Docker
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
echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
sysctl -p

print_success "BBR configured"

# Configure UFW
ufw --force reset
ufw allow 22/tcp comment 'SSH'
ufw allow 443/tcp comment 'HTTPS'
ufw --force enable

print_success "UFW firewall configured"

# Configure automatic updates
echo 'Unattended-Upgrade::Mail "root";' >> /etc/apt/apt.conf.d/50unattended-upgrades
echo unattended-upgrades unattended-upgrades/enable_auto_updates boolean true | debconf-set-selections
dpkg-reconfigure -f noninteractive unattended-upgrades
systemctl restart unattended-upgrades

print_success "Automatic updates configured"

# Configure cron
systemctl is-active --quiet cron || systemctl start cron
systemctl is-enabled --quiet cron || systemctl enable cron

print_success "Cron service configured"

# Create working directory
mkdir -p /opt/remnawave
cd /opt/remnawave

print_success "Working directory created at /opt/remnawave"

print_success "System setup completed successfully!"
