#!/bin/bash
#================================================================
# PHANTOM PRINTER V2 - C2 MODULE
# Multi-channel Command & Control with configurable heartbeat
#================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${SCRIPT_DIR}/../.."
CONFIG_FILE="${BASE_DIR}/config/dropbox.conf"
LOG_FILE="${BASE_DIR}/logs/c2.log"

#================================================================
# DEFAULT CONFIGURATION
#================================================================

# Heartbeat timing (can be overridden in dropbox.conf)
C2_BEACON_INTERVAL="${C2_BEACON_INTERVAL:-300}"      # 5 minutes default (stealth)
C2_BEACON_JITTER="${C2_BEACON_JITTER:-120}"          # ±2 minutes jitter
C2_HEARTBEAT_MODE="${C2_HEARTBEAT_MODE:-stealth}"    # aggressive|balanced|stealth|sleep

# Quiet mode - only send Discord alerts on status changes, not every heartbeat
C2_QUIET_MODE="${C2_QUIET_MODE:-true}"
C2_QUIET_SUMMARY_INTERVAL="${C2_QUIET_SUMMARY_INTERVAL:-3600}"  # Summary every hour

# C2 Server settings
C2_PRIMARY_HOST="${C2_PRIMARY_HOST:-}"
C2_PRIMARY_PORT="${C2_PRIMARY_PORT:-22}"
C2_PRIMARY_USER="${C2_PRIMARY_USER:-dropbox}"
C2_TUNNEL_PORT="${C2_TUNNEL_PORT:-2222}"

# n8n webhook
N8N_WEBHOOK_URL="${N8N_WEBHOOK_URL:-}"
N8N_API_KEY="${N8N_API_KEY:-}"

# Dropbox identity
DROPBOX_ID="${DROPBOX_ID:-phantom-001}"

#================================================================
# LOGGING
#================================================================

log() {
    local level="$1"
    local msg="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [C2] [${level}] ${msg}" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$1"; }
log_warn() { log "WARN" "$1"; }
log_error() { log "ERROR" "$1"; }

#================================================================
# LOAD CONFIGURATION
#================================================================

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Loading configuration from ${CONFIG_FILE}"
        source "$CONFIG_FILE"
    else
        log_warn "Config file not found, using defaults"
    fi
    
    # Apply heartbeat mode presets
    apply_heartbeat_mode
    
    mkdir -p "$(dirname "$LOG_FILE")"
}

apply_heartbeat_mode() {
    case "$C2_HEARTBEAT_MODE" in
        aggressive)
            C2_BEACON_INTERVAL="${C2_BEACON_INTERVAL:-30}"
            C2_BEACON_JITTER="${C2_BEACON_JITTER:-10}"
            ;;
        balanced)
            C2_BEACON_INTERVAL="${C2_BEACON_INTERVAL:-60}"
            C2_BEACON_JITTER="${C2_BEACON_JITTER:-30}"
            ;;
        stealth)
            C2_BEACON_INTERVAL="${C2_BEACON_INTERVAL:-300}"
            C2_BEACON_JITTER="${C2_BEACON_JITTER:-120}"
            ;;
        sleep)
            C2_BEACON_INTERVAL="${C2_BEACON_INTERVAL:-3600}"
            C2_BEACON_JITTER="${C2_BEACON_JITTER:-600}"
            ;;
        custom)
            # Use values from config file directly
            ;;
        *)
            log_warn "Unknown heartbeat mode: ${C2_HEARTBEAT_MODE}, using stealth"
            C2_BEACON_INTERVAL=300
            C2_BEACON_JITTER=120
            ;;
    esac
    
    log_info "Heartbeat mode: ${C2_HEARTBEAT_MODE} (interval=${C2_BEACON_INTERVAL}s, jitter=±${C2_BEACON_JITTER}s)"
}

#================================================================
# SYSTEM INFO COLLECTION
#================================================================

get_system_info() {
    local ip_address=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || echo "unknown")
    local mac_address=$(ip link show eth0 2>/dev/null | awk '/ether/ {print $2}' || echo "unknown")
    local hostname=$(hostname)
    local uptime=$(uptime -p 2>/dev/null || echo "unknown")
    local load=$(cat /proc/loadavg 2>/dev/null | awk '{print $1}' || echo "0")
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    
    cat << EOF
{
    "dropbox_id": "${DROPBOX_ID}",
    "ip_address": "${ip_address}",
    "mac_address": "${mac_address}",
    "hostname": "${hostname}",
    "uptime": "${uptime}",
    "load": "${load}",
    "timestamp": "${timestamp}",
    "mode": "${C2_HEARTBEAT_MODE}",
    "quiet_mode": ${C2_QUIET_MODE}
}
EOF
}

#================================================================
# HEARTBEAT FUNCTIONS
#================================================================

# Track state for quiet mode
LAST_SUMMARY_TIME=0
HEARTBEAT_COUNT=0
LAST_STATUS="unknown"

calculate_sleep_time() {
    local base="$C2_BEACON_INTERVAL"
    local jitter="$C2_BEACON_JITTER"
    
    # Random jitter: interval + random(-jitter, +jitter)
    local random_offset=$(( (RANDOM % (jitter * 2 + 1)) - jitter ))
    local sleep_time=$(( base + random_offset ))
    
    # Ensure minimum 10 seconds
    if [[ $sleep_time -lt 10 ]]; then
        sleep_time=10
    fi
    
    echo "$sleep_time"
}

send_heartbeat() {
    local notify_discord="$1"  # true/false - whether to send Discord notification
    
    if [[ -z "$N8N_WEBHOOK_URL" ]] || [[ "$N8N_WEBHOOK_URL" == "https://your-n8n-instance.com" ]]; then
        log_warn "N8N_WEBHOOK_URL not configured, skipping heartbeat"
        return 1
    fi
    
    local payload=$(get_system_info)
    
    # Add quiet mode flag to control Discord notification on n8n side
    if [[ "$notify_discord" == "false" ]]; then
        payload=$(echo "$payload" | sed 's/}$/,"skip_discord": true}/')
    fi
    
    local response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "X-API-Key: ${N8N_API_KEY}" \
        -H "X-Dropbox-ID: ${DROPBOX_ID}" \
        -d "$payload" \
        "${N8N_WEBHOOK_URL}/webhook/dropbox-heartbeat" \
        --connect-timeout 10 \
        --max-time 30 \
        2>/dev/null)
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    if [[ "$http_code" == "200" ]]; then
        log_info "Heartbeat sent successfully (discord=${notify_discord})"
        LAST_STATUS="online"
        return 0
    else
        log_error "Heartbeat failed: HTTP ${http_code}"
        LAST_STATUS="error"
        return 1
    fi
}

should_notify_discord() {
    # Always notify if quiet mode is disabled
    if [[ "$C2_QUIET_MODE" != "true" ]]; then
        echo "true"
        return
    fi
    
    local current_time=$(date +%s)
    
    # Notify on first heartbeat
    if [[ $HEARTBEAT_COUNT -eq 0 ]]; then
        echo "true"
        return
    fi
    
    # Notify on status change
    if [[ "$LAST_STATUS" != "online" ]]; then
        echo "true"
        return
    fi
    
    # Notify on summary interval (hourly by default)
    local time_since_summary=$(( current_time - LAST_SUMMARY_TIME ))
    if [[ $time_since_summary -ge $C2_QUIET_SUMMARY_INTERVAL ]]; then
        LAST_SUMMARY_TIME=$current_time
        echo "true"
        return
    fi
    
    echo "false"
}

#================================================================
# MAIN HEARTBEAT LOOP
#================================================================

heartbeat_loop() {
    log_info "Starting heartbeat loop"
    log_info "Quiet mode: ${C2_QUIET_MODE}"
    log_info "Summary interval: ${C2_QUIET_SUMMARY_INTERVAL}s"
    
    LAST_SUMMARY_TIME=$(date +%s)
    
    while true; do
        HEARTBEAT_COUNT=$((HEARTBEAT_COUNT + 1))
        
        local notify=$(should_notify_discord)
        
        if send_heartbeat "$notify"; then
            if [[ "$notify" == "true" ]]; then
                log_info "Heartbeat #${HEARTBEAT_COUNT} sent with Discord notification"
            else
                log_info "Heartbeat #${HEARTBEAT_COUNT} sent (quiet)"
            fi
        else
            log_error "Heartbeat #${HEARTBEAT_COUNT} failed"
        fi
        
        local sleep_time=$(calculate_sleep_time)
        log_info "Next heartbeat in ${sleep_time}s"
        sleep "$sleep_time"
    done
}

#================================================================
# SEND ALERT (for important events)
#================================================================

send_alert() {
    local alert_type="$1"
    local level="$2"
    local message="$3"
    
    if [[ -z "$N8N_WEBHOOK_URL" ]]; then
        log_warn "N8N_WEBHOOK_URL not configured"
        return 1
    fi
    
    local payload=$(cat << EOF
{
    "dropbox_id": "${DROPBOX_ID}",
    "type": "${alert_type}",
    "level": "${level}",
    "message": "${message}",
    "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF
)
    
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "X-API-Key: ${N8N_API_KEY}" \
        -H "X-Dropbox-ID: ${DROPBOX_ID}" \
        -d "$payload" \
        "${N8N_WEBHOOK_URL}/webhook/dropbox-alert" \
        --connect-timeout 10 \
        --max-time 30
    
    log_info "Alert sent: ${alert_type} - ${message}"
}

#================================================================
# SERVICE CONTROL
#================================================================

start_c2() {
    log_info "Starting C2 module"
    load_config
    
    # Send online alert (always notifies Discord)
    send_alert "online" "info" "Phantom Printer coming online"
    
    # Start heartbeat loop
    heartbeat_loop
}

stop_c2() {
    log_info "Stopping C2 module"
    send_alert "offline" "info" "Phantom Printer going offline (graceful)"
    
    # Kill any background processes
    pkill -f "c2.sh" 2>/dev/null || true
}

status_c2() {
    if pgrep -f "c2.sh.*heartbeat_loop" > /dev/null; then
        echo "C2 module is running"
        echo "Mode: ${C2_HEARTBEAT_MODE}"
        echo "Interval: ${C2_BEACON_INTERVAL}s (±${C2_BEACON_JITTER}s jitter)"
        echo "Quiet mode: ${C2_QUIET_MODE}"
        return 0
    else
        echo "C2 module is not running"
        return 1
    fi
}

#================================================================
# COMMAND LINE INTERFACE
#================================================================

show_help() {
    cat << EOF
Phantom Printer V2 - C2 Module

Usage: $0 <command> [options]

Commands:
    start           Start C2 heartbeat loop
    stop            Stop C2 module
    status          Check C2 status
    heartbeat       Send single heartbeat (for testing)
    alert           Send alert: $0 alert <type> <level> <message>
    set-mode        Change heartbeat mode: $0 set-mode <aggressive|balanced|stealth|sleep>
    set-interval    Set custom interval: $0 set-interval <seconds> [jitter]
    quiet-on        Enable quiet mode (hourly summaries)
    quiet-off       Disable quiet mode (all heartbeats to Discord)

Heartbeat Modes:
    aggressive      30s interval, ±10s jitter  (frequent check-ins)
    balanced        60s interval, ±30s jitter  (normal operations)
    stealth         300s interval, ±120s jitter (reduced footprint)
    sleep           3600s interval, ±600s jitter (minimal activity)

Examples:
    $0 start
    $0 set-mode stealth
    $0 set-interval 600 180
    $0 quiet-on
    $0 alert recon_complete info "Network scan finished"

EOF
}

set_mode() {
    local mode="$1"
    
    if [[ ! "$mode" =~ ^(aggressive|balanced|stealth|sleep)$ ]]; then
        echo "Invalid mode. Use: aggressive, balanced, stealth, or sleep"
        exit 1
    fi
    
    # Update config file
    if [[ -f "$CONFIG_FILE" ]]; then
        if grep -q "^C2_HEARTBEAT_MODE=" "$CONFIG_FILE"; then
            sed -i "s/^C2_HEARTBEAT_MODE=.*/C2_HEARTBEAT_MODE=\"${mode}\"/" "$CONFIG_FILE"
        else
            echo "C2_HEARTBEAT_MODE=\"${mode}\"" >> "$CONFIG_FILE"
        fi
        echo "Heartbeat mode set to: ${mode}"
        echo "Restart C2 module for changes to take effect"
    else
        echo "Config file not found: ${CONFIG_FILE}"
        exit 1
    fi
}

set_interval() {
    local interval="$1"
    local jitter="${2:-$(( interval / 3 ))}"  # Default jitter is 1/3 of interval
    
    if [[ ! "$interval" =~ ^[0-9]+$ ]] || [[ $interval -lt 10 ]]; then
        echo "Invalid interval. Must be a number >= 10 seconds"
        exit 1
    fi
    
    if [[ -f "$CONFIG_FILE" ]]; then
        # Set custom mode
        if grep -q "^C2_HEARTBEAT_MODE=" "$CONFIG_FILE"; then
            sed -i "s/^C2_HEARTBEAT_MODE=.*/C2_HEARTBEAT_MODE=\"custom\"/" "$CONFIG_FILE"
        else
            echo "C2_HEARTBEAT_MODE=\"custom\"" >> "$CONFIG_FILE"
        fi
        
        # Set interval
        if grep -q "^C2_BEACON_INTERVAL=" "$CONFIG_FILE"; then
            sed -i "s/^C2_BEACON_INTERVAL=.*/C2_BEACON_INTERVAL=\"${interval}\"/" "$CONFIG_FILE"
        else
            echo "C2_BEACON_INTERVAL=\"${interval}\"" >> "$CONFIG_FILE"
        fi
        
        # Set jitter
        if grep -q "^C2_BEACON_JITTER=" "$CONFIG_FILE"; then
            sed -i "s/^C2_BEACON_JITTER=.*/C2_BEACON_JITTER=\"${jitter}\"/" "$CONFIG_FILE"
        else
            echo "C2_BEACON_JITTER=\"${jitter}\"" >> "$CONFIG_FILE"
        fi
        
        echo "Custom interval set: ${interval}s (±${jitter}s jitter)"
        echo "Restart C2 module for changes to take effect"
    else
        echo "Config file not found: ${CONFIG_FILE}"
        exit 1
    fi
}

toggle_quiet_mode() {
    local enabled="$1"
    
    if [[ -f "$CONFIG_FILE" ]]; then
        if grep -q "^C2_QUIET_MODE=" "$CONFIG_FILE"; then
            sed -i "s/^C2_QUIET_MODE=.*/C2_QUIET_MODE=\"${enabled}\"/" "$CONFIG_FILE"
        else
            echo "C2_QUIET_MODE=\"${enabled}\"" >> "$CONFIG_FILE"
        fi
        
        if [[ "$enabled" == "true" ]]; then
            echo "Quiet mode ENABLED - Discord will only receive hourly summaries"
        else
            echo "Quiet mode DISABLED - Discord will receive every heartbeat"
        fi
        echo "Restart C2 module for changes to take effect"
    else
        echo "Config file not found: ${CONFIG_FILE}"
        exit 1
    fi
}

#================================================================
# MAIN
#================================================================

main() {
    local command="${1:-}"
    
    case "$command" in
        start)
            start_c2
            ;;
        stop)
            stop_c2
            ;;
        status)
            load_config
            status_c2
            ;;
        heartbeat)
            load_config
            send_heartbeat "true"
            ;;
        alert)
            load_config
            send_alert "${2:-test}" "${3:-info}" "${4:-Test alert}"
            ;;
        set-mode)
            set_mode "$2"
            ;;
        set-interval)
            set_interval "$2" "$3"
            ;;
        quiet-on)
            toggle_quiet_mode "true"
            ;;
        quiet-off)
            toggle_quiet_mode "false"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
}

main "$@"
