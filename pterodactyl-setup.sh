#!/bin/bash

# =============================================================
#  Pterodactyl Panel + Wings — Fully Automated Setup
#  FiendishHosting | Oracle A1 (Ubuntu 22.04 ARM64)
#  Run AFTER needrestart fix and iptables fix
# =============================================================

set -Eeuo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
section() { echo -e "\n${CYAN}===== $1 =====${NC}"; }

# =============================================================
#  COLLECT INFO UPFRONT (the only interactive part)
# =============================================================

echo ""
echo "========================================="
echo "   Pterodactyl Setup — FiendishHosting   "
echo "========================================="
echo ""

PUBLIC_IP=$(curl -fsSL https://api.ipify.org 2>/dev/null || curl -fsSL https://ifconfig.me)
info "Detected public IP: $PUBLIC_IP"
echo ""

read -p "Client email (for their Pterodactyl account): " CLIENT_EMAIL
read -s -p "Client panel password: " CLIENT_PASS
echo ""
read -p "Client first name: " CLIENT_FIRST
read -p "Client last name: " CLIENT_LAST
echo ""
info "Operator account will be created as: fiendishhosting@gmail.com / dcfiendish"
read -s -p "Operator panel password: " OPERATOR_PASS
echo ""
echo ""

# Validate inputs
[ -z "$CLIENT_EMAIL" ] && error "Client email is required"
[ -z "$CLIENT_PASS" ]  && error "Client password is required"
[ -z "$OPERATOR_PASS" ] && error "Operator password is required"

# =============================================================
#  INSTALL PTERODACTYL (fully unattended via env vars)
# =============================================================
section "Installing Pterodactyl Panel + Wings"

info "Downloading installer..."
curl -fsSL https://pterodactyl-installer.se -o /tmp/ptero-install.sh
chmod +x /tmp/ptero-install.sh

info "Running unattended install (this takes 5-10 minutes)..."

# Set all env vars to bypass interactive prompts
export FQDN="$PUBLIC_IP"
export timezone="America/New_York"
export email="fiendishhosting@gmail.com"
export user_email="fiendishhosting@gmail.com"
export user_username="dcfiendish"
export user_firstname="Fiendish"
export user_lastname="Hosting"
export user_password="$OPERATOR_PASS"
export ASSUME_SSL="false"
export CONFIGURE_LETSENCRYPT="false"
export CONFIGURE_FIREWALL="false"
export MYSQL_DB="panel"
export MYSQL_USER="pterodactyl"
export MYSQL_PASSWORD="$(openssl rand -hex 24)"

# Run panel + wings installer (option 2) non-interactively
# The installer reads env vars and skips prompts when they're set
echo "2" | bash /tmp/ptero-install.sh

info "Pterodactyl installer finished."

# =============================================================
#  FIX PERMISSIONS + NGINX (always required after install)
# =============================================================
section "Fixing Permissions and Nginx Config"

sudo chown -R www-data:www-data /var/www/pterodactyl
sudo chmod -R 755 /var/www/pterodactyl/storage

# Write correct nginx config (installer uses wrong PHP version — 8.3 not 8.1)
sudo tee /etc/nginx/sites-available/default > /dev/null << NGINXEOF
server {
    listen 80;
    server_name $PUBLIC_IP;
    root /var/www/pterodactyl/public;
    index index.html index.htm index.php;
    charset utf-8;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }
    access_log off;
    error_log /var/log/nginx/pterodactyl.app-error.log error;
    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;
    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }
    location ~ /\.ht { deny all; }
}
NGINXEOF

sudo nginx -t && sudo systemctl reload nginx
info "Nginx configured with php8.3-fpm."

# =============================================================
#  CREATE CLIENT ADMIN ACCOUNT
# =============================================================
section "Creating Panel Accounts"

info "Creating client admin account ($CLIENT_EMAIL)..."
cd /var/www/pterodactyl
sudo php artisan p:user:make \
  --email="$CLIENT_EMAIL" \
  --username="$(echo "$CLIENT_EMAIL" | cut -d@ -f1 | tr '.' '_' | tr -dc '[:alnum:]_')" \
  --name-first="$CLIENT_FIRST" \
  --name-last="$CLIENT_LAST" \
  --password="$CLIENT_PASS" \
  --admin=1 \
  --no-interaction \
  || warn "Client account creation failed — create manually in panel at http://$PUBLIC_IP"

info "Operator account (dcfiendish) was created during install."

# =============================================================
#  WAIT FOR PANEL TO BE READY
# =============================================================
section "Waiting for Panel"

info "Waiting for panel to be reachable..."
for i in {1..30}; do
  if curl -fsSL -o /dev/null "http://$PUBLIC_IP" 2>/dev/null; then
    info "Panel is up!"
    break
  fi
  sleep 5
  echo -n "."
done
echo ""

# =============================================================
#  GET API KEY (2 min manual step)
# =============================================================
section "API Key Setup"

echo ""
echo -e "${YELLOW}=============================================${NC}"
echo -e "${YELLOW}  MANUAL STEP REQUIRED (~2 minutes)         ${NC}"
echo -e "${YELLOW}=============================================${NC}"
echo ""
echo "  1. Open: http://$PUBLIC_IP"
echo "  2. Log in as: fiendishhosting@gmail.com"
echo "  3. Go to: Admin panel (gear icon) → Application API"
echo "  4. Click: Create New"
echo "  5. Description: FiendishHosting Setup"
echo "  6. Set ALL permissions to Read + Write"
echo "  7. Click: Create"
echo "  8. Copy the key (starts with ptla_)"
echo ""
read -p "Paste API key here: " API_KEY
[ -z "$API_KEY" ] && error "API key is required"

# Save API key for setup.sh to use
sudo mkdir -p /etc/fiendishhosting
echo "$API_KEY" | sudo tee /etc/fiendishhosting/api.key > /dev/null
sudo chmod 600 /etc/fiendishhosting/api.key
info "API key saved to /etc/fiendishhosting/api.key"

PANEL_URL="http://$PUBLIC_IP"
AUTH_HEADER="Authorization: Bearer $API_KEY"
ACCEPT_HEADER="Accept: application/vnd.pterodactyl.v1+json"
CONTENT_HEADER="Content-Type: application/json"

# Helper: API call with error checking
ptero_api() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"
  local response
  if [ -n "$data" ]; then
    response=$(curl -fsSL -X "$method" \
      -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -H "$CONTENT_HEADER" \
      -d "$data" \
      "$PANEL_URL/api/application/$endpoint")
  else
    response=$(curl -fsSL -X "$method" \
      -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" \
      "$PANEL_URL/api/application/$endpoint")
  fi
  echo "$response"
}

# =============================================================
#  CREATE LOCATION VIA API
# =============================================================
section "Creating Location"

info "Creating location us-east..."
LOCATION_RESPONSE=$(ptero_api POST "locations" \
  '{"short":"us-east","long":"Oracle US East Ashburn"}')

LOCATION_ID=$(echo "$LOCATION_RESPONSE" | jq -r '.attributes.id // empty')
[ -z "$LOCATION_ID" ] && error "Failed to create location. Response: $LOCATION_RESPONSE"
info "Location created with ID: $LOCATION_ID"

# =============================================================
#  CREATE NODE VIA API
# =============================================================
section "Creating Node"

info "Creating Main Node..."
NODE_RESPONSE=$(ptero_api POST "nodes" \
  "{
    \"name\": \"Main Node\",
    \"location_id\": $LOCATION_ID,
    \"fqdn\": \"$PUBLIC_IP\",
    \"scheme\": \"http\",
    \"memory\": 20480,
    \"memory_overallocate\": 0,
    \"disk\": 150000,
    \"disk_overallocate\": 0,
    \"upload_size\": 100,
    \"daemon_listen\": 8080,
    \"daemon_sftp\": 2022,
    \"behind_proxy\": false,
    \"maintenance_mode\": false,
    \"public\": true
  }")

NODE_ID=$(echo "$NODE_RESPONSE" | jq -r '.attributes.id // empty')
[ -z "$NODE_ID" ] && error "Failed to create node. Response: $NODE_RESPONSE"
info "Node created with ID: $NODE_ID"

# =============================================================
#  CREATE ALLOCATIONS VIA API
# =============================================================
section "Creating Allocations"

info "Adding port allocations (25565, 19132)..."
ptero_api POST "nodes/$NODE_ID/allocations" \
  "{\"ip\":\"0.0.0.0\",\"ports\":[\"25565\",\"19132\"]}" > /dev/null

info "Allocations added."

# =============================================================
#  CONFIGURE WINGS VIA AUTO-DEPLOY TOKEN
# =============================================================
section "Configuring Wings"

info "Getting Wings deploy token from panel..."
DEPLOY_TOKEN_RESPONSE=$(ptero_api POST "nodes/$NODE_ID/configuration" "")
DEPLOY_TOKEN=$(echo "$DEPLOY_TOKEN_RESPONSE" | jq -r '.token // empty')

if [ -z "$DEPLOY_TOKEN" ]; then
  # Fallback: use wings configure with manual token approach
  warn "Could not get auto-deploy token via API — trying wings configure directly..."
  warn "You may need to manually run the wings configure command from the panel."
else
  info "Configuring Wings with token..."
  sudo wings configure \
    --panel-url "$PANEL_URL" \
    --token "$DEPLOY_TOKEN" \
    --node "$NODE_ID" \
    || error "Wings configure failed"
fi

# =============================================================
#  START WINGS
# =============================================================
section "Starting Wings"

sudo systemctl enable wings
sudo systemctl start wings
sleep 5

if sudo systemctl is-active --quiet wings; then
  info "Wings is running."
else
  error "Wings failed to start. Check: sudo journalctl -u wings -n 50"
fi

# Save node ID for setup.sh
echo "$NODE_ID" | sudo tee /etc/fiendishhosting/node.id > /dev/null
echo "$PUBLIC_IP" | sudo tee /etc/fiendishhosting/panel.url > /dev/null

# =============================================================
#  DONE
# =============================================================
section "Setup Complete"

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}   Pterodactyl Setup Complete!           ${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "  Panel URL:        http://$PUBLIC_IP"
echo "  Operator login:   fiendishhosting@gmail.com"
echo "  Client login:     $CLIENT_EMAIL"
echo "  Node ID:          $NODE_ID"
echo "  Wings:            Running"
echo ""
echo -e "${YELLOW}  Next step: run setup.sh${NC}"
echo ""
echo -e "${YELLOW}  REMEMBER at handoff:${NC}"
echo "  1. Verify client can log in"
echo "  2. Delete dcfiendish account from panel"
echo "  3. Verify you can no longer log in"
echo ""
