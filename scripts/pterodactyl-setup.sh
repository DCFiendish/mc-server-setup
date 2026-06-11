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

read -p "Client email: " CLIENT_EMAIL
read -p "Client first name: " CLIENT_FIRST
read -p "Client last name: " CLIENT_LAST
echo ""
info "Operator account will be created as: fiendishhosting@gmail.com / dcfiendish"
read -s -p "Operator panel password: " OPERATOR_PASS
echo ""
echo ""

# Validate inputs
[ -z "$CLIENT_EMAIL" ]  && error "Client email is required"
[ -z "$CLIENT_FIRST" ]  && error "Client first name is required"
[ -z "$CLIENT_LAST" ]   && error "Client last name is required"
[ -z "$OPERATOR_PASS" ] && error "Operator password is required"

# Generate a random secure client password (never shown to operator until end)
CLIENT_PASS=$(openssl rand -base64 16 | tr -dc 'A-Za-z0-9!@#$%' | head -c 16)
CLIENT_USERNAME=$(echo "$CLIENT_EMAIL" | cut -d@ -f1 | tr '.' '_' | tr -dc '[:alnum:]_' | head -c 16)

# =============================================================
#  INSTALL EXPECT
# =============================================================
section "Installing expect"
apt-get install -y expect > /dev/null 2>&1
info "expect installed."

# =============================================================
#  DOWNLOAD PTERODACTYL INSTALLER
# =============================================================
section "Downloading Pterodactyl Installer"
sudo rm -f /tmp/ptero-install.sh /tmp/lib.sh
curl -fsSL https://pterodactyl-installer.se -o /tmp/ptero-install.sh
chmod +x /tmp/ptero-install.sh
info "Installer downloaded."

# =============================================================
#  BUILD EXPECT SCRIPT
# =============================================================
section "Building expect script"

sudo tee /tmp/ptero-expect.sh > /dev/null << EXPECTEOF
#!/usr/bin/expect -f
set timeout 600
set operator_pass "$OPERATOR_PASS"
set public_ip "$PUBLIC_IP"

proc answer {val} {
    sleep 0.5
    send "\$val\r"
}

spawn bash /tmp/ptero-install.sh

expect {
    "Input 0-6:"                                    { answer "2"; exp_continue }
    "Are you sure you want to proceed? (y/N):"      { answer "y"; exp_continue }
    "Database name"                                 { answer ""; exp_continue }
    "Database username"                             { answer ""; exp_continue }
    "Password (press enter"                         { answer ""; exp_continue }
    "Select timezone"                               { answer "America/New_York"; exp_continue }
    "Let's Encrypt and Pterodactyl:"                { answer "fiendishhosting@gmail.com"; exp_continue }
    "Email address for the initial admin account:"  { answer "fiendishhosting@gmail.com"; exp_continue }
    "Username for the initial admin account:"       { answer "dcfiendish"; exp_continue }
    "First name for the initial admin account:"     { answer "Fiendish"; exp_continue }
    "Last name for the initial admin account:"      { answer "Hosting"; exp_continue }
    "Password for the initial admin account:"       { answer "\$operator_pass"; exp_continue }
    "Set the FQDN of this panel"                    { answer "\$public_ip"; exp_continue }
    "configure UFW (firewall)? (y/N):"              { answer "n"; exp_continue }
    "configure firewall-cmd (firewall)? (y/N):"     { answer "n"; exp_continue }
    "anonymous telemetry data? (yes/no)"            { answer "n"; exp_continue }
    "Continue with installation? (y/N):"            { answer "y"; exp_continue }
    "configure a user for database hosts? (y/N):"   { answer "n"; exp_continue }
    "configure HTTPS using Let's Encrypt? (y/N):"   { answer "n"; exp_continue }
    "proceed to wings installation? (y/N):"         { answer "y"; exp_continue }
    "Proceed with installation? (y/N):"             { answer "y"; exp_continue }
    "Still assume SSL? (y/N):"                      { answer "n"; exp_continue }
    eof
}
EXPECTEOF

sudo chmod +x /tmp/ptero-expect.sh
info "Expect script built."

# =============================================================
#  RUN INSTALLER
# =============================================================
section "Running Pterodactyl Installer (5-10 minutes)"
expect /tmp/ptero-expect.sh
info "Installer finished."

# =============================================================
#  FIX PERMISSIONS + NGINX
# =============================================================
section "Fixing Permissions and Nginx Config"

sudo chown -R www-data:www-data /var/www/pterodactyl
sudo chmod -R 755 /var/www/pterodactyl/storage

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
info "Nginx configured."

# =============================================================
#  WAIT FOR PANEL
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
#  CREATE CLIENT ACCOUNT
# =============================================================
section "Creating Client Account"

cd /var/www/pterodactyl
sudo php artisan p:user:make \
  --email="$CLIENT_EMAIL" \
  --username="$CLIENT_USERNAME" \
  --name-first="$CLIENT_FIRST" \
  --name-last="$CLIENT_LAST" \
  --password="$CLIENT_PASS" \
  --admin=1 \
  --no-interaction \
  || warn "Client account creation failed — create manually in panel at http://$PUBLIC_IP"

info "Client account created."

# =============================================================
#  GET API KEY (manual step)
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

sudo mkdir -p /etc/fiendishhosting
echo "$API_KEY" | sudo tee /etc/fiendishhosting/api.key > /dev/null
sudo chmod 600 /etc/fiendishhosting/api.key
info "API key saved."

PANEL_URL="http://$PUBLIC_IP"
AUTH_HEADER="Authorization: Bearer $API_KEY"
ACCEPT_HEADER="Accept: application/vnd.pterodactyl.v1+json"
CONTENT_HEADER="Content-Type: application/json"

ptero_api() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"
  if [ -n "$data" ]; then
    curl -fsSL -X "$method" \
      -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -H "$CONTENT_HEADER" \
      -d "$data" "$PANEL_URL/api/application/$endpoint"
  else
    curl -fsSL -X "$method" \
      -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" \
      "$PANEL_URL/api/application/$endpoint"
  fi
}

# =============================================================
#  CREATE LOCATION
# =============================================================
section "Creating Location"
LOCATION_RESPONSE=$(ptero_api POST "locations" \
  '{"short":"us-east","long":"Oracle US East Ashburn"}')
LOCATION_ID=$(echo "$LOCATION_RESPONSE" | jq -r '.attributes.id // empty')
[ -z "$LOCATION_ID" ] && error "Failed to create location. Response: $LOCATION_RESPONSE"
info "Location created: $LOCATION_ID"

# =============================================================
#  CREATE NODE
# =============================================================
section "Creating Node"
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
info "Node created: $NODE_ID"

# =============================================================
#  CREATE ALLOCATIONS
# =============================================================
section "Creating Allocations"
ptero_api POST "nodes/$NODE_ID/allocations" \
  '{"ip":"0.0.0.0","ports":["25565","19132"]}' > /dev/null
info "Allocations added (25565, 19132)."

# =============================================================
#  CONFIGURE + START WINGS
# =============================================================
section "Configuring Wings"

DEPLOY_RESPONSE=$(ptero_api POST "nodes/$NODE_ID/configuration" "")
DEPLOY_TOKEN=$(echo "$DEPLOY_RESPONSE" | jq -r '.token // empty')

if [ -n "$DEPLOY_TOKEN" ]; then
  sudo wings configure \
    --panel-url "$PANEL_URL" \
    --token "$DEPLOY_TOKEN" \
    --node "$NODE_ID" \
    || error "Wings configure failed"
else
  warn "Could not get auto-deploy token — configure Wings manually from the panel."
fi

section "Starting Wings"
sudo systemctl enable wings
sudo systemctl start wings
sleep 5

if sudo systemctl is-active --quiet wings; then
  info "Wings is running."
else
  error "Wings failed to start. Check: sudo journalctl -u wings -n 50"
fi

# Save state for starter.sh
echo "$NODE_ID"    | sudo tee /etc/fiendishhosting/node.id    > /dev/null
echo "$PUBLIC_IP"  | sudo tee /etc/fiendishhosting/panel.url  > /dev/null
echo "$API_KEY"    | sudo tee /etc/fiendishhosting/api.key    > /dev/null
sudo chmod 600 /etc/fiendishhosting/api.key

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
echo ""
echo -e "${YELLOW}  *** SEND THIS TO CLIENT VIA DISCORD ***${NC}"
echo -e "${YELLOW}  Panel URL:  http://$PUBLIC_IP${NC}"
echo -e "${YELLOW}  Username:   $CLIENT_USERNAME${NC}"
echo -e "${YELLOW}  Password:   $CLIENT_PASS${NC}"
echo -e "${YELLOW}  Tell them to change their password on first login.${NC}"
echo ""
echo -e "${YELLOW}  REMEMBER AT HANDOFF:${NC}"
echo "  1. Verify client can log in"
echo "  2. Delete dcfiendish account from panel"
echo "  3. Verify you can no longer log in"
echo ""
echo -e "${RED}  Next step: run starter.sh${NC}"
echo ""
