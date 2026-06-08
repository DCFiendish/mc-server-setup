#!/bin/bash

# =============================================================
#  Pterodactyl Panel + Wings Setup
#  For Oracle A1 (Ubuntu 22.04 ARM64)
#  GitHub: DCFiendish
#  Run AFTER setup.sh or bmwoo-setup.sh
# =============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
section() { echo -e "\n${CYAN}===== $1 =====${NC}"; }

echo ""
echo "========================================="
echo "   Pterodactyl Panel + Wings Setup       "
echo "   FiendishHosting | Oracle A1           "
echo "========================================="
echo ""

# =============================================================
#  COLLECT INFO UPFRONT
# =============================================================

# Get server public IP automatically
PUBLIC_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me)
info "Detected public IP: $PUBLIC_IP"

echo ""
echo "You'll need these details for the installer:"
echo ""
read -p "Admin email for Pterodactyl panel: " ADMIN_EMAIL
read -p "Admin username (e.g. fiendish): " ADMIN_USER
read -s -p "Admin password: " ADMIN_PASS
echo ""
read -p "Admin first name: " ADMIN_FIRST
read -p "Admin last name: " ADMIN_LAST
echo ""

warn "No domain available yet — using IP address: $PUBLIC_IP"
warn "Panel will be accessible at http://$PUBLIC_IP (no SSL for now)"
warn "You can add a domain + SSL later once you have fiendishhosting.com"
echo ""

# =============================================================
#  OPEN REQUIRED PORTS (UFW)
# =============================================================
section "Opening Pterodactyl Ports"

# Panel ports
sudo ufw allow 80/tcp   comment 'Pterodactyl HTTP'
sudo ufw allow 443/tcp  comment 'Pterodactyl HTTPS (future)'
# Wings ports
sudo ufw allow 2022/tcp comment 'Pterodactyl Wings SFTP'
sudo ufw allow 8080/tcp comment 'Pterodactyl Wings API'
sudo ufw reload

info "Ports 80, 443, 2022, 8080 opened."
echo ""
echo -e "${YELLOW}IMPORTANT: Also open these in your OCI Security List:${NC}"
echo "  - TCP 80 (HTTP)"
echo "  - TCP 443 (HTTPS)"
echo "  - TCP 2022 (Wings SFTP)"
echo "  - TCP 8080 (Wings API)"
echo ""
read -p "Press Enter once you've opened them in OCI Console, or press Enter to continue anyway..."

# =============================================================
#  INSTALL DEPENDENCIES
# =============================================================
section "Installing Dependencies"

sudo apt-get update -y
sudo apt-get install -y curl wget git

# =============================================================
#  RUN PTERODACTYL COMMUNITY INSTALLER
# =============================================================
section "Running Pterodactyl Installer"

echo ""
info "Launching the Pterodactyl community installer..."
echo ""
echo "When prompted by the installer:"
echo "  - Select option 0 (Install panel)"  
echo "  - Database: use defaults (press Enter)"
echo "  - Use Let's Encrypt SSL: NO (no domain yet)"
echo "  - Use HTTP: YES"
echo "  - FQDN/Domain: enter your IP: $PUBLIC_IP"
echo ""
echo "After panel installs it will ask about Wings:"
echo "  - Select YES to install Wings on same machine"
echo "  - Node FQDN: enter your IP: $PUBLIC_IP"
echo "  - Use SSL: NO"
echo ""
read -p "Press Enter to launch the installer..."
echo ""

bash <(curl -s https://pterodactyl-installer.se)

# =============================================================
#  CREATE ADMIN USER
# =============================================================
section "Creating Admin User"

info "Creating Pterodactyl admin user..."
cd /var/www/pterodactyl

sudo php artisan p:user:make \
  --email="$ADMIN_EMAIL" \
  --username="$ADMIN_USER" \
  --name-first="$ADMIN_FIRST" \
  --name-last="$ADMIN_LAST" \
  --password="$ADMIN_PASS" \
  --admin=1 2>/dev/null || \
warn "User creation via artisan failed — you can create the user manually in the panel at http://$PUBLIC_IP"

# =============================================================
#  CREATE MINECRAFT NODE & ALLOCATION
# =============================================================
section "Notes on Node Setup"

echo ""
echo -e "${YELLOW}After this script finishes, you need to do these steps manually in the panel:${NC}"
echo ""
echo "1. Go to http://$PUBLIC_IP and log in"
echo "2. Go to Admin → Nodes → Create New"
echo "   - Name: Main Node"
echo "   - FQDN: $PUBLIC_IP"
echo "   - Port: 8080"  
echo "   - SSL: OFF"
echo "   - Memory: 20480 (20GB, leaving 4GB for panel/OS)"
echo "   - Disk: 150000 (150GB)"
echo "3. On the Node page → Configuration tab → copy the token"
echo "4. SSH into the server and run:"
echo "   sudo nano /etc/pterodactyl/config.yml"
echo "   Paste the token where it says 'token:'"
echo "   Save and run: sudo systemctl restart wings"
echo "5. Back in panel → Node → Allocations tab"
echo "   - Add allocation: IP = $PUBLIC_IP, Port = 25565"
echo "   - Add allocation: IP = $PUBLIC_IP, Port = 19132 (for Geyser)"
echo ""

# =============================================================
#  DONE
# =============================================================
section "Setup Complete!"

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}   Pterodactyl Setup Done!               ${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "  Panel URL:     http://$PUBLIC_IP"
echo "  Admin Email:   $ADMIN_EMAIL"
echo "  Admin User:    $ADMIN_USER"
echo ""
echo -e "${YELLOW}  Manual steps remaining:${NC}"
echo "  1) Open OCI Security List ports: 80, 443, 2022, 8080"
echo "  2) Create node in panel UI"
echo "  3) Paste Wings token into /etc/pterodactyl/config.yml"
echo "  4) Restart Wings: sudo systemctl restart wings"
echo "  5) Add port allocations (25565, 19132)"
echo "  6) Create server in panel pointing to Minecraft install"
echo ""
echo -e "${CYAN}  When you get fiendishhosting.com, run Certbot to add SSL:${NC}"
echo "  sudo certbot --nginx -d panel.fiendishhosting.com"
echo ""
