#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# RED TEAMING DROPBOX V2 - INSTALLATION SCRIPT
# ══════════════════════════════════════════════════════════════════════════════
# Run this script on a fresh Kali Linux installation on Raspberry Pi 5
# ══════════════════════════════════════════════════════════════════════════════

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

DROPBOX_DIR="/home/kali/dropbox-v2"
LOG_FILE="/var/log/dropbox-install.log"

# ──────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
# ──────────────────────────────────────────────────────────────────────────────

log() {
    echo -e "${GREEN}[+]${NC} $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"
}

log_section() {
    echo "" | tee -a "$LOG_FILE"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE} $1${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

check_pi5() {
    if grep -q "Raspberry Pi 5" /proc/cpuinfo 2>/dev/null; then
        log "Detected Raspberry Pi 5"
    else
        log_warn "Raspberry Pi 5 not detected. Proceeding anyway..."
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# SYSTEM UPDATE
# ──────────────────────────────────────────────────────────────────────────────

update_system() {
    log_section "UPDATING SYSTEM"
    
    apt update
    apt full-upgrade -y
    apt autoremove -y
    
    log "System updated successfully"
}

# ──────────────────────────────────────────────────────────────────────────────
# INSTALL DEPENDENCIES
# ──────────────────────────────────────────────────────────────────────────────

install_dependencies() {
    log_section "INSTALLING DEPENDENCIES"
    
    # Core tools
    log "Installing core tools..."
    apt install -y \
        git curl wget vim tmux htop \
        jq ipcalc socat netcat-openbsd \
        python3 python3-pip python3-venv \
        build-essential libssl-dev libffi-dev
    
    # Networking tools
    log "Installing networking tools..."
    apt install -y \
        autossh openssh-server openssh-client \
        nmap masscan arp-scan \
        tcpdump wireshark-cli tshark \
        dnsutils whois net-tools iproute2 \
        macchanger avahi-daemon avahi-utils
    
    # Offensive tools
    log "Installing offensive tools..."
    apt install -y \
        responder crackmapexec \
        hydra john hashcat \
        smbclient smbmap enum4linux \
        nikto gobuster dirb \
        sqlmap
    
    # WiFi tools
    log "Installing WiFi tools..."
    apt install -y \
        aircrack-ng hostapd dnsmasq \
        bettercap hcxtools hcxdumptool \
        wifite
    
    # Python packages
    log "Installing Python packages..."
    pip3 install --break-system-packages \
        impacket ldap3 bloodhound pycryptodome \
        requests paramiko scapy netifaces \
        python-nmap netaddr
    
    log "Dependencies installed successfully"
}

# ──────────────────────────────────────────────────────────────────────────────
# INSTALL ADDITIONAL TOOLS
# ──────────────────────────────────────────────────────────────────────────────

install_additional_tools() {
    log_section "INSTALLING ADDITIONAL TOOLS"
    
    local TOOLS_DIR="${DROPBOX_DIR}/tools"
    mkdir -p "$TOOLS_DIR"
    cd "$TOOLS_DIR"
    
    # Nuclei
    if ! command -v nuclei &> /dev/null; then
        log "Installing Nuclei..."
        GO111MODULE=on go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest 2>/dev/null || \
            apt install -y nuclei 2>/dev/null || \
            log_warn "Could not install Nuclei"
    fi
    
    # GoWitness
    if ! command -v gowitness &> /dev/null; then
        log "Installing GoWitness..."
        GO111MODULE=on go install -v github.com/sensepost/gowitness@latest 2>/dev/null || \
            log_warn "Could not install GoWitness"
    fi
    
    # enum4linux-ng
    if ! command -v enum4linux-ng &> /dev/null; then
        log "Installing enum4linux-ng..."
        pip3 install --break-system-packages enum4linux-ng 2>/dev/null || \
            log_warn "Could not install enum4linux-ng"
    fi
    
    log "Additional tools installed"
}

# ──────────────────────────────────────────────────────────────────────────────
# DOWNLOAD PAYLOAD ARSENAL
# ──────────────────────────────────────────────────────────────────────────────

download_payloads() {
    log_section "DOWNLOADING PAYLOAD ARSENAL"
    
    local PAYLOAD_DIR="${DROPBOX_DIR}/payloads"
    local TOOLS_DIR="${DROPBOX_DIR}/tools"
    mkdir -p "$PAYLOAD_DIR" "$TOOLS_DIR"
    
    cd "$TOOLS_DIR"
    
    # PayloadsAllTheThings
    log "Cloning PayloadsAllTheThings..."
    git clone --depth 1 https://github.com/swisskyrepo/PayloadsAllTheThings 2>/dev/null || \
        (cd PayloadsAllTheThings && git pull)
    
    # GTFOBins
    log "Cloning GTFOBins..."
    git clone --depth 1 https://github.com/GTFOBins/GTFOBins.github.io GTFOBins 2>/dev/null || \
        (cd GTFOBins && git pull)
    
    # LOLBAS
    log "Cloning LOLBAS..."
    git clone --depth 1 https://github.com/LOLBAS-Project/LOLBAS 2>/dev/null || \
        (cd LOLBAS && git pull)
    
    # PowerShell Suite
    log "Cloning PowerShell-Suite..."
    git clone --depth 1 https://github.com/FuzzySecurity/PowerShell-Suite 2>/dev/null || \
        (cd PowerShell-Suite && git pull)
    
    # HackTricks
    log "Cloning HackTricks..."
    git clone --depth 1 https://github.com/carlospolop/hacktricks 2>/dev/null || \
        (cd hacktricks && git pull)
    
    # Impacket examples
    log "Cloning Impacket..."
    git clone --depth 1 https://github.com/fortra/impacket 2>/dev/null || \
        (cd impacket && git pull)
    
    # Download binaries
    cd "$PAYLOAD_DIR"
    
    log "Downloading SharpHound..."
    wget -q https://github.com/BloodHoundAD/BloodHound/raw/master/Collectors/SharpHound.exe -O SharpHound.exe 2>/dev/null || true
    
    log "Downloading LaZagne..."
    wget -q https://github.com/AlessandroZ/LaZagne/releases/download/v2.4.5/lazagne.exe -O lazagne.exe 2>/dev/null || true
    
    log "Downloading Rubeus..."
    wget -q https://github.com/r3motecontrol/Ghostpack-CompiledBinaries/raw/master/Rubeus.exe -O Rubeus.exe 2>/dev/null || true
    
    log "Downloading Mimikatz..."
    wget -q https://github.com/gentilkiwi/mimikatz/releases/download/2.2.0-20220919/mimikatz_trunk.zip -O mimikatz.zip 2>/dev/null && \
        unzip -o mimikatz.zip -d mimikatz 2>/dev/null && rm mimikatz.zip || true
    
    # Linux privesc tools
    log "Downloading Linux privesc tools..."
    mkdir -p linux
    wget -q https://raw.githubusercontent.com/carlospolop/PEASS-ng/master/linPEAS/linpeas.sh -O linux/linpeas.sh 2>/dev/null || true
    wget -q https://raw.githubusercontent.com/rebootuser/LinEnum/master/LinEnum.sh -O linux/linenum.sh 2>/dev/null || true
    
    # Windows privesc tools
    log "Downloading Windows privesc tools..."
    mkdir -p windows
    wget -q https://raw.githubusercontent.com/carlospolop/PEASS-ng/master/winPEAS/winPEASbat/winPEAS.bat -O windows/winpeas.bat 2>/dev/null || true
    
    log "Payload arsenal downloaded"
}

# ──────────────────────────────────────────────────────────────────────────────
# GENERATE SSH KEYS
# ──────────────────────────────────────────────────────────────────────────────

setup_ssh() {
    log_section "SETTING UP SSH"
    
    local SSH_DIR="/home/kali/.ssh"
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    
    # Generate dropbox key if it doesn't exist
    if [[ ! -f "${SSH_DIR}/id_dropbox" ]]; then
        log "Generating SSH key for C2 connection..."
        ssh-keygen -t ed25519 -f "${SSH_DIR}/id_dropbox" -N "" -C "dropbox-v2"
        log "SSH key generated: ${SSH_DIR}/id_dropbox"
        
        echo ""
        echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║  IMPORTANT: Copy this public key to your C2 server              ║${NC}"
        echo -e "${YELLOW}╠══════════════════════════════════════════════════════════════════╣${NC}"
        cat "${SSH_DIR}/id_dropbox.pub"
        echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
    fi
    
    # Fix permissions
    chown -R kali:kali "$SSH_DIR"
    chmod 600 "${SSH_DIR}/id_dropbox" 2>/dev/null || true
    
    log "SSH setup complete"
}

# ──────────────────────────────────────────────────────────────────────────────
# CREATE DIRECTORY STRUCTURE
# ──────────────────────────────────────────────────────────────────────────────

create_directories() {
    log_section "CREATING DIRECTORY STRUCTURE"
    
    mkdir -p "${DROPBOX_DIR}"/{config,modules,scripts,payloads,tools,loot,logs,certs}
    mkdir -p "${DROPBOX_DIR}/modules"/{stealth,c2,recon,attack,exfil,opsec}
    mkdir -p "${DROPBOX_DIR}/loot"/{creds,hashes,scans,exfil}
    mkdir -p "${DROPBOX_DIR}/n8n"/{workflows,data}
    
    # Set permissions
    chown -R kali:kali "$DROPBOX_DIR"
    
    log "Directory structure created"
}

# ──────────────────────────────────────────────────────────────────────────────
# CREATE SYSTEMD SERVICES
# ──────────────────────────────────────────────────────────────────────────────

create_services() {
    log_section "CREATING SYSTEMD SERVICES"
    
    # Main dropbox service
    cat > /etc/systemd/system/dropbox-main.service << 'EOF'
[Unit]
Description=Red Teaming Dropbox V2 - Main Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/home/kali/dropbox-v2
ExecStart=/home/kali/dropbox-v2/scripts/startup.sh
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

    # Stealth service
    cat > /etc/systemd/system/dropbox-stealth.service << 'EOF'
[Unit]
Description=Red Teaming Dropbox V2 - Stealth Module
After=network.target
Before=dropbox-main.service

[Service]
Type=oneshot
User=root
ExecStart=/home/kali/dropbox-v2/modules/stealth/stealth.sh enable
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # Payload hosting service
    cat > /etc/systemd/system/dropbox-payloads.service << 'EOF'
[Unit]
Description=Red Teaming Dropbox V2 - Payload Hosting
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=kali
WorkingDirectory=/home/kali/dropbox-v2/payloads
ExecStart=/usr/bin/python3 -m http.server 80
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd
    systemctl daemon-reload
    
    log "Systemd services created"
}

# ──────────────────────────────────────────────────────────────────────────────
# CREATE STARTUP SCRIPT
# ──────────────────────────────────────────────────────────────────────────────

create_startup_script() {
    log_section "CREATING STARTUP SCRIPT"
    
    cat > "${DROPBOX_DIR}/scripts/startup.sh" << 'STARTUP'
#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# RED TEAMING DROPBOX V2 - STARTUP ORCHESTRATION
# ══════════════════════════════════════════════════════════════════════════════

set -e

DROPBOX_DIR="/home/kali/dropbox-v2"
LOG_DIR="${DROPBOX_DIR}/logs"
LOG_FILE="${LOG_DIR}/startup_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "═══════════════════════════════════════════════════════════════════"
log " RED TEAMING DROPBOX V2 - STARTING UP"
log "═══════════════════════════════════════════════════════════════════"

# Wait for network
log "Waiting for network..."
sleep 10

# Enable stealth mode
log "Enabling stealth mode..."
bash "${DROPBOX_DIR}/modules/stealth/stealth.sh" enable

# Start C2 connection
log "Starting C2 connection..."
bash "${DROPBOX_DIR}/modules/c2/c2.sh" start &

# Wait before recon
log "Waiting before starting recon..."
sleep 120

# Start initial recon (if enabled)
if grep -q "auto_recon_on_boot = true" "${DROPBOX_DIR}/config/dropbox.conf" 2>/dev/null; then
    log "Starting initial reconnaissance..."
    bash "${DROPBOX_DIR}/scripts/recon.sh" quick &
fi

log "Startup complete. Dropbox is operational."

# Keep running (C2 beacon loop handles the rest)
wait
STARTUP

    chmod +x "${DROPBOX_DIR}/scripts/startup.sh"
    chown kali:kali "${DROPBOX_DIR}/scripts/startup.sh"
    
    log "Startup script created"
}

# ──────────────────────────────────────────────────────────────────────────────
# CONFIGURE NETWORK
# ──────────────────────────────────────────────────────────────────────────────

configure_network() {
    log_section "CONFIGURING NETWORK"
    
    # Enable IP forwarding (for MITM)
    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    sysctl -p
    
    # Configure NetworkManager to auto-connect
    log "NetworkManager configured for auto-connect"
    log_warn "Remember to configure WiFi with: nmtui"
    
    log "Network configuration complete"
}

# ──────────────────────────────────────────────────────────────────────────────
# CONVERT TO HEADLESS
# ──────────────────────────────────────────────────────────────────────────────

convert_to_headless() {
    log_section "CONVERTING TO HEADLESS MODE"
    
    # Set default target to multi-user (CLI, no GUI)
    log "Setting default boot target to CLI..."
    systemctl set-default multi-user.target
    
    # Disable display managers
    log "Disabling display managers..."
    systemctl disable lightdm 2>/dev/null || true
    systemctl disable gdm 2>/dev/null || true
    systemctl disable sddm 2>/dev/null || true
    
    # Disable unnecessary services for a dropbox
    log "Disabling unnecessary services..."
    systemctl disable bluetooth 2>/dev/null || true
    systemctl disable cups 2>/dev/null || true
    systemctl disable cups-browsed 2>/dev/null || true
    systemctl disable ModemManager 2>/dev/null || true
    systemctl disable wpa_supplicant 2>/dev/null || true  # NetworkManager handles WiFi
    systemctl disable triggerhappy 2>/dev/null || true
    systemctl disable avahi-daemon 2>/dev/null || true    # We'll start this manually when needed
    
    # Enable essential services
    log "Enabling essential services..."
    systemctl enable ssh
    systemctl enable NetworkManager
    
    # Ask about removing desktop packages
    if [[ "${REMOVE_DESKTOP:-false}" == "true" ]]; then
        log "Removing desktop environment packages..."
        apt remove --purge -y \
            kali-desktop-xfce xfce4* lightdm* \
            xorg* xserver* \
            firefox-esr chromium \
            libreoffice* \
            2>/dev/null || true
        apt autoremove -y
        apt clean
        log "Desktop packages removed - saved ~2-3GB"
    else
        log "Keeping desktop packages (use REMOVE_DESKTOP=true to remove)"
    fi
    
    # Optimize boot time
    log "Optimizing boot configuration..."
    
    # Reduce kernel verbosity
    if [[ -f /boot/cmdline.txt ]]; then
        if ! grep -q "quiet" /boot/cmdline.txt; then
            sed -i 's/$/ quiet loglevel=3/' /boot/cmdline.txt
        fi
    fi
    
    # Disable splash screen
    if [[ -f /boot/config.txt ]]; then
        if ! grep -q "disable_splash=1" /boot/config.txt; then
            echo "disable_splash=1" >> /boot/config.txt
        fi
    fi
    
    # NOTE: HDMI stays ENABLED for initial configuration
    # Run 'sudo ~/dropbox-v2/scripts/arm.sh' when ready to deploy
    
    log "Headless conversion complete"
    log "NOTE: HDMI still enabled for configuration. Run 'arm.sh' before deployment."
    log "System will boot to CLI on next reboot"
}

# ──────────────────────────────────────────────────────────────────────────────
# FINAL SETUP
# ──────────────────────────────────────────────────────────────────────────────

final_setup() {
    log_section "FINALIZING INSTALLATION"
    
    # Make all scripts executable
    find "${DROPBOX_DIR}" -name "*.sh" -exec chmod +x {} \;
    
    # Fix ownership
    chown -R kali:kali "${DROPBOX_DIR}"
    
    # Generate self-signed cert for HTTPS payload hosting
    if [[ ! -f "${DROPBOX_DIR}/certs/server.crt" ]]; then
        log "Generating self-signed certificate..."
        mkdir -p "${DROPBOX_DIR}/certs"
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "${DROPBOX_DIR}/certs/server.key" \
            -out "${DROPBOX_DIR}/certs/server.crt" \
            -subj "/CN=printer.local" 2>/dev/null
    fi
    
    log "Installation complete!"
}

# ──────────────────────────────────────────────────────────────────────────────
# PRINT NEXT STEPS
# ──────────────────────────────────────────────────────────────────────────────

print_next_steps() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         RED TEAMING DROPBOX V2 - INSTALLATION COMPLETE           ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║                                                                  ║${NC}"
    echo -e "${GREEN}║  ✓ System converted to HEADLESS mode (no GUI)                   ║${NC}"
    echo -e "${GREEN}║  ✓ SSH enabled for remote access                                ║${NC}"
    echo -e "${GREEN}║                                                                  ║${NC}"
    echo -e "${GREEN}║  NEXT STEPS:                                                     ║${NC}"
    echo -e "${GREEN}║                                                                  ║${NC}"
    echo -e "${GREEN}║  1. Edit configuration:                                          ║${NC}"
    echo -e "${GREEN}║     nano ${DROPBOX_DIR}/config/dropbox.conf              ║${NC}"
    echo -e "${GREEN}║                                                                  ║${NC}"
    echo -e "${GREEN}║  2. Copy SSH public key to C2 server:                            ║${NC}"
    echo -e "${GREEN}║     cat /home/kali/.ssh/id_dropbox.pub                           ║${NC}"
    echo -e "${GREEN}║                                                                  ║${NC}"
    echo -e "${GREEN}║  3. Configure WiFi (if not done via Imager):                     ║${NC}"
    echo -e "${GREEN}║     nmtui                                                        ║${NC}"
    echo -e "${GREEN}║                                                                  ║${NC}"
    echo -e "${GREEN}║  4. Deploy n8n on C2 server:                                     ║${NC}"
    echo -e "${GREEN}║     See ${DROPBOX_DIR}/n8n/docker-compose.yml            ║${NC}"
    echo -e "${GREEN}║                                                                  ║${NC}"
    echo -e "${GREEN}║  5. Test the dropbox:                                            ║${NC}"
    echo -e "${GREEN}║     sudo systemctl start dropbox-main                            ║${NC}"
    echo -e "${GREEN}║                                                                  ║${NC}"
    echo -e "${GREEN}║  6. Enable services & test:                                     ║${NC}"
    echo -e "${GREEN}║     sudo systemctl enable dropbox-stealth dropbox-main           ║${NC}"
    echo -e "${GREEN}║     sudo systemctl start dropbox-main                            ║${NC}"
    echo -e "${GREEN}║                                                                  ║${NC}"
    echo -e "${GREEN}║  7. WHEN READY TO DEPLOY (disables HDMI):                        ║${NC}"
    echo -e "${GREEN}║     sudo ~/dropbox-v2/scripts/arm.sh                             ║${NC}"
    echo -e "${GREEN}║     sudo reboot                                                  ║${NC}"
    echo -e "${GREEN}║                                                                  ║${NC}"
    echo -e "${GREEN}║  Need HDMI back for maintenance?                                 ║${NC}"
    echo -e "${GREEN}║     sudo ~/dropbox-v2/scripts/arm.sh disarm                      ║${NC}"
    echo -e "${GREEN}║                                                                  ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Show the SSH key for easy copy
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW} SSH PUBLIC KEY (copy this to your C2 server):${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
    cat /home/kali/.ssh/id_dropbox.pub 2>/dev/null || echo "Key not found"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         RED TEAMING DROPBOX V2 - INSTALLATION SCRIPT             ║${NC}"
    echo -e "${BLUE}║                    Codename: Phantom Printer                     ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    check_root
    check_pi5
    
    update_system
    install_dependencies
    create_directories
    install_additional_tools
    download_payloads
    setup_ssh
    create_services
    create_startup_script
    configure_network
    convert_to_headless
    final_setup
    
    print_next_steps
}

# Run main
main "$@"
