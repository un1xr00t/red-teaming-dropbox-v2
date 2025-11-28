#!/bin/bash
#================================================================
# PHANTOM PRINTER V2 - STEALTH MODULE
# HP Printer Disguise: MAC spoofing, hostname, mDNS, fake ports
#================================================================

set -e

# Source configuration
CONFIG_FILE="/home/kali/dropbox-v2/config/dropbox.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Defaults if not in config
INTERFACE="${INTERFACE:-eth0}"
HP_HOSTNAME="${HP_HOSTNAME:-HPLJ-M428fdw}"

# HP MAC prefixes (OUI)
HP_MAC_PREFIXES=("00:1E:0B" "3C:D9:2B" "94:57:A5" "B0:5C:DA" "10:1F:74")

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [STEALTH] $1"
    logger -t "dropbox-stealth" "$1"
}

# Generate random HP MAC address
generate_hp_mac() {
    local prefix=${HP_MAC_PREFIXES[$RANDOM % ${#HP_MAC_PREFIXES[@]}]}
    local suffix=$(printf '%02X:%02X:%02X' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
    echo "$prefix:$suffix"
}

# Spoof MAC address
spoof_mac() {
    local new_mac=$(generate_hp_mac)
    log "Spoofing MAC to: $new_mac"
    
    ip link set "$INTERFACE" down 2>/dev/null || true
    
    if command -v macchanger &>/dev/null; then
        macchanger -m "$new_mac" "$INTERFACE" 2>/dev/null || true
    else
        ip link set "$INTERFACE" address "$new_mac" 2>/dev/null || true
    fi
    
    ip link set "$INTERFACE" up 2>/dev/null || true
    
    log "MAC address changed successfully"
}

# Restore original MAC
restore_mac() {
    log "Restoring original MAC..."
    
    ip link set "$INTERFACE" down 2>/dev/null || true
    
    if command -v macchanger &>/dev/null; then
        macchanger -p "$INTERFACE" 2>/dev/null || true
    fi
    
    ip link set "$INTERFACE" up 2>/dev/null || true
    
    log "MAC address restored"
}

# Set HP hostname
set_hostname() {
    log "Setting hostname to: $HP_HOSTNAME"
    
    hostnamectl set-hostname "$HP_HOSTNAME" 2>/dev/null || \
        hostname "$HP_HOSTNAME"
    
    # Update /etc/hosts
    if ! grep -q "$HP_HOSTNAME" /etc/hosts; then
        sed -i "s/127.0.1.1.*/127.0.1.1\t$HP_HOSTNAME/" /etc/hosts 2>/dev/null || true
    fi
    
    log "Hostname changed successfully"
}

# Restore original hostname
restore_hostname() {
    log "Restoring hostname to: kali"
    hostnamectl set-hostname "kali" 2>/dev/null || hostname "kali"
    log "Hostname restored"
}

# Configure mDNS/Avahi for printer advertisement
setup_mdns() {
    log "Configuring mDNS printer advertisement..."
    
    # Create Avahi service file
    cat > /etc/avahi/services/printer.service << 'EOF'
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name>HP LaserJet Pro MFP M428fdw</name>
  
  <service>
    <type>_ipp._tcp</type>
    <port>631</port>
    <txt-record>txtvers=1</txt-record>
    <txt-record>qtotal=1</txt-record>
    <txt-record>pdl=application/postscript,application/pdf</txt-record>
    <txt-record>product=(HP LaserJet Pro MFP M428fdw)</txt-record>
    <txt-record>ty=HP LaserJet Pro MFP M428fdw</txt-record>
  </service>
  
  <service>
    <type>_pdl-datastream._tcp</type>
    <port>9100</port>
  </service>
  
  <service>
    <type>_printer._tcp</type>
    <port>515</port>
  </service>
  
  <service>
    <type>_http._tcp</type>
    <port>80</port>
    <txt-record>path=/</txt-record>
  </service>
</service-group>
EOF
    
    # Restart Avahi
    systemctl restart avahi-daemon 2>/dev/null || true
    
    log "mDNS printer advertisement configured"
}

# Remove mDNS advertisement
remove_mdns() {
    log "Removing mDNS advertisement..."
    rm -f /etc/avahi/services/printer.service 2>/dev/null || true
    systemctl restart avahi-daemon 2>/dev/null || true
    log "mDNS advertisement removed"
}

# Start fake printer listeners
start_printer_ports() {
    log "Starting fake printer port listeners..."
    
    # Kill any existing listeners
    pkill -f "nc.*9100" 2>/dev/null || true
    pkill -f "nc.*515" 2>/dev/null || true
    pkill -f "nc.*631" 2>/dev/null || true
    
    # JetDirect port 9100 - accepts and discards print jobs
    (while true; do nc -l -p 9100 -q 1 > /dev/null 2>&1; done) &
    
    # LPD port 515
    (while true; do nc -l -p 515 -q 1 > /dev/null 2>&1; done) &
    
    # IPP port 631
    (while true; do nc -l -p 631 -q 1 > /dev/null 2>&1; done) &
    
    log "Printer ports listening (515, 631, 9100)"
}

# Stop fake printer listeners
stop_printer_ports() {
    log "Stopping fake printer port listeners..."
    pkill -f "nc.*-l.*-p.*9100" 2>/dev/null || true
    pkill -f "nc.*-l.*-p.*515" 2>/dev/null || true
    pkill -f "nc.*-l.*-p.*631" 2>/dev/null || true
    log "Printer ports stopped"
}

# Start fake HP web interface on port 80
start_web_interface() {
    log "Starting fake HP web interface..."
    
    # Create fake HP printer page
    mkdir -p /tmp/hp-web
    cat > /tmp/hp-web/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>HP LaserJet Pro MFP M428fdw</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
        .header { background: #0096d6; color: white; padding: 15px; margin: -20px -20px 20px; }
        .header h1 { margin: 0; font-size: 24px; }
        .status { background: white; padding: 20px; border-radius: 5px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        .status-item { display: flex; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid #eee; }
        .status-label { color: #666; }
        .status-value { font-weight: bold; }
        .ready { color: #4caf50; }
    </style>
</head>
<body>
    <div class="header">
        <h1>HP LaserJet Pro MFP M428fdw</h1>
    </div>
    <div class="status">
        <h2>Printer Status</h2>
        <div class="status-item">
            <span class="status-label">Status:</span>
            <span class="status-value ready">Ready</span>
        </div>
        <div class="status-item">
            <span class="status-label">Toner Level:</span>
            <span class="status-value">Black: 67%</span>
        </div>
        <div class="status-item">
            <span class="status-label">Paper Tray 1:</span>
            <span class="status-value">A4 (250 sheets)</span>
        </div>
        <div class="status-item">
            <span class="status-label">IP Address:</span>
            <span class="status-value" id="ip">Loading...</span>
        </div>
        <div class="status-item">
            <span class="status-label">Firmware:</span>
            <span class="status-value">2409A_002_0912</span>
        </div>
    </div>
    <script>
        document.getElementById('ip').textContent = location.hostname;
    </script>
</body>
</html>
EOF
    
    # Kill existing web server
    pkill -f "python.*8080.*hp-web" 2>/dev/null || true
    pkill -f "python.*80.*SimpleHTTP" 2>/dev/null || true
    
    # Start simple HTTP server
    cd /tmp/hp-web
    python3 -m http.server 80 --bind 0.0.0.0 > /dev/null 2>&1 &
    
    log "Fake HP web interface started on port 80"
}

# Stop web interface
stop_web_interface() {
    log "Stopping fake HP web interface..."
    pkill -f "python.*http.server.*80" 2>/dev/null || true
    rm -rf /tmp/hp-web 2>/dev/null || true
    log "Web interface stopped"
}

# Enable stealth mode
enable_stealth() {
    log "=== ENABLING STEALTH MODE ==="
    
    spoof_mac
    set_hostname
    setup_mdns
    start_printer_ports
    start_web_interface
    
    log "=== STEALTH MODE ENABLED ==="
    log "Device now appears as: HP LaserJet Pro MFP M428fdw"
}

# Disable stealth mode
disable_stealth() {
    log "=== DISABLING STEALTH MODE ==="
    
    stop_web_interface
    stop_printer_ports
    remove_mdns
    restore_hostname
    restore_mac
    
    log "=== STEALTH MODE DISABLED ==="
}

# Show current status
show_status() {
    echo "=== STEALTH STATUS ==="
    echo "Hostname: $(hostname)"
    echo "MAC Address: $(ip link show "$INTERFACE" 2>/dev/null | grep ether | awk '{print $2}')"
    echo ""
    echo "Listening Ports:"
    ss -tlnp 2>/dev/null | grep -E "(80|515|631|9100)" || echo "  No printer ports active"
    echo ""
    echo "Avahi Service:"
    ls -la /etc/avahi/services/printer.service 2>/dev/null || echo "  No mDNS advertisement"
}

# Main
case "${1:-}" in
    enable|start)
        enable_stealth
        ;;
    disable|stop)
        disable_stealth
        ;;
    status)
        show_status
        ;;
    *)
        echo "Usage: $0 {enable|disable|status}"
        exit 1
        ;;
esac

exit 0
