#!/bin/bash

# =============================================================
#  bmwoo Friend Group Server Setup
#  Purpur 1.21.11 | Oracle A1 | Ubuntu 22.04 ARM64
#  GitHub: DCFiendish
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

USER_AGENT="DCFiendish-mc-setup/1.0 (https://github.com/DCFiendish)"
MC_VERSION="1.21.11"
SOFTWARE="purpur"
RAM="8G"
PLUGINS_DIR="/opt/minecraft/server/plugins"

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
sudo apt-get install -y curl wget jq ufw unzip screen
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
  sudo useradd -r -m -d /opt/minecraft -s /bin/bash minecraft
fi
sudo mkdir -p /opt/minecraft/server/plugins
sudo chown -R minecraft:minecraft /opt/minecraft
info "minecraft user and directories ready."

# =============================================================
#  DOWNLOAD PURPUR
# =============================================================
section "Downloading Purpur ${MC_VERSION}"

sudo -u minecraft curl -s \
  -o /opt/minecraft/server/server.jar \
  "https://api.purpurmc.org/v2/purpur/${MC_VERSION}/latest/download"
info "Purpur ${MC_VERSION} downloaded."

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
#  START SCRIPT (Aikar flags, >12GB variant)
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
  -XX:+AlwaysPreTouch \
  -XX:G1NewSizePercent=40 \
  -XX:G1MaxNewSizePercent=50 \
  -XX:G1HeapRegionSize=16M \
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
info "start.sh written with Aikar flags."

# =============================================================
#  PLUGINS
# =============================================================
section "Downloading Plugins"

# --- Geyser (Bedrock support) ---
sudo -u minecraft curl -s -L \
  "https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot" \
  -o "$PLUGINS_DIR/Geyser-Spigot.jar"
info "  Geyser downloaded."

# --- Floodgate (Bedrock auth) ---
sudo -u minecraft curl -s -L \
  "https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot" \
  -o "$PLUGINS_DIR/floodgate-spigot.jar"
info "  Floodgate downloaded."

# --- BedrockConnect (console DNS bypass) ---
BC_URL=$(curl -s "https://api.github.com/repos/Pugmatt/BedrockConnect/releases/latest" \
  | jq -r '.assets[] | select(.name | endswith(".jar")) | .browser_download_url' | head -1)
sudo -u minecraft curl -s -L "$BC_URL" -o "$PLUGINS_DIR/BedrockConnect.jar"
info "  BedrockConnect downloaded."

# --- Grim Anticheat (via Modrinth) ---
GRIM_URL=$(curl -s "https://api.modrinth.com/v2/project/grimac/version?loaders=[%22paper%22]&game_versions=[%221.21.11%22]" \
  | jq -r '.[0].files[] | select(.primary==true) | .url' 2>/dev/null || echo "")
if [ -z "$GRIM_URL" ]; then
  GRIM_URL=$(curl -s "https://api.modrinth.com/v2/project/grimac/version" \
    | jq -r '.[0].files[] | select(.primary==true) | .url')
fi
sudo -u minecraft curl -s -L "$GRIM_URL" -o "$PLUGINS_DIR/GrimAC.jar"
info "  Grim Anticheat downloaded."

# --- EssentialsX ---
ESS_URL=$(curl -s "https://api.github.com/repos/EssentialsX/Essentials/releases/latest" \
  | jq -r '.assets[] | select(.name | startswith("EssentialsX-") and endswith(".jar")) | .browser_download_url' | head -1)
sudo -u minecraft curl -s -L "$ESS_URL" -o "$PLUGINS_DIR/EssentialsX.jar"
info "  EssentialsX downloaded."

# --- LuckPerms ---
LP_URL=$(curl -s "https://api.github.com/repos/LuckPerms/LuckPerms/releases/latest" \
  | jq -r '.assets[] | select(.name | startswith("LuckPerms-Bukkit")) | .browser_download_url' | head -1)
sudo -u minecraft curl -s -L "$LP_URL" -o "$PLUGINS_DIR/LuckPerms.jar"
info "  LuckPerms downloaded."

# --- CoreProtect (via Modrinth) ---
CP_URL=$(curl -s "https://api.modrinth.com/v2/project/coreprotect/version?loaders=[%22paper%22]" \
  | jq -r '.[0].files[] | select(.primary==true) | .url')
sudo -u minecraft curl -s -L "$CP_URL" -o "$PLUGINS_DIR/CoreProtect.jar"
info "  CoreProtect downloaded."

# --- Graves (via Modrinth) ---
GRAVES_URL=$(curl -s "https://api.modrinth.com/v2/project/graves/version?loaders=[%22paper%22]" \
  | jq -r '.[0].files[] | select(.primary==true) | .url' 2>/dev/null || echo "")
if [ -n "$GRAVES_URL" ]; then
  sudo -u minecraft curl -s -L "$GRAVES_URL" -o "$PLUGINS_DIR/Graves.jar"
  info "  Graves downloaded."
else
  warn "  Graves not found on Modrinth — download manually from SpigotMC."
fi

# --- Chunky (world pre-gen) ---
CHUNKY_URL=$(curl -s "https://api.modrinth.com/v2/project/chunky/version?loaders=[%22bukkit%22]" \
  | jq -r '.[0].files[] | select(.primary==true) | .url')
sudo -u minecraft curl -s -L "$CHUNKY_URL" -o "$PLUGINS_DIR/Chunky.jar"
info "  Chunky downloaded."

# --- Spark (performance profiler) ---
sudo -u minecraft curl -s -L \
  "https://ci.lucko.me/job/spark/lastSuccessfulBuild/artifact/spark-bukkit/build/libs/spark-bukkit.jar" \
  -o "$PLUGINS_DIR/spark.jar"
info "  Spark downloaded."

# --- DriveBackupV2 ---
DRIVE_URL=$(curl -s "https://api.github.com/repos/MinIO4/DriveBackupV2/releases/latest" \
  | jq -r '.assets[] | select(.name | endswith(".jar")) | .browser_download_url' | head -1)
sudo -u minecraft curl -s -L "$DRIVE_URL" -o "$PLUGINS_DIR/DriveBackupV2.jar"
info "  DriveBackupV2 downloaded."

# --- TAB (player list) ---
TAB_URL=$(curl -s "https://api.github.com/repos/NEZNAMY/TAB/releases/latest" \
  | jq -r '.assets[] | select(.name | endswith(".jar") and (contains("TAB") or contains("tab"))) | .browser_download_url' | head -1)
sudo -u minecraft curl -s -L "$TAB_URL" -o "$PLUGINS_DIR/TAB.jar"
info "  TAB downloaded."

# --- Multiverse-Core ---
MV_URL=$(curl -s "https://api.github.com/repos/Multiverse/Multiverse-Core/releases/latest" \
  | jq -r '.assets[] | select(.name | endswith(".jar")) | .browser_download_url' | head -1)
sudo -u minecraft curl -s -L "$MV_URL" -o "$PLUGINS_DIR/Multiverse-Core.jar"
info "  Multiverse-Core downloaded."

# --- Pufferfish (free, performance) ---
PUFFER_URL=$(curl -s "https://api.modrinth.com/v2/project/pufferfish/version?loaders=[%22paper%22]" \
  | jq -r '.[0].files[] | select(.primary==true) | .url' 2>/dev/null || echo "")
if [ -n "$PUFFER_URL" ]; then
  sudo -u minecraft curl -s -L "$PUFFER_URL" -o "$PLUGINS_DIR/Pufferfish.jar"
  info "  Pufferfish downloaded."
else
  warn "  Pufferfish not found via Modrinth API — download manually from pufferfish.host."
fi

# --- FarmLimiter ---
FL_URL=$(curl -s "https://api.modrinth.com/v2/project/farmlimiter/version?loaders=[%22paper%22]" \
  | jq -r '.[0].files[] | select(.primary==true) | .url' 2>/dev/null || echo "")
if [ -n "$FL_URL" ]; then
  sudo -u minecraft curl -s -L "$FL_URL" -o "$PLUGINS_DIR/FarmLimiter.jar"
  info "  FarmLimiter downloaded."
else
  warn "  FarmLimiter not found — download manually from Modrinth/SpigotMC."
fi

# --- ClearLag ---
CL_URL=$(curl -s "https://api.modrinth.com/v2/project/clearlagg/version?loaders=[%22paper%22]" \
  | jq -r '.[0].files[] | select(.primary==true) | .url' 2>/dev/null || echo "")
if [ -n "$CL_URL" ]; then
  sudo -u minecraft curl -s -L "$CL_URL" -o "$PLUGINS_DIR/ClearLag.jar"
  info "  ClearLag downloaded."
else
  warn "  ClearLag not found — download manually from Modrinth/SpigotMC."
fi

info "All plugins downloaded."

# =============================================================
#  FIREWALL
# =============================================================
section "Firewall (UFW)"

sudo ufw allow 22/tcp    comment 'SSH'
sudo ufw allow 25565/tcp comment 'Minecraft Java'
sudo ufw allow 19132/tcp comment 'Geyser Bedrock TCP'
sudo ufw allow 19132/udp comment 'Geyser Bedrock UDP'
sudo ufw allow 19999/tcp comment 'Netdata monitoring'
sudo ufw --force enable
info "Firewall configured."

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
curl -s https://get.netdata.cloud/kickstart.sh > /tmp/netdata-kickstart.sh
sudo sh /tmp/netdata-kickstart.sh --non-interactive --dont-start-it 2>/dev/null || \
  warn "Netdata install failed — skip or install manually."
sudo systemctl enable netdata 2>/dev/null || true
sudo systemctl start netdata 2>/dev/null || true
info "Netdata installed. Access at http://PUBLIC_IP:19999 (restrict to your IP in OCI)"

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
ExecStart=/opt/minecraft/server/start.sh
ExecStop=/bin/kill -s SIGINT \$MAINPID
Restart=on-failure
RestartSec=10
StandardInput=null

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable minecraft
info "Systemd service created and enabled (auto-restart on crash)."

# =============================================================
#  FIRST RUN (generates world + config files)
# =============================================================
section "First Run"
info "Running server for 45 seconds to generate configs (including Geyser)..."
sudo -u minecraft timeout 45 bash /opt/minecraft/server/start.sh || true
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
echo ""
echo -e "${YELLOW}  Manual steps still needed:${NC}"
echo "  1) OCI Console → Security List → open ports 25565, 19132, 19999"
echo "  2) Configure DriveBackupV2 with your Google/OneDrive credentials"
echo "  3) Run Chunky pre-gen once server is running:"
echo "       /chunky world world"
echo "       /chunky radius 2000"
echo "       /chunky start"
echo "  4) Lock Nether/End via Multiverse:"
echo "       /mv create world_nether NETHER"
echo "       /mv modify set allowentry false world_nether"
echo "  5) Add players: /whitelist add <playername>"
echo "  6) Run Pterodactyl setup: bash pterodactyl-setup.sh"
echo "  7) Restrict Netdata port 19999 to your IP in OCI Security List"
echo ""
echo -e "${GREEN}  Start:  sudo systemctl start minecraft${NC}"
echo -e "${GREEN}  Logs:   sudo journalctl -u minecraft -f${NC}"
echo ""
