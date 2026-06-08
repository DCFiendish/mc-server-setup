#!/bin/bash

# =============================================================
#  bmwoo Friend Group Server Setup
#  Purpur 1.21.11 | Oracle A1 | Ubuntu 22.04 ARM64
#  GitHub: DCFiendish
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

USER_AGENT="DCFiendish-mc-setup/1.0 (https://github.com/DCFiendish)"
MC_VERSION="1.21.11"
SOFTWARE="purpur"
RAM="8G"
PLUGINS_DIR="/opt/minecraft/server/plugins"

# Helper: download a plugin with validation
# Usage: dl_plugin <url> <output_path> <name>
dl_plugin() {
  local url="$1"
  local out="$2"
  local name="$3"
  if [ -z "$url" ]; then
    warn "  $name: download URL not found — install manually."
    return
  fi
  sudo -u minecraft curl -fsSL -A "$USER_AGENT" "$url" -o "$out" \
    || warn "  $name: download failed — install manually."
  info "  $name downloaded."
}

echo ""
echo "========================================="
echo "   bmwoo Friend Group Server Setup       "
echo "   Purpur ${MC_VERSION} | Full Stack      "
echo "========================================="
echo ""

# World seed
read -p "World seed (leave blank for random): " WORLD_SEED

echo ""
info "Starting setup. This will take a few minutes..."
echo ""

# =============================================================
#  SYSTEM UPDATE
# =============================================================
section "System Update"

sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y curl wget jq ufw unzip tmux
info "System updated."

# =============================================================
#  JAVA 21 (Eclipse Temurin)
# =============================================================
section "Java 21"

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
info "Java 21 Temurin installed."

# =============================================================
#  MINECRAFT USER & DIRECTORIES
# =============================================================
section "Minecraft User & Directories"

if ! id "minecraft" &>/dev/null; then
  sudo useradd -r -m -U -d /opt/minecraft -s /usr/sbin/nologin minecraft
fi
sudo mkdir -p /opt/minecraft/server/plugins
sudo chown -R minecraft:minecraft /opt/minecraft
info "minecraft user and directories ready."

# =============================================================
#  DOWNLOAD PURPUR
# =============================================================
section "Downloading Purpur ${MC_VERSION}"

HTTP_CODE=$(sudo -u minecraft curl -fsSL -A "$USER_AGENT" \
  -w "%{http_code}" \
  -o /opt/minecraft/server/server.jar \
  "https://api.purpurmc.org/v2/purpur/${MC_VERSION}/latest/download")

if [ "$HTTP_CODE" != "200" ]; then
  error "Failed to download Purpur ${MC_VERSION} (HTTP $HTTP_CODE). Check the version is valid."
fi

# Verify it's actually a JAR
if ! file /opt/minecraft/server/server.jar | grep -q "Java archive"; then
  error "Downloaded file is not a valid JAR. Check Purpur API for version ${MC_VERSION}."
fi

info "Purpur ${MC_VERSION} downloaded and verified."

# =============================================================
#  EULA
# =============================================================
echo "eula=true" | sudo tee /opt/minecraft/server/eula.txt > /dev/null
info "EULA accepted."

# =============================================================
#  SERVER.PROPERTIES
# =============================================================
section "Server Config"

if [ -n "$WORLD_SEED" ]; then
  SEED_LINE="level-seed=$WORLD_SEED"
else
  SEED_LINE="level-seed="
fi

sudo tee /opt/minecraft/server/server.properties > /dev/null <<EOF
#Minecraft server properties
online-mode=true
server-port=25565
max-players=20
view-distance=12
simulation-distance=8
$SEED_LINE
white-list=true
enforce-whitelist=true
spawn-protection=16
difficulty=normal
gamemode=survival
pvp=true
enable-command-block=true
motd=bmwoo's Server
EOF

sudo chown minecraft:minecraft /opt/minecraft/server/server.properties
info "server.properties written."

# =============================================================
#  START SCRIPT (Aikar flags, 8G heap)
# =============================================================
section "Start Script"

sudo tee /opt/minecraft/server/start.sh > /dev/null <<'EOF'
#!/bin/bash
cd /opt/minecraft/server
java -Xms8G -Xmx8G \
  -XX:+UseG1GC \
  -XX:+ParallelRefProcEnabled \
  -XX:MaxGCPauseMillis=200 \
  -XX:+UnlockExperimentalVMOptions \
  -XX:+DisableExplicitGC \
  -XX:G1NewSizePercent=30 \
  -XX:G1MaxNewSizePercent=40 \
  -XX:G1HeapRegionSize=8M \
  -XX:G1ReservePercent=15 \
  -XX:G1HeapWastePercent=5 \
  -XX:G1MixedGCCountTarget=4 \
  -XX:InitiatingHeapOccupancyPercent=20 \
  -XX:G1MixedGCLiveThresholdPercent=90 \
  -XX:G1RSetUpdatingPauseTimePercent=5 \
  -XX:SurvivorRatio=32 \
  -XX:+PerfDisableSharedMem \
  -XX:MaxTenuringThreshold=1 \
  -Dusing.aikars.flags=https://mcflags.emc.gs \
  -Daikars.new.flags=true \
  -jar server.jar --nogui
EOF

sudo chmod +x /opt/minecraft/server/start.sh
sudo chown minecraft:minecraft /opt/minecraft/server/start.sh
info "start.sh written with Aikar flags (8G heap tuned)."

# =============================================================
#  PLUGINS
# =============================================================
section "Downloading Plugins"

# --- Geyser (Bedrock support) ---
dl_plugin \
  "https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot" \
  "$PLUGINS_DIR/Geyser-Spigot.jar" \
  "Geyser"

# --- Floodgate (Bedrock auth) ---
dl_plugin \
  "https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot" \
  "$PLUGINS_DIR/floodgate-spigot.jar" \
  "Floodgate"

# --- BedrockConnect (console DNS bypass) ---
BC_URL=$(curl -fsSL -A "$USER_AGENT" "https://api.github.com/repos/Pugmatt/BedrockConnect/releases/latest" \
  | jq -r '.assets[] | select(.name | endswith(".jar")) | .browser_download_url' | head -1 || echo "")
dl_plugin "$BC_URL" "$PLUGINS_DIR/BedrockConnect.jar" "BedrockConnect"

# --- Grim Anticheat (via Modrinth) ---
GRIM_URL=$(curl -fsSL -A "$USER_AGENT" \
  "https://api.modrinth.com/v2/project/grimac/version?loaders=[%22paper%22]&game_versions=[%221.21.11%22]" \
  | jq -r '.[0].files[] | select(.primary==true) | .url' 2>/dev/null || echo "")
if [ -z "$GRIM_URL" ]; then
  GRIM_URL=$(curl -fsSL -A "$USER_AGENT" "https://api.modrinth.com/v2/project/grimac/version" \
    | jq -r '.[0].files[] | select(.primary==true) | .url' 2>/dev/null || echo "")
fi
dl_plugin "$GRIM_URL" "$PLUGINS_DIR/GrimAC.jar" "Grim Anticheat"

# --- EssentialsX ---
ESS_URL=$(curl -fsSL -A "$USER_AGENT" "https://api.github.com/repos/EssentialsX/Essentials/releases/latest" \
  | jq -r '.assets[] | select(.name | startswith("EssentialsX-") and endswith(".jar")) | .browser_download_url' \
  | head -1 || echo "")
dl_plugin "$ESS_URL" "$PLUGINS_DIR/EssentialsX.jar" "EssentialsX"

# --- LuckPerms ---
LP_URL=$(curl -fsSL -A "$USER_AGENT" "https://api.github.com/repos/LuckPerms/LuckPerms/releases/latest" \
  | jq -r '.assets[] | select(.name | startswith("LuckPerms-Bukkit")) | .browser_download_url' \
  | head -1 || echo "")
dl_plugin "$LP_URL" "$PLUGINS_DIR/LuckPerms.jar" "LuckPerms"

# --- CoreProtect (via Modrinth) ---
CP_URL=$(curl -fsSL -A "$USER_AGENT" \
  "https://api.modrinth.com/v2/project/coreprotect/version?loaders=[%22paper%22]" \
  | jq -r '.[0].files[] | select(.primary==true) | .url' 2>/dev/null || echo "")
dl_plugin "$CP_URL" "$PLUGINS_DIR/CoreProtect.jar" "CoreProtect"

# --- Graves (via Modrinth) ---
GRAVES_URL=$(curl -fsSL -A "$USER_AGENT" \
  "https://api.modrinth.com/v2/project/graves/version?loaders=[%22paper%22]" \
  | jq -r '.[0].files[] | select(.primary==true) | .url' 2>/dev/null || echo "")
dl_plugin "$GRAVES_URL" "$PLUGINS_DIR/Graves.jar" "Graves"

# --- Chunky (world pre-gen) ---
CHUNKY_URL=$(curl -fsSL -A "$USER_AGENT" \
  "https://api.modrinth.com/v2/project/chunky/version?loaders=[%22bukkit%22]" \
  | jq -r '.[0].files[] | select(.primary==true) | .url' 2>/dev/null || echo "")
dl_plugin "$CHUNKY_URL" "$PLUGINS_DIR/Chunky.jar" "Chunky"

# --- Spark (performance profiler) ---
dl_plugin \
  "https://ci.lucko.me/job/spark/lastSuccessfulBuild/artifact/spark-bukkit/build/libs/spark-bukkit.jar" \
  "$PLUGINS_DIR/spark.jar" \
  "Spark"

# --- DriveBackupV2 ---
DRIVE_URL=$(curl -fsSL -A "$USER_AGENT" \
  "https://api.github.com/repos/MinIO4/DriveBackupV2/releases/latest" \
  | jq -r '.assets[] | select(.name | endswith(".jar")) | .browser_download_url' \
  | head -1 || echo "")
dl_plugin "$DRIVE_URL" "$PLUGINS_DIR/DriveBackupV2.jar" "DriveBackupV2"

# --- TAB (player list) ---
TAB_URL=$(curl -fsSL -A "$USER_AGENT" "https://api.github.com/repos/NEZNAMY/TAB/releases/latest" \
  | jq -r '.assets[] | select(.name | endswith(".jar") and (contains("TAB") or contains("tab"))) | .browser_download_url' \
  | head -1 || echo "")
dl_plugin "$TAB_URL" "$PLUGINS_DIR/TAB.jar" "TAB"

# --- Multiverse-Core ---
MV_URL=$(curl -fsSL -A "$USER_AGENT" \
  "https://api.github.com/repos/Multiverse/Multiverse-Core/releases/latest" \
  | jq -r '.assets[] | select(.name | endswith(".jar")) | .browser_download_url' \
  | head -1 || echo "")
dl_plugin "$MV_URL" "$PLUGINS_DIR/Multiverse-Core.jar" "Multiverse-Core"

# --- FarmLimiter ---
FL_URL=$(curl -fsSL -A "$USER_AGENT" \
  "https://api.modrinth.com/v2/project/farmlimiter/version?loaders=[%22paper%22]" \
  | jq -r '.[0].files[] | select(.primary==true) | .url' 2>/dev/null || echo "")
dl_plugin "$FL_URL" "$PLUGINS_DIR/FarmLimiter.jar" "FarmLimiter"

info "All plugins downloaded."

# =============================================================
#  FIREWALL
# =============================================================
section "Firewall (UFW)"

sudo ufw allow 22/tcp    comment 'SSH'
sudo ufw allow 25565/tcp comment 'Minecraft Java'
sudo ufw allow 19132/tcp comment 'Geyser Bedrock TCP'
sudo ufw allow 19132/udp comment 'Geyser Bedrock UDP'
sudo ufw --force enable
info "Firewall configured."
warn "Remember to also open these ports in your OCI Security List."
warn "Netdata (port 19999) is intentionally NOT opened — add your IP manually in OCI if needed."

# =============================================================
#  FAIL2BAN
# =============================================================
section "Fail2Ban"
sudo apt-get install -y fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
info "Fail2Ban installed and running."

# =============================================================
#  NETDATA (server monitoring)
# =============================================================
section "Netdata"
curl -fsSL https://get.netdata.cloud/kickstart.sh > /tmp/netdata-kickstart.sh
sudo sh /tmp/netdata-kickstart.sh --non-interactive --dont-start-it 2>/dev/null || \
  warn "Netdata install failed — skip or install manually."
sudo systemctl enable netdata 2>/dev/null || true
sudo systemctl start netdata 2>/dev/null || true
info "Netdata installed (port 19999 — restrict to your IP in OCI Security List before opening)."

# =============================================================
#  SYSTEMD SERVICE
# =============================================================
section "Systemd Service"

sudo tee /etc/systemd/system/minecraft.service > /dev/null <<EOF
[Unit]
Description=bmwoo Minecraft Server
After=network.target

[Service]
User=minecraft
WorkingDirectory=/opt/minecraft/server
ExecStartPre=/usr/bin/test -f /opt/minecraft/server/server.jar
ExecStart=/opt/minecraft/server/start.sh
ExecStop=/bin/kill -s SIGINT \$MAINPID
TimeoutStopSec=120
SuccessExitStatus=143
Restart=on-failure
RestartSec=10
StandardInput=null

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable minecraft
info "Systemd service created and enabled."

# =============================================================
#  FIRST RUN (generates world + config files)
# =============================================================
section "First Run"
info "Running server for 120 seconds to generate configs (including Geyser)..."
sudo -u minecraft timeout 120 bash /opt/minecraft/server/start.sh || true
info "First run complete. World and config files generated."

# =============================================================
#  CONFIGURE GEYSER
# =============================================================
section "Configuring Geyser"

GEYSER_CONFIG="$PLUGINS_DIR/Geyser-Spigot/config.yml"

if [ -f "$GEYSER_CONFIG" ]; then
  sudo sed -i 's/auth-type: online/auth-type: floodgate/' "$GEYSER_CONFIG"
  info "Geyser auth-type set to floodgate."
else
  warn "Geyser config not found — server may need more time to initialise."
  warn "Once server is running, set auth-type: floodgate manually in:"
  warn "  $GEYSER_CONFIG"
fi

# =============================================================
#  DONE
# =============================================================

PUBLIC_IP=$(curl -fsSL https://api.ipify.org 2>/dev/null || echo "unknown")

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}   bmwoo Server Setup Complete!          ${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "  Software:  Purpur ${MC_VERSION}"
echo "  RAM:       ${RAM} / 24GB"
if [ -n "$WORLD_SEED" ]; then
  echo "  Seed:      $WORLD_SEED"
else
  echo "  Seed:      Random"
fi
echo "  Public IP: $PUBLIC_IP"
echo ""
echo -e "${YELLOW}  OCI Security List — open these ports:${NC}"
echo "    TCP 25565  (Minecraft Java)"
echo "    TCP+UDP 19132  (Geyser Bedrock)"
echo "    TCP 19999  (Netdata — restrict to your IP only)"
echo ""
echo -e "${YELLOW}  Manual steps still needed:${NC}"
echo "  1) Open ports above in OCI Console Security List"
echo "  2) Configure DriveBackupV2 with Google/OneDrive credentials"
echo "  3) Run Chunky pre-gen once server is running:"
echo "       /chunky world world"
echo "       /chunky radius 2000"
echo "       /chunky start"
echo "  4) Lock Nether/End via Multiverse:"
echo "       /mv create world_nether NETHER"
echo "       /mv modify set allowentry false world_nether"
echo "  5) Add players: /whitelist add <playername>"
echo "  6) Run Pterodactyl setup: bash pterodactyl-setup.sh"
echo ""
echo -e "${GREEN}  Start:  sudo systemctl start minecraft${NC}"
echo -e "${GREEN}  Logs:   sudo journalctl -u minecraft -f${NC}"
echo ""
