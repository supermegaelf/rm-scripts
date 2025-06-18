#!/bin/bash

# Remnawave package installation script
# Section 2: Installing packages

set -e

echo "========================================="
echo "Remnawave Package Installation"
echo "========================================="
echo

# Update package list and install basic packages
echo "Installing basic packages..."
apt-get update -y
apt-get install -y ca-certificates curl jq ufw wget gnupg unzip nano dialog git certbot python3-certbot-dns-cloudflare unattended-upgrades locales dnsutils coreutils grep gawk

# Install and enable cron
echo
echo "Installing and enabling cron..."
apt-get install -y cron
systemctl start cron
systemctl enable cron

# Configure locales
echo
echo "Configuring locales..."
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8

# Set timezone
echo
echo "Setting timezone to Europe/Moscow..."
timedatectl set-timezone Europe/Moscow

# Add Docker repository
echo
echo "Adding Docker repository..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | tee /etc/apt/keyrings/docker.asc > /dev/null
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
echo
echo "Installing Docker..."
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Configure TCP BBR
echo
echo "Configuring TCP BBR..."
echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
sysctl -p

# Configure UFW firewall
echo
echo "Configuring UFW firewall..."
ufw --force reset
ufw allow 22/tcp comment 'SSH'
ufw allow 443/tcp comment 'HTTPS'
ufw --force enable

# Configure unattended upgrades
echo
echo "Configuring unattended upgrades..."
echo 'Unattended-Upgrade::Mail "root";' >> /etc/apt/apt.conf.d/50unattended-upgrades
echo unattended-upgrades unattended-upgrades/enable_auto_updates boolean true | debconf-set-selections
dpkg-reconfigure -f noninteractive unattended-upgrades
systemctl restart unattended-upgrades

echo
echo "✓ Package installation completed!"
echo
