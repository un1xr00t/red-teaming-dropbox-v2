#!/bin/bash
#================================================================
# PHANTOM PRINTER - C2 SERVER SETUP (SSH TUNNEL ONLY)
# Run this on your Linode Nanode (Ubuntu 22.04)
# n8n is hosted separately on Hostinger
#================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_banner() {
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║       PHANTOM PRINTER - C2 SERVER SETUP                    ║"
    echo "║       SSH Tunnel Relay (n8n hosted externally)             ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

#================================================================
# CONFIGURATION
#================================================================

# Port the dropbox reverse tunnel binds to
SSH_TUNNEL_PORT=2222

# Timezone
TIMEZONE="America/New_York"

#================================================================
# SWAP CONFIGURATION
#================================================================

setup_swap() {
    log "Configuring swap file..."
    
    if swapon --show | grep -q '/swapfile'; then
        warn "Swap file already exists, skipping..."
        return
    fi
    
    # 1GB swap is plenty for tunnel-only server
    fallocate -l 1G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    
    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    
    cat > /etc/sysctl.d/99-swap.conf << 'EOF'
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF
    
    sysctl -p /etc/sysctl.d/99-swap.conf
    
    log "Swap configured: 1GB"
}

#================================================================
# SYSTEM HARDENING
#================================================================

harden_system() {
    log "Hardening system..."
    
    setup_swap
    
    apt update && apt upgrade -y
    
    timedatectl set-timezone "$TIMEZONE"
    
    apt install -y \
        ufw \
        fail2ban \
        unattended-upgrades \
        curl \
        wget \
        htop \
        tmux
    
    echo 'Unattended-Upgrade::Automatic-Reboot "false";' >> /etc/apt/apt.conf.d/50unattended-upgrades
    
    log "System hardened"
}

#================================================================
# FIREWALL SETUP
#================================================================

setup_firewall() {
    log "Configuring firewall..."
    
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    
    # SSH access
    ufw allow 22/tcp comment 'SSH'
    
    # Reverse tunnel port (dropbox connects back through this)
    ufw allow ${SSH_TUNNEL_PORT}/tcp comment 'Dropbox SSH Tunnel'
    
    ufw --force enable
    
    log "Firewall configured"
    ufw status verbose
}

#================================================================
# FAIL2BAN SETUP
#================================================================

setup_fail2ban() {
    log "Configuring fail2ban..."
    
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
ignoreip = 127.0.0.1/8

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF
    
    systemctl enable fail2ban
    systemctl restart fail2ban
    
    log "Fail2ban configured"
}

#================================================================
# SSH CONFIGURATION
#================================================================

setup_ssh() {
    log "Configuring SSH for reverse tunnels..."
    
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    
    cat >> /etc/ssh/sshd_config << 'EOF'

# Phantom Printer C2 Settings
GatewayPorts yes
ClientAliveInterval 30
ClientAliveCountMax 3
TCPKeepAlive yes
AllowTcpForwarding yes
EOF
    
    # Create dropbox user
    if ! id "dropbox" &>/dev/null; then
        useradd -m -s /bin/bash dropbox
        mkdir -p /home/dropbox/.ssh
        chmod 700 /home/dropbox/.ssh
        touch /home/dropbox/.ssh/authorized_keys
        chmod 600 /home/dropbox/.ssh/authorized_keys
        chown -R dropbox:dropbox /home/dropbox/.ssh
        log "Created 'dropbox' user for SSH tunnels"
    fi
    
    systemctl restart sshd
    
    log "SSH configured for reverse tunnels"
}

#================================================================
# PRINT SUMMARY
#================================================================

print_summary() {
    SERVER_IP=$(curl -s ifconfig.me)
    
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           C2 SERVER SETUP COMPLETE                         ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}SERVER IP:${NC} ${SERVER_IP}"
    echo ""
    echo -e "${YELLOW}═══ SSH TUNNEL CONFIG ═══${NC}"
    echo -e "User:         ${GREEN}dropbox${NC}"
    echo -e "Tunnel Port:  ${GREEN}${SSH_TUNNEL_PORT}${NC}"
    echo ""
    echo -e "${YELLOW}═══ NEXT STEPS ═══${NC}"
    echo ""
    echo "1. Add the dropbox Pi's SSH public key:"
    echo -e "   ${CYAN}nano /home/dropbox/.ssh/authorized_keys${NC}"
    echo "   (paste the key from your Pi)"
    echo ""
    echo "2. On your Pi, update dropbox.conf with:"
    echo -e "   ${GREEN}C2_PRIMARY_HOST=\"${SERVER_IP}\"${NC}"
    echo -e "   ${GREEN}C2_PRIMARY_PORT=\"22\"${NC}"
    echo -e "   ${GREEN}C2_PRIMARY_USER=\"dropbox\"${NC}"
    echo -e "   ${GREEN}C2_TUNNEL_PORT=\"${SSH_TUNNEL_PORT}\"${NC}"
    echo ""
    echo "3. Update N8N_WEBHOOK_URL to your Hostinger n8n URL"
    echo ""
    echo "4. Test SSH tunnel from Pi:"
    echo -e "   ${CYAN}ssh -i ~/.ssh/id_dropbox dropbox@${SERVER_IP}${NC}"
    echo ""
    echo -e "${YELLOW}═══ TO ACCESS DROPBOX REMOTELY ═══${NC}"
    echo "Once tunnel is active, SSH to dropbox via:"
    echo -e "   ${CYAN}ssh -p ${SSH_TUNNEL_PORT} kali@${SERVER_IP}${NC}"
    echo ""
}

#================================================================
# MAIN
#================================================================

main() {
    print_banner
    
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        exit 1
    fi
    
    log "Starting C2 server setup..."
    
    harden_system
    setup_firewall
    setup_fail2ban
    setup_ssh
    
    print_summary
}

main "$@"
