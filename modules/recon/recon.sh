#!/bin/bash
#================================================================
# PHANTOM PRINTER V2 - RECON MODULE
# Automated network reconnaissance
#================================================================

set -e

# Source configuration
CONFIG_FILE="/home/kali/dropbox-v2/config/dropbox.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Directories
LOOT_DIR="/home/kali/dropbox-v2/loot"
SCAN_DIR="$LOOT_DIR/scans"
LOG_FILE="/home/kali/dropbox-v2/logs/recon.log"

mkdir -p "$SCAN_DIR" "$LOOT_DIR/creds" "$LOOT_DIR/hashes" "$(dirname "$LOG_FILE")"

# Defaults
INTERFACE="${INTERFACE:-eth0}"

# Log function
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [RECON] $1"
    echo "$msg" | tee -a "$LOG_FILE"
    logger -t "dropbox-recon" "$1"
}

# Get local network info
get_network_info() {
    local ip=$(ip -4 addr show "$INTERFACE" 2>/dev/null | grep inet | awk '{print $2}')
    local gateway=$(ip route | grep default | awk '{print $3}' | head -1)
    local network=$(echo "$ip" | sed 's/\.[0-9]*\//.0\//')
    
    echo "IP: $ip"
    echo "Gateway: $gateway"
    echo "Network: $network"
}

# ARP scan - fast layer 2 discovery
arp_scan() {
    log "Starting ARP scan..."
    local output="$SCAN_DIR/arp-scan-$(date +%Y%m%d-%H%M%S).txt"
    
    if command -v arp-scan &>/dev/null; then
        arp-scan --interface="$INTERFACE" --localnet 2>/dev/null | tee "$output"
    else
        log "arp-scan not installed, using arping fallback"
        # Fallback to ping sweep
        local network=$(ip -4 addr show "$INTERFACE" | grep inet | awk '{print $2}' | cut -d/ -f1 | sed 's/\.[0-9]*$/.0/')
        for i in $(seq 1 254); do
            ping -c 1 -W 1 "${network%.*}.$i" &>/dev/null && echo "${network%.*}.$i" &
        done | tee "$output"
        wait
    fi
    
    log "ARP scan complete: $output"
}

# Nmap discovery scan
nmap_discovery() {
    log "Starting nmap discovery scan..."
    local network=$(ip -4 addr show "$INTERFACE" | grep inet | awk '{print $2}' | sed 's/\.[0-9]*\//.0\//')
    local output="$SCAN_DIR/nmap-discovery-$(date +%Y%m%d-%H%M%S)"
    
    nmap -sn -T4 "$network" -oA "$output" 2>/dev/null
    
    # Extract live hosts
    grep "Nmap scan report" "${output}.nmap" 2>/dev/null | awk '{print $5}' > "$SCAN_DIR/live-hosts.txt"
    
    local count=$(wc -l < "$SCAN_DIR/live-hosts.txt")
    log "Discovery complete: $count live hosts found"
}

# Nmap service scan on live hosts
nmap_services() {
    log "Starting service enumeration..."
    
    if [[ ! -f "$SCAN_DIR/live-hosts.txt" ]]; then
        log "No live hosts file, running discovery first"
        nmap_discovery
    fi
    
    local output="$SCAN_DIR/nmap-services-$(date +%Y%m%d-%H%M%S)"
    
    nmap -sV -sC -T4 -iL "$SCAN_DIR/live-hosts.txt" -oA "$output" 2>/dev/null
    
    log "Service scan complete: ${output}.nmap"
}

# Quick port scan with masscan
masscan_quick() {
    log "Starting masscan quick scan..."
    local network=$(ip -4 addr show "$INTERFACE" | grep inet | awk '{print $2}' | sed 's/\.[0-9]*\//.0\//')
    local output="$SCAN_DIR/masscan-$(date +%Y%m%d-%H%M%S).txt"
    
    if command -v masscan &>/dev/null; then
        masscan "$network" -p21,22,23,25,53,80,110,139,143,443,445,993,995,1433,3306,3389,5432,8080,8443 \
            --rate=1000 -oL "$output" 2>/dev/null
        log "Masscan complete: $output"
    else
        log "masscan not installed, skipping"
    fi
}

# SMB enumeration
smb_enum() {
    log "Starting SMB enumeration..."
    local output="$SCAN_DIR/smb-enum-$(date +%Y%m%d-%H%M%S).txt"
    
    if [[ ! -f "$SCAN_DIR/live-hosts.txt" ]]; then
        log "No live hosts, running discovery first"
        nmap_discovery
    fi
    
    if command -v crackmapexec &>/dev/null; then
        # Enumerate shares
        crackmapexec smb "$SCAN_DIR/live-hosts.txt" --shares 2>/dev/null | tee "$output"
        
        # Check for signing
        crackmapexec smb "$SCAN_DIR/live-hosts.txt" --gen-relay-list "$SCAN_DIR/relay-targets.txt" 2>/dev/null
        
        log "SMB enumeration complete"
    else
        log "crackmapexec not installed, trying enum4linux"
        
        while read -r host; do
            echo "=== $host ===" >> "$output"
            enum4linux -a "$host" 2>/dev/null >> "$output" || true
        done < "$SCAN_DIR/live-hosts.txt"
    fi
}

# Start Responder in analyze mode
responder_analyze() {
    log "Starting Responder in analyze mode..."
    
    if ! command -v responder &>/dev/null; then
        log "Responder not installed"
        return 1
    fi
    
    # Run in analyze mode (passive, no poisoning)
    responder -I "$INTERFACE" -A &
    local pid=$!
    echo "$pid" > /tmp/responder.pid
    
    log "Responder started (PID: $pid) in analyze mode"
}

# Stop Responder
responder_stop() {
    if [[ -f /tmp/responder.pid ]]; then
        kill "$(cat /tmp/responder.pid)" 2>/dev/null || true
        rm -f /tmp/responder.pid
        log "Responder stopped"
    fi
}

# Full recon suite
full_recon() {
    log "=== STARTING FULL RECONNAISSANCE ==="
    
    echo "Network Info:"
    get_network_info
    echo ""
    
    arp_scan
    nmap_discovery
    masscan_quick
    nmap_services
    smb_enum
    
    log "=== FULL RECONNAISSANCE COMPLETE ==="
    log "Results saved to: $SCAN_DIR"
    
    # List results
    echo ""
    echo "=== SCAN RESULTS ==="
    ls -la "$SCAN_DIR"
}

# Quick recon (just discovery)
quick_recon() {
    log "=== STARTING QUICK RECONNAISSANCE ==="
    
    get_network_info
    arp_scan
    nmap_discovery
    
    log "=== QUICK RECONNAISSANCE COMPLETE ==="
    
    # Show live hosts
    if [[ -f "$SCAN_DIR/live-hosts.txt" ]]; then
        echo ""
        echo "=== LIVE HOSTS ==="
        cat "$SCAN_DIR/live-hosts.txt"
    fi
}

# Show status
show_status() {
    echo "=== RECON STATUS ==="
    echo "Interface: $INTERFACE"
    get_network_info
    echo ""
    echo "Scan Directory: $SCAN_DIR"
    echo "Scans on disk:"
    ls -lh "$SCAN_DIR" 2>/dev/null || echo "  No scans yet"
    echo ""
    echo "Live hosts file:"
    if [[ -f "$SCAN_DIR/live-hosts.txt" ]]; then
        wc -l < "$SCAN_DIR/live-hosts.txt" | xargs echo "  Count:"
    else
        echo "  Not created yet"
    fi
}

# Main
case "${1:-}" in
    full)
        full_recon
        ;;
    quick)
        quick_recon
        ;;
    arp)
        arp_scan
        ;;
    discovery|discover)
        nmap_discovery
        ;;
    services)
        nmap_services
        ;;
    masscan)
        masscan_quick
        ;;
    smb)
        smb_enum
        ;;
    responder)
        responder_analyze
        ;;
    responder-stop)
        responder_stop
        ;;
    status)
        show_status
        ;;
    *)
        echo "Usage: $0 {full|quick|arp|discovery|services|masscan|smb|responder|status}"
        echo ""
        echo "Commands:"
        echo "  full       - Run full recon suite"
        echo "  quick      - Quick discovery only"
        echo "  arp        - ARP scan only"
        echo "  discovery  - Nmap host discovery"
        echo "  services   - Nmap service scan"
        echo "  masscan    - Fast port scan"
        echo "  smb        - SMB enumeration"
        echo "  responder  - Start Responder (analyze mode)"
        echo "  status     - Show recon status"
        exit 1
        ;;
esac

exit 0
