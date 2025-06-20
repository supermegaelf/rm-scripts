#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# WireProxy WARP Management Script
echo
echo -e "${PURPLE}==========================${NC}"
echo -e "${NC}WireProxy WARP Management${NC}"
echo -e "${PURPLE}==========================${NC}"
echo

# Check if script is run with parameters
if [ "$1" = "uninstall" ] || [ "$1" = "--uninstall" ] || [ "$1" = "-u" ]; then
   ACTION="uninstall"
elif [ "$1" = "install" ] || [ "$1" = "--install" ] || [ "$1" = "-i" ]; then
   ACTION="install"
else
   # Interactive menu
   echo -e "${CYAN}Please select an action:${NC}"
   echo
   echo -e "${GREEN}1.${NC} Install WireProxy WARP"
   echo -e "${RED}2.${NC} Uninstall WireProxy WARP"
   echo -e "${YELLOW}3.${NC} Exit"
   echo
   
   while true; do
       read -p "Enter your choice (1-3): " CHOICE
       case $CHOICE in
           1)
               ACTION="install"
               break
               ;;
           2)
               ACTION="uninstall"
               break
               ;;
           3)
               echo -e "${CYAN}Goodbye!${NC}"
               exit 0
               ;;
           *)
               echo -e "${RED}Invalid choice. Please enter 1, 2, or 3.${NC}"
               ;;
       esac
   done
fi

# Uninstall function
if [ "$ACTION" = "uninstall" ]; then
   echo
   echo -e "${PURPLE}===========================${NC}"
   echo -e "${NC}WireProxy WARP Uninstaller${NC}"
   echo -e "${PURPLE}===========================${NC}"
   echo

   # Check if WireProxy is installed
   if [ ! -f "/usr/bin/wireproxy" ] && [ ! -f "/etc/systemd/system/wireproxy.service" ]; then
       echo -e "${YELLOW}WireProxy WARP is not installed on this system.${NC}"
       exit 0
   fi

   # Confirmation
   echo -e "${YELLOW}This will completely remove WireProxy WARP setup.${NC}"
   echo -e "${YELLOW}Are you sure you want to continue? (y/N)${NC}"
   read -r CONFIRM

   if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
       echo -e "${CYAN}Uninstallation cancelled.${NC}"
       exit 0
   fi

   echo
   echo -e "${GREEN}========================${NC}"
   echo -e "${NC}Removing WireProxy WARP${NC}"
   echo -e "${GREEN}========================${NC}"
   echo

   # Stop and disable service
   echo "Stopping WireProxy service..."
   systemctl stop wireproxy 2>/dev/null && echo "✓ Service stopped" || echo "ℹ Service was not running"
   systemctl disable wireproxy 2>/dev/null && echo "✓ Service disabled" || echo "ℹ Service was not enabled"

   # Remove systemd service
   echo "Removing systemd service..."
   if [ -f "/etc/systemd/system/wireproxy.service" ]; then
       rm -f /etc/systemd/system/wireproxy.service
       systemctl daemon-reload
       echo "✓ Systemd service removed"
   else
       echo "ℹ Systemd service file not found"
   fi

   # Remove configuration files
   echo "Removing configuration files..."
   if [ -f "/etc/wireguard/proxy.conf" ]; then
       rm -f /etc/wireguard/proxy.conf
       echo "✓ Configuration file removed"
   else
       echo "ℹ Configuration file not found"
   fi
   
   # Remove directory if empty
   if [ -d "/etc/wireguard" ] && [ -z "$(ls -A /etc/wireguard)" ]; then
       rmdir /etc/wireguard
       echo "✓ Empty wireguard directory removed"
   fi

   # Remove WireProxy binary
   echo "Removing WireProxy binary..."
   if [ -f "/usr/bin/wireproxy" ]; then
       rm -f /usr/bin/wireproxy
       echo "✓ WireProxy binary removed"
   else
       echo "ℹ WireProxy binary not found"
   fi

   # Remove management script
   echo "Removing management script..."
   if [ -f "/usr/bin/warp" ]; then
       rm -f /usr/bin/warp
       echo "✓ Management script removed"
   else
       echo "ℹ Management script not found"
   fi

   # Remove temporary files
   echo "Cleaning up temporary files..."
   rm -f /tmp/warp-account.conf /tmp/wireproxy.tar.gz
   echo "✓ Temporary files cleaned"

   echo
   echo -e "${GREEN}===========================================${NC}"
   echo -e "${NC}✓ WireProxy WARP uninstalled successfully!${NC}"
   echo -e "${GREEN}===========================================${NC}"
   echo
   exit 0
fi

# Installation process
echo
echo -e "${PURPLE}=====================${NC}"
echo -e "${NC}WireProxy WARP Setup${NC}"
echo -e "${PURPLE}=====================${NC}"
echo

# Check if already installed
if [ -f "/usr/bin/wireproxy" ] && [ -f "/etc/systemd/system/wireproxy.service" ]; then
   echo -e "${YELLOW}WireProxy WARP appears to be already installed.${NC}"
   echo -e "${YELLOW}Do you want to reinstall? (y/N)${NC}"
   read -r REINSTALL
   
   if [[ ! "$REINSTALL" =~ ^[Yy]$ ]]; then
       echo -e "${CYAN}Installation cancelled.${NC}"
       echo -e "${CYAN}Use 'warp status' to check current installation.${NC}"
       exit 0
   fi
   
   echo -e "${YELLOW}Proceeding with reinstallation...${NC}"
fi

set -e

echo -e "${GREEN}======================${NC}"
echo -e "${NC}1. System preparation${NC}"
echo -e "${GREEN}======================${NC}"
echo

# Update package list and install basic packages
echo "Updating package list and installing dependencies..."
apt-get update -y
apt-get install -y curl wget net-tools iproute2 iptables jq tar

echo
echo -e "${GREEN}--------------------------------${NC}"
echo -e "${NC}✓ System preparation completed!${NC}"
echo -e "${GREEN}--------------------------------${NC}"
echo

echo -e "${GREEN}=========================${NC}"
echo -e "${NC}2. Creating WARP account${NC}"
echo -e "${GREEN}=========================${NC}"
echo

# Create directory structure
echo "Creating directory structure..."
mkdir -p /etc/wireguard

# Register WARP account
echo "Registering WARP account..."
curl -s "https://warp.cloudflare.now.cc/?run=register" > /tmp/warp-account.conf

# Verify account creation
if [ ! -s /tmp/warp-account.conf ]; then
   echo -e "${RED}Failed to create WARP account!${NC}"
   exit 1
fi

echo "WARP account registered successfully!"

echo
echo -e "${GREEN}-----------------------------------${NC}"
echo -e "${NC}✓ WARP account creation completed!${NC}"
echo -e "${GREEN}-----------------------------------${NC}"
echo

echo -e "${GREEN}========================${NC}"
echo -e "${NC}3. Installing WireProxy${NC}"
echo -e "${GREEN}========================${NC}"
echo

# Determine architecture
echo "Detecting system architecture..."
ARCH=$(uname -m)
case $ARCH in
   x86_64) ARCH="amd64" ;;
   aarch64) ARCH="arm64" ;;
   *) 
       echo -e "${RED}Unsupported architecture: $ARCH${NC}"
       exit 1
       ;;
esac
echo "Architecture detected: $ARCH"

# Download and install WireProxy
echo "Downloading WireProxy..."
wget -O /tmp/wireproxy.tar.gz "https://github.com/pufferffish/wireproxy/releases/download/v1.0.9/wireproxy_linux_${ARCH}.tar.gz"

if [ ! -f /tmp/wireproxy.tar.gz ]; then
   echo -e "${RED}Failed to download WireProxy!${NC}"
   exit 1
fi

echo "Installing WireProxy..."
tar xzf /tmp/wireproxy.tar.gz -C /usr/bin/
chmod +x /usr/bin/wireproxy

# Clean up
rm -f /tmp/wireproxy.tar.gz

echo
echo -e "${GREEN}------------------------------------${NC}"
echo -e "${NC}✓ WireProxy installation completed!${NC}"
echo -e "${GREEN}------------------------------------${NC}"
echo

echo -e "${GREEN}==========================${NC}"
echo -e "${NC}4. Creating configuration${NC}"
echo -e "${GREEN}==========================${NC}"
echo

# Extract data from WARP account
echo "Extracting WARP account data..."
PRIVATE_KEY=$(jq -r '.private_key' /tmp/warp-account.conf)
ADDRESS_V6=$(jq -r '.config.interface.addresses.v6' /tmp/warp-account.conf)

if [ "$PRIVATE_KEY" == "null" ] || [ "$ADDRESS_V6" == "null" ]; then
   echo -e "${RED}Failed to extract account data!${NC}"
   exit 1
fi

echo "Private Key: ${PRIVATE_KEY:0:20}..."
echo "IPv6 Address: $ADDRESS_V6"

# Create WireProxy configuration
echo "Creating WireProxy configuration..."
cat > /etc/wireguard/proxy.conf << EOF
[Interface]
Address = 172.16.0.2/32
Address = ${ADDRESS_V6}/128
MTU = 1280
PrivateKey = ${PRIVATE_KEY}
DNS = 1.1.1.1,8.8.8.8,8.8.4.4,2606:4700:4700::1111,2001:4860:4860::8888,2001:4860:4860::8844

[Peer]
PublicKey = bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=
Endpoint = engage.cloudflareclient.com:2408
AllowedIPs = 0.0.0.0/0, ::/0

[Socks5]
BindAddress = 127.0.0.1:40000
EOF

echo
echo -e "${GREEN}------------------------------------${NC}"
echo -e "${NC}✓ Configuration creation completed!${NC}"
echo -e "${GREEN}------------------------------------${NC}"
echo

echo -e "${GREEN}=========================${NC}"
echo -e "${NC}5. Testing configuration${NC}"
echo -e "${GREEN}=========================${NC}"
echo

# Test configuration
echo "Testing WireProxy configuration..."
timeout 5 /usr/bin/wireproxy -c /etc/wireguard/proxy.conf > /dev/null 2>&1 &
WIREPROXY_PID=$!

sleep 2

if kill -0 $WIREPROXY_PID 2>/dev/null; then
   echo -e "${GREEN}Configuration test passed!${NC}"
   kill $WIREPROXY_PID 2>/dev/null || true
else
   echo -e "${RED}Configuration test failed!${NC}"
   exit 1
fi

echo
echo -e "${GREEN}-----------------------------------${NC}"
echo -e "${NC}✓ Configuration testing completed!${NC}"
echo -e "${GREEN}-----------------------------------${NC}"
echo

echo -e "${GREEN}============================${NC}"
echo -e "${NC}6. Creating systemd service${NC}"
echo -e "${GREEN}============================${NC}"
echo

# Create systemd service
echo "Creating systemd service..."
cat > /etc/systemd/system/wireproxy.service << EOF
[Unit]
Description=WireProxy for WARP
After=network.target
Documentation=https://github.com/pufferffish/wireproxy

[Service]
ExecStart=/usr/bin/wireproxy -c /etc/wireguard/proxy.conf
RemainAfterExit=yes
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start service
echo "Starting WireProxy service..."
systemctl daemon-reload
systemctl start wireproxy
systemctl enable wireproxy

# Wait for service to start
sleep 3

echo
echo -e "${GREEN}--------------------------------------${NC}"
echo -e "${NC}✓ Systemd service creation completed!${NC}"
echo -e "${GREEN}--------------------------------------${NC}"
echo

echo -e "${GREEN}==============================${NC}"
echo -e "${NC}7. Creating management script${NC}"
echo -e "${GREEN}==============================${NC}"
echo

# Create management script
echo "Creating management script..."
cat > /usr/bin/warp << 'EOF'
#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

case "$1" in
   start)
       systemctl start wireproxy
       echo -e "${GREEN}WireProxy started${NC}"
       ;;
   stop)
       systemctl stop wireproxy
       echo -e "${YELLOW}WireProxy stopped${NC}"
       ;;
   restart)
       systemctl restart wireproxy
       echo -e "${GREEN}WireProxy restarted${NC}"
       ;;
   status)
       systemctl status wireproxy
       ;;
   test)
       echo -e "${YELLOW}Testing WARP connection...${NC}"
       if curl --proxy socks5h://127.0.0.1:40000 --connect-timeout 10 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep -q "warp="; then
           echo -e "${GREEN}WARP connection is working!${NC}"
           echo "Your IP information:"
           curl --proxy socks5h://127.0.0.1:40000 --silent https://ipinfo.io
       else
           echo -e "${RED}WARP connection failed!${NC}"
       fi
       ;;
   info)
       echo -e "${GREEN}WireProxy WARP Information:${NC}"
       echo "SOCKS5 Proxy: 127.0.0.1:40000"
       echo "Service status:"
       systemctl is-active wireproxy
       echo "Port status:"
       ss -tlnp | grep 40000 || echo "Port not listening"
       ;;
   logs)
       journalctl -u wireproxy.service -f
       ;;
   uninstall)
       echo -e "${PURPLE}WireProxy WARP Uninstaller${NC}"
       echo
       echo -e "${YELLOW}This will completely remove WireProxy WARP setup.${NC}"
       echo -e "${YELLOW}Are you sure you want to continue? (y/N)${NC}"
       read -r CONFIRM

       if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
           echo -e "${CYAN}Uninstallation cancelled.${NC}"
           exit 0
       fi

       echo
       echo "Stopping WireProxy service..."
       systemctl stop wireproxy 2>/dev/null
       systemctl disable wireproxy 2>/dev/null

       echo "Removing systemd service..."
       rm -f /etc/systemd/system/wireproxy.service
       systemctl daemon-reload

       echo "Removing configuration files..."
       rm -f /etc/wireguard/proxy.conf
       rmdir /etc/wireguard 2>/dev/null || true

       echo "Removing WireProxy binary..."
       rm -f /usr/bin/wireproxy

       echo "Removing management script..."
       rm -f /usr/bin/warp

       echo "Cleaning up temporary files..."
       rm -f /tmp/warp-account.conf /tmp/wireproxy.tar.gz

       echo
       echo -e "${GREEN}WireProxy WARP uninstalled successfully!${NC}"
       ;;
   *)
       echo "WireProxy WARP Management Script"
       echo ""
       echo "Usage: $0 {start|stop|restart|status|test|info|logs|uninstall}"
       echo ""
       echo "Commands:"
       echo "  start      - Start WireProxy service"
       echo "  stop       - Stop WireProxy service"  
       echo "  restart    - Restart WireProxy service"
       echo "  status     - Show service status"
       echo "  test       - Test WARP connection"
       echo "  info       - Show proxy information"
       echo "  logs       - Show real-time logs"
       echo -e "  ${RED}uninstall  - Completely remove WireProxy WARP${NC}"
       echo ""
       echo "Examples:"
       echo "  curl --proxy socks5h://127.0.0.1:40000 https://ipinfo.io"
       echo "  curl --proxy socks5h://127.0.0.1:40000 https://www.cloudflare.com/cdn-cgi/trace"
       exit 1
       ;;
esac
EOF

chmod +x /usr/bin/warp

echo
echo -e "${GREEN}----------------------------------------${NC}"
echo -e "${NC}✓ Management script creation completed!${NC}"
echo -e "${GREEN}----------------------------------------${NC}"
echo

echo -e "${GREEN}======================${NC}"
echo -e "${NC}8. Final verification${NC}"
echo -e "${GREEN}======================${NC}"
echo

# Final verification
echo "Performing final verification..."

# Check if service is running
if systemctl is-active --quiet wireproxy; then
   echo -e "${GREEN}✓ WireProxy service is running${NC}"
else
   echo -e "${RED}✗ WireProxy service is not running${NC}"
   echo "Checking logs..."
   journalctl -u wireproxy.service -n 10 --no-pager
   exit 1
fi

# Check if port is listening
if ss -tlnp | grep -q 40000; then
   echo -e "${GREEN}✓ SOCKS5 proxy is listening on port 40000${NC}"
else
   echo -e "${RED}✗ SOCKS5 proxy is not listening${NC}"
   exit 1
fi

# Test connection
echo "Testing WARP connection..."
if curl --proxy socks5h://127.0.0.1:40000 --connect-timeout 10 --silent https://www.cloudflare.com/cdn-cgi/trace | grep -q "warp="; then
   echo -e "${GREEN}✓ WARP connection is working!${NC}"
else
   echo -e "${YELLOW}⚠ WARP connection test inconclusive${NC}"
fi

# Clean up temporary files
rm -f /tmp/warp-account.conf

echo
echo -e "${GREEN}--------------------------------${NC}"
echo -e "${NC}✓ Final verification completed!${NC}"
echo -e "${GREEN}--------------------------------${NC}"
echo

echo -e "${GREEN}===============================================${NC}"
echo -e "${NC}✓ WireProxy WARP setup completed successfully!${NC}"
echo -e "${GREEN}===============================================${NC}"
echo
echo -e "${CYAN}SOCKS5 Proxy Information:${NC}"
echo -e "Address: ${WHITE}127.0.0.1:40000${NC}"
echo
echo -e "${CYAN}Management Commands:${NC}"
echo -e "Check status: ${WHITE}warp status${NC}"
echo -e "Test connection: ${WHITE}warp test${NC}"
echo -e "Show information: ${WHITE}warp info${NC}"
echo -e "View logs: ${WHITE}warp logs${NC}"
echo -e "Uninstall: ${RED}warp uninstall${NC}"
echo
echo -e "${CYAN}Usage Examples:${NC}"
echo -e "Test with curl: ${WHITE}curl --proxy socks5h://127.0.0.1:40000 https://ipinfo.io${NC}"
echo -e "Check WARP status: ${WHITE}curl --proxy socks5h://127.0.0.1:40000 https://www.cloudflare.com/cdn-cgi/trace${NC}"
echo
echo -e "${GREEN}Setup completed! Your WARP SOCKS5 proxy is ready to use.${NC}"
echo
