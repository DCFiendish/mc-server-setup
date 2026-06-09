# FiendishHosting — Minecraft Server Setup

One-time Minecraft server setup on Oracle Cloud Free Tier A1.

## Scripts

### 1. Pterodactyl Panel Setup (run first)
```bash
curl -sSL https://raw.githubusercontent.com/DCFiendish/mc-server-setup/main/scripts/pterodactyl-setup.sh -o ptero.sh && sudo bash ptero.sh
```

### 2. Starter Package
```bash
curl -sSL https://raw.githubusercontent.com/DCFiendish/mc-server-setup/main/scripts/starter.sh | bash
```

## Prerequisites
- Ubuntu 22.04 ARM64 (Oracle A1)
- Run needrestart fix first:
```bash
sudo sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf
```
- Run iptables fix (see scripts for full list)

## Docs
Pricing and handoff documents are in the `docs/` folder.
