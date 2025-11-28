#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# ARM SCRIPT - Prepare Dropbox for Deployment
# ══════════════════════════════════════════════════════════════════════════════
# Run this AFTER you've configured and tested everything.
# This locks down the device for actual field deployment.
# ══════════════════════════════════════════════════════════════════════════════

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

DROPBOX_DIR="/home/kali/dropbox-v2"

log() {
    echo -e "${GREEN}[+]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# ──────────────────────────────────────────────────────────────────────────────
# PRE-FLIGHT CHECKS
# ──────────────────────────────────────────────────────────────────────────────

preflight_checks() {
    echo ""
    echo -e "${YELLOW}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}              PRE-FLIGHT CHECKS${NC}"
    echo -e "${YELLOW}════════════════════════════════════════════════════════════════${NC}"
    
    local errors=0
    
    # Check config exists
    if [[ -f "${DROPBOX_DIR}/config/dropbox.conf" ]]; then
        echo -e "${GREEN}[✓]${NC} Config file exists"
    else
        echo -e "${RED}[✗]${NC} Config file missing!"
        ((errors++))
    fi
    
    # Check C2 is configured (not default)
    if grep -q "YOUR_C2_IP" "${DROPBOX_DIR}/config/dropbox.conf" 2>/dev/null; then
        echo -e "${RED}[✗]${NC} C2 server not configured (still shows YOUR_C2_IP)"
        ((errors++))
    else
        echo -e "${GREEN}[✓]${NC} C2 server configured"
    fi
    
    # Check SSH key exists
    if [[ -f "/home/kali/.ssh/id_dropbox" ]]; then
        echo -e "${GREEN}[✓]${NC} SSH key exists"
    else
        echo -e "${RED}[✗]${NC} SSH key missing!"
        ((errors++))
    fi
    
    # Check network connectivity
    if ping -c 1 8.8.8.8 &>/dev/null; then
        echo -e "${GREEN}[✓]${NC} Network connectivity OK"
    else
        echo -e "${YELLOW}[!]${NC} No internet (may be OK if using local network)"
    fi
    
    # Check services exist
    if systemctl list-unit-files | grep -q "dropbox-main"; then
        echo -e "${GREEN}[✓]${NC} Systemd services installed"
    else
        echo -e "${RED}[✗]${NC} Systemd services not installed!"
        ((errors++))
    fi
    
    echo ""
    
    if [[ $errors -gt 0 ]]; then
        echo -e "${RED}Found $errors error(s). Please fix before arming.${NC}"
        exit 1
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# ARM THE DROPBOX
# ──────────────────────────────────────────────────────────────────────────────

arm_dropbox() {
    echo ""
    echo -e "${YELLOW}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}              ARMING DROPBOX FOR DEPLOYMENT${NC}"
    echo -e "${YELLOW}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Confirm
    echo -e "${RED}WARNING: This will:${NC}"
    echo "  - Disable HDMI output"
    echo "  - Enable all dropbox services on boot"
    echo "  - Clear bash history"
    echo "  - The device will be ready for field deployment"
    echo ""
    read -p "Are you sure? (type 'ARM' to confirm): " confirm
    
    if [[ "$confirm" != "ARM" ]]; then
        echo "Aborted."
        exit 0
    fi
    
    echo ""
    
    # Disable HDMI
    log "Disabling HDMI output..."
    if [[ -f /boot/firmware/config.txt ]]; then
        CONFIG_FILE="/boot/firmware/config.txt"
    else
        CONFIG_FILE="/boot/config.txt"
    fi
    
    if [[ -f "$CONFIG_FILE" ]]; then
        if ! grep -q "hdmi_blanking=2" "$CONFIG_FILE"; then
            echo "" >> "$CONFIG_FILE"
            echo "# Disabled for stealth deployment" >> "$CONFIG_FILE"
            echo "hdmi_blanking=2" >> "$CONFIG_FILE"
        fi
        log "HDMI will be disabled on next boot"
    fi
    
    # Enable services
    log "Enabling dropbox services..."
    systemctl enable dropbox-stealth.service 2>/dev/null || true
    systemctl enable dropbox-main.service 2>/dev/null || true
    systemctl enable dropbox-payloads.service 2>/dev/null || true
    
    # Clear history
    log "Clearing bash history..."
    history -c
    > ~/.bash_history
    > /home/kali/.bash_history 2>/dev/null || true
    > /root/.bash_history 2>/dev/null || true
    
    # Set permissions
    log "Locking down permissions..."
    chmod 600 /home/kali/.ssh/id_dropbox 2>/dev/null || true
    chmod 700 /home/kali/.ssh 2>/dev/null || true
    
    # Create armed flag
    touch "${DROPBOX_DIR}/.armed"
    date > "${DROPBOX_DIR}/.armed"
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}              DROPBOX ARMED AND READY${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "On next boot, the dropbox will:"
    echo -e "  1. Boot to CLI (no desktop)"
    echo -e "  2. No HDMI output"
    echo -e "  3. Auto-enable HP printer disguise"
    echo -e "  4. Connect to C2"
    echo -e "  5. Begin operations"
    echo ""
    echo -e "${YELLOW}Reboot now to deploy: sudo reboot${NC}"
    echo ""
}

# ──────────────────────────────────────────────────────────────────────────────
# DISARM (for maintenance)
# ──────────────────────────────────────────────────────────────────────────────

disarm_dropbox() {
    echo ""
    log "Disarming dropbox for maintenance..."
    
    # Re-enable HDMI
    if [[ -f /boot/firmware/config.txt ]]; then
        CONFIG_FILE="/boot/firmware/config.txt"
    else
        CONFIG_FILE="/boot/config.txt"
    fi
    
    sed -i '/hdmi_blanking=2/d' "$CONFIG_FILE" 2>/dev/null || true
    sed -i '/Disabled for stealth deployment/d' "$CONFIG_FILE" 2>/dev/null || true
    
    # Remove armed flag
    rm -f "${DROPBOX_DIR}/.armed"
    
    log "HDMI re-enabled. Reboot to access display."
    echo ""
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────────────────────────────────

case "${1:-}" in
    arm|"")
        preflight_checks
        arm_dropbox
        ;;
    disarm)
        disarm_dropbox
        ;;
    check)
        preflight_checks
        ;;
    *)
        echo "Usage: $0 {arm|disarm|check}"
        echo ""
        echo "  arm     - Prepare for field deployment (disables HDMI)"
        echo "  disarm  - Re-enable HDMI for maintenance"
        echo "  check   - Run pre-flight checks only"
        exit 1
        ;;
esac
