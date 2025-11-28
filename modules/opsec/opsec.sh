#!/bin/bash
#================================================================
# PHANTOM PRINTER V2 - OPSEC MODULE
# Self-destruct, kill switch, anti-forensics
#================================================================

# Source configuration
CONFIG_FILE="/home/kali/dropbox-v2/config/dropbox.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Directories
DROPBOX_DIR="/home/kali/dropbox-v2"
LOOT_DIR="$DROPBOX_DIR/loot"
LOG_DIR="$DROPBOX_DIR/logs"
SSH_DIR="/home/kali/.ssh"

# Defaults
N8N_WEBHOOK_URL="${N8N_WEBHOOK_URL:-}"
DROPBOX_ID="${DROPBOX_ID:-phantom-001}"

# Log function (to stdout only during destruction)
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [OPSEC] $1"
}

# Send final alert before destruction
send_destruct_alert() {
    local level="$1"
    
    if [[ -n "$N8N_WEBHOOK_URL" ]]; then
        curl -s -X POST "${N8N_WEBHOOK_URL}/webhook/dropbox-alert" \
            -H "Content-Type: application/json" \
            -d "{\"dropbox_id\":\"$DROPBOX_ID\",\"type\":\"self_destruct\",\"level\":\"critical\",\"message\":\"Self-destruct initiated: $level\"}" \
            --max-time 5 2>/dev/null || true
    fi
}

# Secure file deletion
secure_delete() {
    local path="$1"
    
    if [[ -f "$path" ]]; then
        shred -vzfun 3 "$path" 2>/dev/null || rm -f "$path"
    elif [[ -d "$path" ]]; then
        find "$path" -type f -exec shred -vzfun 3 {} \; 2>/dev/null || true
        rm -rf "$path"
    fi
}

# Wipe loot directory
wipe_loot() {
    log "Wiping loot directory..."
    secure_delete "$LOOT_DIR"
    mkdir -p "$LOOT_DIR"
    log "Loot wiped"
}

# Wipe logs
wipe_logs() {
    log "Wiping logs..."
    secure_delete "$LOG_DIR"
    mkdir -p "$LOG_DIR"
    
    # Clear system logs related to dropbox
    journalctl --rotate 2>/dev/null || true
    journalctl --vacuum-time=1s 2>/dev/null || true
    
    # Clear bash history
    history -c 2>/dev/null || true
    rm -f /home/kali/.bash_history
    rm -f /root/.bash_history
    
    log "Logs wiped"
}

# Wipe SSH keys
wipe_ssh_keys() {
    log "Wiping SSH keys..."
    secure_delete "$SSH_DIR/id_dropbox"
    secure_delete "$SSH_DIR/id_dropbox.pub"
    log "SSH keys wiped"
}

# Restore original identity
restore_identity() {
    log "Restoring original identity..."
    
    # Restore hostname
    hostnamectl set-hostname "kali" 2>/dev/null || hostname "kali"
    
    # Restore MAC address
    ip link set eth0 down 2>/dev/null || true
    macchanger -p eth0 2>/dev/null || true
    ip link set eth0 up 2>/dev/null || true
    
    # Remove mDNS advertisement
    rm -f /etc/avahi/services/printer.service 2>/dev/null || true
    systemctl restart avahi-daemon 2>/dev/null || true
    
    log "Identity restored"
}

# Stop all dropbox services
stop_services() {
    log "Stopping all dropbox services..."
    
    systemctl stop dropbox-main 2>/dev/null || true
    systemctl stop dropbox-stealth 2>/dev/null || true
    systemctl stop dropbox-ssh-tunnel 2>/dev/null || true
    systemctl stop dropbox-payloads 2>/dev/null || true
    
    # Kill related processes
    pkill -f "autossh" 2>/dev/null || true
    pkill -f "responder" 2>/dev/null || true
    pkill -f "python.*http.server" 2>/dev/null || true
    pkill -f "nc.*-l" 2>/dev/null || true
    
    log "Services stopped"
}

# Disable services from starting
disable_services() {
    log "Disabling dropbox services..."
    
    systemctl disable dropbox-main 2>/dev/null || true
    systemctl disable dropbox-stealth 2>/dev/null || true
    systemctl disable dropbox-ssh-tunnel 2>/dev/null || true
    systemctl disable dropbox-payloads 2>/dev/null || true
    
    log "Services disabled"
}

# LEVEL 1: Quick wipe (loot + logs)
destruct_quick() {
    log "=== SELF-DESTRUCT: QUICK ==="
    send_destruct_alert "quick"
    
    stop_services
    wipe_loot
    wipe_logs
    restore_identity
    
    log "=== QUICK DESTRUCT COMPLETE ==="
}

# LEVEL 2: Standard wipe (+ SSH keys, config)
destruct_standard() {
    log "=== SELF-DESTRUCT: STANDARD ==="
    send_destruct_alert "standard"
    
    stop_services
    disable_services
    wipe_loot
    wipe_logs
    wipe_ssh_keys
    restore_identity
    
    # Wipe config
    secure_delete "$DROPBOX_DIR/config"
    mkdir -p "$DROPBOX_DIR/config"
    
    log "=== STANDARD DESTRUCT COMPLETE ==="
}

# LEVEL 3: Full wipe (entire dropbox directory)
destruct_full() {
    log "=== SELF-DESTRUCT: FULL ==="
    send_destruct_alert "full"
    
    stop_services
    disable_services
    restore_identity
    
    # Remove systemd services
    rm -f /etc/systemd/system/dropbox-*.service
    systemctl daemon-reload
    
    # Wipe entire dropbox directory
    secure_delete "$DROPBOX_DIR"
    
    # Wipe SSH directory
    secure_delete "$SSH_DIR"
    
    log "=== FULL DESTRUCT COMPLETE ==="
}

# LEVEL 4: Nuclear (unrecoverable)
destruct_nuclear() {
    log "=== SELF-DESTRUCT: NUCLEAR ==="
    log "WARNING: This will make the system unbootable!"
    send_destruct_alert "nuclear"
    
    stop_services
    disable_services
    restore_identity
    
    # Remove systemd services
    rm -f /etc/systemd/system/dropbox-*.service
    
    # Wipe everything
    secure_delete "$DROPBOX_DIR"
    secure_delete "$SSH_DIR"
    secure_delete "/home/kali/.bash_history"
    secure_delete "/root/.bash_history"
    
    # Clear all logs
    find /var/log -type f -exec shred -vzfun 1 {} \; 2>/dev/null || true
    
    # Corrupt boot sector (makes system unbootable)
    log "Corrupting boot sector..."
    dd if=/dev/urandom of=/dev/mmcblk0 bs=512 count=1 2>/dev/null || true
    
    log "=== NUCLEAR DESTRUCT COMPLETE - SYSTEM UNBOOTABLE ==="
    
    # Force immediate shutdown
    sync
    echo o > /proc/sysrq-trigger 2>/dev/null || poweroff -f
}

# Dead man's switch check
deadman_check() {
    local last_beacon_file="/tmp/last_beacon"
    local max_hours="${DEADMAN_HOURS:-24}"
    local max_seconds=$((max_hours * 3600))
    
    if [[ ! -f "$last_beacon_file" ]]; then
        echo "$(date +%s)" > "$last_beacon_file"
        log "Dead man's switch initialized"
        return 0
    fi
    
    local last_beacon=$(cat "$last_beacon_file")
    local now=$(date +%s)
    local diff=$((now - last_beacon))
    
    if [[ $diff -gt $max_seconds ]]; then
        log "DEAD MAN'S SWITCH TRIGGERED! No beacon in ${max_hours} hours"
        destruct_standard
        return 1
    else
        local remaining=$(( (max_seconds - diff) / 3600 ))
        log "Dead man's switch OK. ${remaining} hours remaining."
        return 0
    fi
}

# Update beacon timestamp
deadman_update() {
    echo "$(date +%s)" > /tmp/last_beacon
    log "Dead man's switch reset"
}

# Status
show_status() {
    echo "=== OPSEC STATUS ==="
    echo "Dropbox Directory: $DROPBOX_DIR"
    echo ""
    echo "Services:"
    for svc in dropbox-main dropbox-stealth dropbox-ssh-tunnel dropbox-payloads; do
        status=$(systemctl is-active "$svc" 2>/dev/null || echo "not found")
        echo "  $svc: $status"
    done
    echo ""
    echo "Dead Man's Switch:"
    if [[ -f /tmp/last_beacon ]]; then
        local last=$(cat /tmp/last_beacon)
        local now=$(date +%s)
        local hours_ago=$(( (now - last) / 3600 ))
        echo "  Last beacon: ${hours_ago} hours ago"
    else
        echo "  Not initialized"
    fi
    echo ""
    echo "Loot size: $(du -sh "$LOOT_DIR" 2>/dev/null | cut -f1 || echo "N/A")"
    echo "Log size: $(du -sh "$LOG_DIR" 2>/dev/null | cut -f1 || echo "N/A")"
}

# Confirmation prompt
confirm_destruct() {
    local level="$1"
    
    echo ""
    echo "!!! WARNING !!!"
    echo "You are about to run self-destruct level: $level"
    echo ""
    
    case "$level" in
        quick)
            echo "This will: Wipe loot, logs, restore identity"
            ;;
        standard)
            echo "This will: Wipe loot, logs, SSH keys, config, restore identity"
            ;;
        full)
            echo "This will: Delete entire dropbox installation"
            ;;
        nuclear)
            echo "THIS WILL MAKE THE SYSTEM UNBOOTABLE!"
            ;;
    esac
    
    echo ""
    read -p "Type 'DESTROY' to confirm: " confirm
    
    if [[ "$confirm" == "DESTROY" ]]; then
        return 0
    else
        echo "Aborted."
        return 1
    fi
}

# Main
case "${1:-}" in
    quick)
        if [[ "${2:-}" != "--force" ]]; then
            confirm_destruct "quick" || exit 1
        fi
        destruct_quick
        ;;
    standard)
        if [[ "${2:-}" != "--force" ]]; then
            confirm_destruct "standard" || exit 1
        fi
        destruct_standard
        ;;
    full)
        if [[ "${2:-}" != "--force" ]]; then
            confirm_destruct "full" || exit 1
        fi
        destruct_full
        ;;
    nuclear)
        if [[ "${2:-}" != "--force" ]]; then
            confirm_destruct "nuclear" || exit 1
        fi
        destruct_nuclear
        ;;
    deadman-check)
        deadman_check
        ;;
    deadman-update)
        deadman_update
        ;;
    status)
        show_status
        ;;
    *)
        echo "Usage: $0 {quick|standard|full|nuclear|deadman-check|deadman-update|status}"
        echo ""
        echo "Self-Destruct Levels:"
        echo "  quick     - Wipe loot, logs, restore identity"
        echo "  standard  - + Wipe SSH keys, config"
        echo "  full      - Delete entire dropbox installation"
        echo "  nuclear   - Make system unbootable (DANGER!)"
        echo ""
        echo "Dead Man's Switch:"
        echo "  deadman-check   - Check if triggered"
        echo "  deadman-update  - Reset timer"
        echo ""
        echo "Add --force to skip confirmation"
        exit 1
        ;;
esac

exit 0
