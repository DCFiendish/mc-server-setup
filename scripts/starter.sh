#!/bin/bash

# =============================================================
#  Minecraft Server Setup Script
#  For Oracle A1 (Ubuntu 22.04 ARM64)
#  GitHub: DCFiendish
# =============================================================

set -Eeuo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

USER_AGENT="DCFiendish-mc-setup/1.0 (https://github.com/DCFiendish)"

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

# =============================================================
#  QUESTIONS
# =============================================================

echo ""
echo "========================================="
echo "   Minecraft Server Setup by DCFiendish  "
echo "========================================="
echo ""

# Software
echo "Server software:"
echo "  1) Paper"
echo "  2) Purpur"
read -p "Choose (1/2): " SOFTWARE_CHOICE
case $SOFTWARE_CHOICE in
  1) SOFTWARE="paper" ;;
  2) SOFTWARE="purpur" ;;
  *) error "Invalid choice." ;;
esac

# Version
echo ""
echo "Minecraft version:"
echo "  1) 1.21.11  (latest 1.21.x)"
echo "  2) 1.21.10"
echo "  3) 1.21.9"
echo "  4) 1.21.8"
echo "  5) 1.21.4"
echo "  6) 1.21.1"
echo "  7) 1.20.6  (latest 1.20.x)"
echo "  8) 1.20.4"
echo "  9) 1.20.1"
echo " 10) 26.1.2  (latest 2026)"
read -p "Choose (1-10): " VERSION_CHOICE
case $VERSION_CHOICE in
  1)  MC_VERSION="1.21.11" ;;
  2)  MC_VERSION="1.21.10" ;;
  3)  MC_VERSION="1.21.9"  ;;
  4)  MC_VERSION="1.21.8"  ;;
  5)  MC_VERSION="1.21.4"  ;;
  6)  MC_VERSION="1.21.1"  ;;
  7)  MC_VERSION="1.20.6"  ;;
  8)  MC_VERSION="1.20.4"  ;;
  9)  MC_VERSION="1.20.1"  ;;
  10) MC_VERSION="26.1.2"  ;;
  *)  error "Invalid choice." ;;
esac

# World seed
echo ""
read -p "World seed (leave blank for random): " WORLD_SEED

# RAM
RAM="8G"

# Optional plugins
echo ""
echo "Optional plugins (y/n for each):"
read -p "  EssentialsX?  " INSTALL_ESSENTIALS
read -p "  LuckPerms?    " INSTALL_LUCKPERMS
read -p "  Pterodactyl panel? (separate script, just noting choice) " INSTALL_PTERO

echo ""
info "Starting setup for $SOFTWARE $MC_VERSION..."
echo ""

# =============================================================
#  SYSTEM UPDATE
# =============================================================

info "Updating system packages..."
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y curl wget jq ufw unzip tmux

# =============================================================
#  JAVA 21 (Eclipse Temurin via Adoptium)
# =============================================================

info "Installing Java 21 (Eclipse Temurin)..."
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
#  MINECRAFT USER & DIRECTORIES
# =============================================================

info "Creating minecraft user and directories..."
if ! id "minecraft" &>/dev/null; then
  sudo useradd -r -m -U -d /opt/minecraft -s /usr/sbin/nologin minecraft
fi
sudo mkdir -p /opt/minecraft/server/plugins
sudo chown -R minecraft:minecraft /opt/minecraft

# =============================================================
#  DOWNLOAD SERVER JAR
# =============================================================

info "Downloading $SOFTWARE $MC_VERSION..."

if [ "$SOFTWARE" = "paper" ]; then
  BUILDS_JSON=$(curl -fsSL -A "$USER_AGENT" \
    "https://fill.papermc.io/v3/projects/paper/versions/${MC_VERSION}/builds")

  if echo "$BUILDS_JSON" | jq -e '.ok == false' > /dev/null 2>&1; then
    error "Paper API error for version $MC_VERSION: $(echo $BUILDS_JSON | jq -r '.message')"
  fi

  JAR_URL=$(echo "$BUILDS_JSON" | jq -r \
    'first(.[] | select(.channel == "STABLE") | .downloads."server:default".url) // "null"')

  if [ "$JAR_URL" = "null" ] || [ -z "$JAR_URL" ]; then
    error "No stable Paper build found for $MC_VERSION."
  fi

  sudo -u minecraft curl -fsSL -A "$USER_AGENT" \
    -o /opt/minecraft/server/server.jar "$JAR_URL"

elif [ "$SOFTWARE" = "purpur" ]; then
  HTTP_CODE=$(sudo -u minecraft curl -fsSL -A "$USER_AGENT" \
    -w "%{http_code}" \
    -o /opt/minecraft/server/server.jar \
    "https://api.purpurmc.org/v2/purpur/${MC_VERSION}/latest/download")

  if [ "$HTTP_CODE" != "200" ]; then
    error "Failed to download Purpur ${MC_VERSION} (HTTP $HTTP_CODE). Check the version is valid."
  fi
fi

# Verify it's actually a JAR
if ! file /opt/minecraft/server/server.jar | grep -q "Java archive"; then
  error "Downloaded file is not a valid JAR. The version may not exist or the API may be down."
fi

info "Server jar downloaded and verified."

# =============================================================
#  ACCEPT EULA
# =============================================================

info "Accepting EULA..."
echo "eula=true" | sudo tee /opt/minecraft/server/eula.txt > /dev/null

# =============================================================
#  SERVER.PROPERTIES
# =============================================================

info "Writing server.properties..."

if [ -n "$WORLD_SEED" ]; then
  SEED_LINE="level-seed=$WORLD_SEED"
else
  SEED_LINE="level-seed="
fi

sudo tee /opt/minecraft/server/server.properties > /dev/null <<EOF
#Minecraft server properties
online-mode=true
server-port=25565
max-players=100
view-distance=10
simulation-distance=6
$SEED_LINE
white-list=true
enforce-whitelist=true
spawn-protection=0
difficulty=normal
gamemode=survival
pvp=true
enable-command-block=false
motd=A Minecraft Server
EOF

sudo chown minecraft:minecraft /opt/minecraft/server/server.properties
info "server.properties written."

# =============================================================
#  START SCRIPT (Aikar flags, 8G heap tuned for ARM)
# =============================================================

info "Writing start.sh with Aikar flags..."

sudo tee /opt/minecraft/server/start.sh > /dev/null <<EOF
#!/bin/bash
cd /opt/minecraft/server
java -Xms${RAM} -Xmx${RAM} \\
  -XX:+UseG1GC \\
  -XX:+ParallelRefProcEnabled \\
  -XX:MaxGCPauseMillis=200 \\
  -XX:+UnlockExperimentalVMOptions \\
  -XX:+DisableExplicitGC \\
  -XX:G1NewSizePercent=30 \\
  -XX:G1MaxNewSizePercent=40 \\
  -XX:G1HeapRegionSize=8M \\
  -XX:G1ReservePercent=15 \\
  -XX:G1HeapWastePercent=5 \\
  -XX:G1MixedGCCountTarget=4 \\
  -XX:InitiatingHeapOccupancyPercent=20 \\
  -XX:G1MixedGCLiveThresholdPercent=90 \\
  -XX:G1RSetUpdatingPauseTimePercent=5 \\
  -XX:SurvivorRatio=32 \\
  -XX:+PerfDisableSharedMem \\
  -XX:MaxTenuringThreshold=1 \\
  -Dusing.aikars.flags=https://mcflags.emc.gs \\
  -Daikars.new.flags=true \\
  -jar server.jar --nogui
EOF

sudo chmod +x /opt/minecraft/server/start.sh
sudo chown minecraft:minecraft /opt/minecraft/server/start.sh
info "start.sh written."

# =============================================================
#  DOWNLOAD PLUGINS
# =============================================================

info "Downloading base plugins..."
PLUGINS_DIR="/opt/minecraft/server/plugins"

# Spark
dl_plugin \
  "https://ci.lucko.me/job/spark/lastSuccessfulBuild/artifact/spark-bukkit/build/libs/spark-bukkit.jar" \
  "$PLUGINS_DIR/spark.jar" \
  "Spark"

# DriveBackupV2
DRIVE_URL=$(curl -fsSL -A "$USER_AGENT" \
  "https://api.github.com/repos/MinIO4/DriveBackupV2/releases/latest" \
  | jq -r '.assets[] | select(.name | endswith(".jar")) | .browser_download_url' \
  | head -1 || echo "")
dl_plugin "$DRIVE_URL" "$PLUGINS_DIR/DriveBackupV2.jar" "DriveBackupV2"

# TAB
TAB_URL=$(curl -fsSL -A "$USER_AGENT" \
  "https://api.github.com/repos/NEZNAMY/TAB/releases/latest" \
  | jq -r '.assets[] | select(.name | endswith(".jar") and (contains("TAB") or contains("tab"))) | .browser_download_url' \
  | head -1 || echo "")
dl_plugin "$TAB_URL" "$PLUGINS_DIR/TAB.jar" "TAB"

# Fail2Ban (system level, not a plugin)
info "Installing Fail2Ban (system)..."
sudo apt-get install -y fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Optional: EssentialsX
if [[ "$INSTALL_ESSENTIALS" =~ ^[Yy]$ ]]; then
  ESS_URL=$(curl -fsSL -A "$USER_AGENT" \
    "https://api.github.com/repos/EssentialsX/Essentials/releases/latest" \
    | jq -r '.assets[] | select(.name | startswith("EssentialsX-") and endswith(".jar")) | .browser_download_url' \
    | head -1 || echo "")
  dl_plugin "$ESS_URL" "$PLUGINS_DIR/EssentialsX.jar" "EssentialsX"
fi

# Optional: LuckPerms
if [[ "$INSTALL_LUCKPERMS" =~ ^[Yy]$ ]]; then
  LP_URL=$(curl -fsSL -A "$USER_AGENT" \
    "https://api.github.com/repos/LuckPerms/LuckPerms/releases/latest" \
    | jq -r '.assets[] | select(.name | startswith("LuckPerms-Bukkit")) | .browser_download_url' \
    | head -1 || echo "")
  dl_plugin "$LP_URL" "$PLUGINS_DIR/LuckPerms.jar" "LuckPerms"
fi

info "All plugins downloaded."

# =============================================================
#  FIREWALL (UFW)
# =============================================================

info "Configuring UFW firewall..."
sudo ufw allow 22/tcp    comment 'SSH'
sudo ufw allow 25565/tcp comment 'Minecraft Java'
sudo ufw allow 25565/udp comment 'Minecraft Java UDP'
sudo ufw --force enable
info "Firewall configured."
warn "If you install Geyser later, also open: sudo ufw allow 19132/tcp && sudo ufw allow 19132/udp"

# =============================================================
#  SYSTEMD SERVICE
# =============================================================

info "Creating systemd service..."

sudo tee /etc/systemd/system/minecraft.service > /dev/null <<EOF
[Unit]
Description=Minecraft Server
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

info "Running server for 120 seconds to generate configs..."
sudo -u minecraft timeout 120 bash /opt/minecraft/server/start.sh || true
info "First run complete."

# =============================================================
#  DONE
# =============================================================

PUBLIC_IP=$(curl -fsSL https://api.ipify.org 2>/dev/null || echo "unknown")

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}   Setup Complete!                       ${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "  Software:  $SOFTWARE"
echo "  Version:   $MC_VERSION"
echo "  RAM:       $RAM"
echo "  Public IP: $PUBLIC_IP"
if [ -n "$WORLD_SEED" ]; then
  echo "  Seed:      $WORLD_SEED"
else
  echo "  Seed:      Random (check server.properties after first run)"
fi
echo ""
echo -e "${YELLOW}  OCI Security List — open these ports:${NC}"
echo "    TCP 25565  (Minecraft Java)"
echo "    TCP+UDP 19132  (if using Geyser/Bedrock)"
echo ""
echo "  Server dir:  /opt/minecraft/server"
echo "  Start:       sudo systemctl start minecraft"
echo "  Stop:        sudo systemctl stop minecraft"
echo "  Logs:        sudo journalctl -u minecraft -f"
echo ""
if [[ "$INSTALL_PTERO" =~ ^[Yy]$ ]]; then
  echo -e "${YELLOW}  Pterodactyl: Run the pterodactyl-setup.sh script next.${NC}"
  echo ""
fi
echo "  Remember to:"
echo "  1) Open OCI Security List port 25565 TCP"
echo "  2) Configure DriveBackupV2 with client's cloud storage"
echo "  3) Add players to whitelist: /whitelist add <player>"
if [[ "$INSTALL_ESSENTIALS" =~ ^[Yy]$ ]]; then
  echo "  4) Configure EssentialsX in plugins/EssentialsX/config.yml"
fi
echo ""
echo -e "${GREEN}  Start the server: sudo systemctl start minecraft${NC}"
echo ""
