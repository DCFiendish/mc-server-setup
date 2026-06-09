#!/bin/bash

# =============================================================
#  FiendishHosting — Starter Package Setup
#  Oracle A1 (Ubuntu 22.04 ARM64)
#  Run AFTER pterodactyl-setup.sh
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

USER_AGENT="DCFiendish-mc-setup/2.0 (https://github.com/DCFiendish)"

dl_plugin() {
  local url="$1"
  local out="$2"
  local name="$3"
  if [ -z "$url" ]; then
    warn "  $name: download URL not found — install manually."
    return
  fi
  curl -fsSL -A "$USER_AGENT" "$url" -o "$out" \
    || warn "  $name: download failed — install manually."
  info "  $name downloaded."
}

# =============================================================
#  CHECK PREREQUISITES
# =============================================================

[ ! -f /etc/fiendishhosting/api.key ] && error "API key not found. Run pterodactyl-setup.sh first."
[ ! -f /etc/fiendishhosting/node.id ]  && error "Node ID not found. Run pterodactyl-setup.sh first."
[ ! -f /etc/fiendishhosting/panel.url ] && error "Panel URL not found. Run pterodactyl-setup.sh first."

API_KEY=$(cat /etc/fiendishhosting/api.key)
NODE_ID=$(cat /etc/fiendishhosting/node.id)
PANEL_URL="http://$(cat /etc/fiendishhosting/panel.url)"
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
      -d "$data" \
      "$PANEL_URL/api/application/$endpoint"
  else
    curl -fsSL -X "$method" \
      -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" \
      "$PANEL_URL/api/application/$endpoint"
  fi
}

# =============================================================
#  QUESTIONS
# =============================================================

echo ""
echo "========================================="
echo "   FiendishHosting — Starter Package     "
echo "========================================="
echo ""

# Server name
read -p "Server name (e.g. SurvivalSMP): " SERVER_NAME
[ -z "$SERVER_NAME" ] && error "Server name is required"

# Client email (for panel ownership)
read -p "Client email (must match their Pterodactyl account): " CLIENT_EMAIL
[ -z "$CLIENT_EMAIL" ] && error "Client email is required"

# Software
echo ""
echo "Server software:"
echo "  1) Paper"
echo "  2) Purpur"
read -p "Choose (1/2): " SOFTWARE_CHOICE
case $SOFTWARE_CHOICE in
  1) SOFTWARE="paper"  ;;
  2) SOFTWARE="purpur" ;;
  *) error "Invalid choice." ;;
esac

# Version
echo ""
echo "Minecraft version:"
echo "  1) 1.21.11  (latest 1.21.x)"
echo "  2) 1.21.4"
echo "  3) 1.21.1"
echo "  4) 1.20.6"
echo "  5) 1.20.4"
echo "  6) 1.20.1"
echo "  7) 26.1.2   (latest 2026)"
read -p "Choose (1-7): " VERSION_CHOICE
case $VERSION_CHOICE in
  1) MC_VERSION="1.21.11" ;;
  2) MC_VERSION="1.21.4"  ;;
  3) MC_VERSION="1.21.1"  ;;
  4) MC_VERSION="1.20.6"  ;;
  5) MC_VERSION="1.20.4"  ;;
  6) MC_VERSION="1.20.1"  ;;
  7) MC_VERSION="26.1.2"  ;;
  *) error "Invalid choice." ;;
esac

# World seed
echo ""
read -p "World seed (leave blank for random): " WORLD_SEED

# Optional plugins
echo ""
echo "Optional plugins (y/n for each):"
read -p "  EssentialsX?   " INSTALL_ESSENTIALS
read -p "  LuckPerms?     " INSTALL_LUCKPERMS
read -p "  GrimAC?        " INSTALL_GRIM
read -p "  TAB?           " INSTALL_TAB
read -p "  GravesX?       " INSTALL_GRAVES
read -p "  Multiverse?    " INSTALL_MULTIVERSE
read -p "  Chunky?        " INSTALL_CHUNKY
read -p "  ViaVersion?    " INSTALL_VIA
read -p "  Geyser+Floodgate (Bedrock crossplay)? " INSTALL_GEYSER

echo ""
info "Starting Starter setup: $SOFTWARE $MC_VERSION — $SERVER_NAME"
echo ""

RAM="8G"

# =============================================================
#  SYSTEM UPDATE + JAVA
# =============================================================
section "System Update"

sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y curl wget jq ufw unzip fail2ban

sudo systemctl enable fail2ban
sudo systemctl start fail2ban
info "Fail2Ban installed and running."

section "Installing Java 21"

sudo apt-get install -y wget apt-transport-https gpg

wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public \
  | gpg --dearmor \
  | sudo tee /usr/share/keyrings/adoptium.gpg > /dev/null

echo "deb [signed-by=/usr/share/keyrings/adoptium.gpg] \
https://packages.adoptium.net/artifactory/deb \
$(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" \
  | sudo tee /etc/apt/sources.list.d/adoptium.list

sudo apt-get update -y
sudo apt-get install -y temurin-21-jdk
java -version
info "Java 21 installed."

# =============================================================
#  DOWNLOAD SERVER JAR TO TEMP
# =============================================================
section "Downloading Server Jar"

TMPDIR=$(mktemp -d)
PLUGINS_TMP="$TMPDIR/plugins"
mkdir -p "$PLUGINS_TMP"

info "Downloading $SOFTWARE $MC_VERSION..."

if [ "$SOFTWARE" = "paper" ]; then
  BUILDS_JSON=$(curl -fsSL -A "$USER_AGENT" \
    "https://fill.papermc.io/v3/projects/paper/versions/${MC_VERSION}/builds")

  if echo "$BUILDS_JSON" | jq -e '.ok == false' > /dev/null 2>&1; then
    error "Paper API error: $(echo "$BUILDS_JSON" | jq -r '.message')"
  fi

  JAR_URL=$(echo "$BUILDS_JSON" | jq -r \
    'first(.[] | select(.channel == "STABLE") | .downloads."server:default".url) // "null"')

  [ "$JAR_URL" = "null" ] || [ -z "$JAR_URL" ] && \
    error "No stable Paper build found for $MC_VERSION."

  curl -fsSL -A "$USER_AGENT" -o "$TMPDIR/server.jar" "$JAR_URL"

elif [ "$SOFTWARE" = "purpur" ]; then
  HTTP_CODE=$(curl -fsSL -A "$USER_AGENT" \
    -w "%{http_code}" \
    -o "$TMPDIR/server.jar" \
    "https://api.purpurmc.org/v2/purpur/${MC_VERSION}/latest/download")

  [ "$HTTP_CODE" != "200" ] && \
    error "Failed to download Purpur $MC_VERSION (HTTP $HTTP_CODE)"
fi

file "$TMPDIR/server.jar" | grep -q "Java archive" || \
  error "Downloaded file is not a valid JAR."

info "Server jar downloaded and verified."

# =============================================================
#  WRITE SERVER.PROPERTIES
# =============================================================
section "Server Properties"

if [ -n "$WORLD_SEED" ]; then
  SEED_LINE="level-seed=$WORLD_SEED"
else
  SEED_LINE="level-seed="
fi

cat > "$TMPDIR/server.properties" << EOF
online-mode=true
server-port=25565
max-players=100
view-distance=10
simulation-distance=6
$SEED_LINE
white-list=false
enforce-whitelist=false
spawn-protection=0
difficulty=normal
gamemode=survival
pvp=true
enable-command-block=false
motd=$SERVER_NAME
EOF

# Accept EULA
echo "eula=true" > "$TMPDIR/eula.txt"

# =============================================================
#  DOWNLOAD PLUGINS
# =============================================================
section "Downloading Plugins"

# Spark (always included)
dl_plugin \
  "https://ci.lucko.me/job/spark/lastSuccessfulBuild/artifact/spark-bukkit/build/libs/spark-bukkit.jar" \
  "$PLUGINS_TMP/spark.jar" \
  "Spark"

# DriveBackupV2 (always included)
dl_plugin \
  "https://github.com/MaxMaeder/DriveBackupV2/releases/latest/download/DriveBackupV2.jar" \
  "$PLUGINS_TMP/DriveBackupV2.jar" \
  "DriveBackupV2"

# AntiXray is built into Paper/Purpur config — no plugin needed

# Optional: EssentialsX
if [[ "$INSTALL_ESSENTIALS" =~ ^[Yy]$ ]]; then
  ESS_URL=$(curl -fsSL -A "$USER_AGENT" \
    "https://api.github.com/repos/EssentialsX/Essentials/releases/latest" \
    | jq -r '.assets[] | select(.name | startswith("EssentialsX-") and endswith(".jar")) | .browser_download_url' \
    | head -1 || echo "")
  dl_plugin "$ESS_URL" "$PLUGINS_TMP/EssentialsX.jar" "EssentialsX"
fi

# Optional: LuckPerms
if [[ "$INSTALL_LUCKPERMS" =~ ^[Yy]$ ]]; then
  warn "LuckPerms: GitHub URL unreliable — download manually from luckperms.net and add via panel file manager."
fi

# Optional: GrimAC
if [[ "$INSTALL_GRIM" =~ ^[Yy]$ ]]; then
  GRIM_URL=$(curl -fsSL --globoff -A "$USER_AGENT" \
    "https://api.modrinth.com/v2/project/AC/version?loaders=[%22paper%22]" \
    | jq -r '.[0].files[] | select(.primary==true) | .url' || echo "")
  dl_plugin "$GRIM_URL" "$PLUGINS_TMP/GrimAC.jar" "GrimAC"
fi

# Optional: TAB
if [[ "$INSTALL_TAB" =~ ^[Yy]$ ]]; then
  TAB_URL=$(curl -fsSL -A "$USER_AGENT" \
    "https://api.github.com/repos/NEZNAMY/TAB/releases/latest" \
    | jq -r '.assets[] | select(.name | endswith(".jar")) | .browser_download_url' \
    | head -1 || echo "")
  dl_plugin "$TAB_URL" "$PLUGINS_TMP/TAB.jar" "TAB"
fi

# Optional: GravesX
if [[ "$INSTALL_GRAVES" =~ ^[Yy]$ ]]; then
  GRAVES_URL="https://hangar.papermc.io/api/v1/projects/GravesX/versions/4.9.10.10/PAPER/download"
  dl_plugin "$GRAVES_URL" "$PLUGINS_TMP/GravesX.jar" "GravesX"
fi

# Optional: Multiverse-Core
if [[ "$INSTALL_MULTIVERSE" =~ ^[Yy]$ ]]; then
  MV_URL=$(curl -fsSL -A "$USER_AGENT" \
    "https://api.github.com/repos/Multiverse/Multiverse-Core/releases/latest" \
    | jq -r '.assets[] | select(.name | endswith(".jar")) | .browser_download_url' \
    | head -1 || echo "")
  dl_plugin "$MV_URL" "$PLUGINS_TMP/Multiverse-Core.jar" "Multiverse-Core"
fi

# Optional: Chunky
if [[ "$INSTALL_CHUNKY" =~ ^[Yy]$ ]]; then
  CHUNKY_URL=$(curl -fsSL --globoff -A "$USER_AGENT" \
    "https://api.modrinth.com/v2/project/chunky/version?loaders=[%22paper%22]" \
    | jq -r '.[0].files[] | select(.primary==true) | .url' || echo "")
  dl_plugin "$CHUNKY_URL" "$PLUGINS_TMP/Chunky.jar" "Chunky"
fi

# Optional: ViaVersion
if [[ "$INSTALL_VIA" =~ ^[Yy]$ ]]; then
  dl_plugin \
    "https://github.com/ViaVersion/ViaVersion/releases/download/5.9.1/ViaVersion-5.9.1.jar" \
    "$PLUGINS_TMP/ViaVersion.jar" \
    "ViaVersion"
fi

# Optional: Geyser + Floodgate
if [[ "$INSTALL_GEYSER" =~ ^[Yy]$ ]]; then
  dl_plugin \
    "https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot" \
    "$PLUGINS_TMP/Geyser-Spigot.jar" \
    "Geyser"
  dl_plugin \
    "https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot" \
    "$PLUGINS_TMP/floodgate-spigot.jar" \
    "Floodgate"
  # ViaVersion required with Geyser
  dl_plugin \
    "https://github.com/ViaVersion/ViaVersion/releases/download/5.9.1/ViaVersion-5.9.1.jar" \
    "$PLUGINS_TMP/ViaVersion.jar" \
    "ViaVersion (required for Geyser)"

  # Open Geyser port in iptables
  sudo iptables -I INPUT -p udp --dport 19132 -j ACCEPT
  sudo iptables -I INPUT -p tcp --dport 19132 -j ACCEPT
  info "Geyser ports opened in iptables. Also open UDP+TCP 19132 in OCI Security List."
fi

info "All plugins downloaded."

# =============================================================
#  FIND CLIENT USER ID IN PANEL
# =============================================================
section "Finding Client Panel User"

info "Looking up client user: $CLIENT_EMAIL..."
USERS_RESPONSE=$(ptero_api GET "users?filter[email]=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$CLIENT_EMAIL'))")")
CLIENT_USER_ID=$(echo "$USERS_RESPONSE" | jq -r '.data[] | select(.attributes.email == "'"$CLIENT_EMAIL"'") | .attributes.id' | head -1)

[ -z "$CLIENT_USER_ID" ] && error "Client user not found in panel. Make sure pterodactyl-setup.sh was run with this email."
info "Client user ID: $CLIENT_USER_ID"

# =============================================================
#  FIND NEST + EGG IDS
# =============================================================
section "Finding Nest and Egg"

info "Finding Minecraft nest and $SOFTWARE egg..."
NESTS_RESPONSE=$(ptero_api GET "nests?include=eggs")

NEST_ID=$(echo "$NESTS_RESPONSE" | jq -r '.data[] | select(.attributes.name == "Minecraft") | .attributes.id' | head -1)
[ -z "$NEST_ID" ] && error "Minecraft nest not found. Check panel has default eggs installed."
info "Minecraft nest ID: $NEST_ID"

if [ "$SOFTWARE" = "paper" ]; then
  EGG_SEARCH="Paper"
else
  EGG_SEARCH="Purpur"
fi

EGG_ID=$(echo "$NESTS_RESPONSE" | \
  jq -r --arg nest "$NEST_ID" --arg egg "$EGG_SEARCH" \
  '.data[] | select(.attributes.id == ($nest | tonumber)) | .relationships.eggs.data[] | select(.attributes.name | test($egg; "i")) | .attributes.id' \
  | head -1)

# Fallback: if Purpur egg not found, use Paper egg
if [ -z "$EGG_ID" ] && [ "$SOFTWARE" = "purpur" ]; then
  warn "Purpur egg not found, using Paper egg (will still work with Purpur jar)"
  EGG_ID=$(echo "$NESTS_RESPONSE" | \
    jq -r --arg nest "$NEST_ID" \
    '.data[] | select(.attributes.id == ($nest | tonumber)) | .relationships.eggs.data[] | select(.attributes.name | test("Paper"; "i")) | .attributes.id' \
    | head -1)
fi

[ -z "$EGG_ID" ] && error "Could not find a suitable egg. Check panel has Minecraft eggs installed."
info "Egg ID: $EGG_ID"

# =============================================================
#  FIND ALLOCATION ID
# =============================================================
section "Finding Allocation"

info "Finding port 25565 allocation on node $NODE_ID..."
ALLOC_RESPONSE=$(ptero_api GET "nodes/$NODE_ID/allocations")
ALLOC_ID=$(echo "$ALLOC_RESPONSE" | jq -r '.data[] | select(.attributes.port == 25565 and .attributes.assigned == false) | .attributes.id' | head -1)

[ -z "$ALLOC_ID" ] && error "No unassigned port 25565 allocation found. Check node allocations in panel."
info "Allocation ID: $ALLOC_ID"

# =============================================================
#  CREATE SERVER IN PANEL
# =============================================================
section "Creating Server in Pterodactyl"

info "Creating server: $SERVER_NAME..."
SERVER_RESPONSE=$(ptero_api POST "servers" \
  "{
    \"name\": \"$SERVER_NAME\",
    \"user\": $CLIENT_USER_ID,
    \"egg\": $EGG_ID,
    \"docker_image\": \"ghcr.io/pterodactyl/yolks:java_21\",
    \"startup\": \"java -Xms128M -XX:MaxRAMPercentage=95.0 -Dterminal.jline=false -Dterminal.ansi=true -jar {{SERVER_JARFILE}}\",
    \"environment\": {
      \"MINECRAFT_VERSION\": \"$MC_VERSION\",
      \"SERVER_JARFILE\": \"server.jar\",
      \"BUILD_NUMBER\": \"latest\"
    },
    \"limits\": {
      \"memory\": 8192,
      \"swap\": 0,
      \"disk\": 50000,
      \"io\": 500,
      \"cpu\": 0
    },
    \"feature_limits\": {
      \"databases\": 0,
      \"allocations\": 1,
      \"backups\": 0
    },
    \"allocation\": {
      \"default\": $ALLOC_ID
    }
  }")

SERVER_UUID=$(echo "$SERVER_RESPONSE" | jq -r '.attributes.uuid // empty')
SERVER_ID=$(echo "$SERVER_RESPONSE" | jq -r '.attributes.id // empty')

[ -z "$SERVER_UUID" ] && error "Failed to create server. Response: $SERVER_RESPONSE"
info "Server created. UUID: $SERVER_UUID"

# =============================================================
#  WAIT FOR PTERODACTYL TO FINISH INSTALLING SERVER
# =============================================================
section "Waiting for Server Installation"

info "Waiting for Pterodactyl to finish server install..."
for i in {1..30}; do
  STATUS=$(ptero_api GET "servers/$SERVER_ID" | jq -r '.attributes.status // "installing"')
  if [ "$STATUS" = "null" ] || [ -z "$STATUS" ]; then
    info "Server installation complete."
    break
  fi
  sleep 10
  echo -n "."
done
echo ""

VOLUME_PATH="/var/lib/pterodactyl/volumes/$SERVER_UUID"
[ ! -d "$VOLUME_PATH" ] && error "Volume directory not found at $VOLUME_PATH"
info "Volume directory: $VOLUME_PATH"

# =============================================================
#  COPY SERVER FILES INTO PTERODACTYL VOLUME
# =============================================================
section "Copying Server Files"

info "Copying server.jar..."
sudo cp "$TMPDIR/server.jar" "$VOLUME_PATH/server.jar"

info "Copying server.properties and eula.txt..."
sudo cp "$TMPDIR/server.properties" "$VOLUME_PATH/server.properties"
sudo cp "$TMPDIR/eula.txt" "$VOLUME_PATH/eula.txt"

info "Copying plugins..."
sudo mkdir -p "$VOLUME_PATH/plugins"
sudo cp -r "$PLUGINS_TMP"/. "$VOLUME_PATH/plugins/"

info "Fixing permissions..."
sudo chown -R pterodactyl:pterodactyl "$VOLUME_PATH"

# Cleanup temp
rm -rf "$TMPDIR"
info "Files copied."

# =============================================================
#  CONFIGURE DRIVEBACKUPV2
# =============================================================
section "Configuring DriveBackupV2"

# Wait for first server start to generate plugin configs
# We'll write the config after first run — handled in handoff notes

# =============================================================
#  OPEN IPTABLES FOR MINECRAFT
# =============================================================
section "Firewall"

sudo iptables -I INPUT -p tcp --dport 25565 -j ACCEPT
sudo iptables -I INPUT -p udp --dport 25565 -j ACCEPT
info "Port 25565 opened in iptables."
warn "Also open TCP 25565 in OCI Security List if not already done."

# =============================================================
#  START SERVER VIA PTERODACTYL
# =============================================================
section "Starting Server"

info "Starting server via Pterodactyl panel..."
# Use client API with admin key to send power action
curl -fsSL -X POST \
  -H "Authorization: Bearer $API_KEY" \
  -H "Accept: application/vnd.pterodactyl.v1+json" \
  -H "Content-Type: application/json" \
  -d '{"signal":"start"}' \
  "$PANEL_URL/api/client/servers/$SERVER_UUID/power" > /dev/null \
  || warn "Could not auto-start server — start manually from panel."

info "Server start signal sent."

# =============================================================
#  DONE
# =============================================================
section "Setup Complete"

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}   Starter Package Complete!             ${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "  Server Name:  $SERVER_NAME"
echo "  Software:     $SOFTWARE $MC_VERSION"
echo "  Panel URL:    $PANEL_URL"
echo "  Client login: $CLIENT_EMAIL"
echo "  Server IP:    $(cat /etc/fiendishhosting/panel.url):25565"
echo ""
echo -e "${YELLOW}  Post-setup steps:${NC}"
echo "  1. Open OCI Security List — TCP 25565$([ "${INSTALL_GEYSER:-n}" = y ] && echo ", TCP+UDP 19132" || true)"
echo "  2. Log into panel → server console → run: drivebackup linkaccount onedrive"
echo "  3. Send client the OneDrive auth link"
echo "  4. Verify server is running in panel"
echo "  5. Send client their Handoff.docx"
echo ""
echo -e "${RED}  HANDOFF — before you leave:${NC}"
echo "  1. Verify client can log into panel"
echo "  2. Admin → Users → delete dcfiendish"
echo "  3. Verify you can no longer log in"
echo ""
if [[ "${INSTALL_GEYSER:-n}" =~ ^[Yy]$ ]]; then
  echo -e "${YELLOW}  Geyser installed — also open UDP+TCP 19132 in OCI Security List${NC}"
  echo ""
fi
