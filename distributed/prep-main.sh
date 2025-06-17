#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print status messages
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if command succeeded
check_status() {
    if [ $? -eq 0 ]; then
        print_success "$1"
    else
        print_error "$1 failed!"
        exit 1
    fi
}

echo -e "${BLUE}=== System Setup Script ===${NC}"
echo -e "${YELLOW}This script will configure your system with Docker, security settings, and more${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

print_status "Step 1: Updating package list and installing essential packages..."
apt-get update -y
check_status "Package list update"

apt-get install -y ca-certificates curl jq ufw wget gnupg unzip nano dialog git certbot python3-certbot-dns-cloudflare unattended-upgrades locales dnsutils coreutils grep gawk
check_status "Essential packages installation"

print_status "Step 2: Installing and configuring cron service..."
apt-get install -y cron
check_status "Cron installation"

systemctl start cron
check_status "Cron service start"

systemctl enable cron
check_status "Cron service enable"

print_status "Step 3: Configuring system locale..."
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
check_status "Locale generation"

update-locale LANG=en_US.UTF-8
check_status "Locale update"

print_status "Step 4: Adding Docker repository..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | tee /etc/apt/keyrings/docker.asc > /dev/null
check_status "Docker GPG key download"

chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
check_status "Docker repository configuration"

print_status "Step 5: Installing Docker..."
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
check_status "Docker installation"

print_status "Step 6: Configuring network optimization (BBR)..."
echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
sysctl -p
check_status "Network optimization configuration"

print_status "Step 7: Configuring UFW firewall..."
ufw --force reset
ufw allow 22/tcp comment 'SSH'
ufw allow 443/tcp comment 'HTTPS'
ufw --force enable
check_status "UFW firewall configuration"

print_status "Step 8: Configuring automatic updates..."
echo 'Unattended-Upgrade::Mail "root";' >> /etc/apt/apt.conf.d/50unattended-upgrades
echo unattended-upgrades unattended-upgrades/enable_auto_updates boolean true | debconf-set-selections
dpkg-reconfigure -f noninteractive unattended-upgrades
check_status "Unattended upgrades configuration"

systemctl restart unattended-upgrades
check_status "Unattended upgrades service restart"

echo
echo -e "${GREEN}=== System Setup Complete! ===${NC}"
