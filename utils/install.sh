#!/bin/bash

# Single-use auto-update installer
# Hardcoded repository and settings

set -e

REPO_URL="https://github.com/mastermind-mayhem/Penny.git"
INSTALL_DIR="/etc/penny"
UPDATE_INTERVAL=300

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run with sudo privileges."
    echo "Please try again with 'sudo': sudo ./$0"
    exit 1
fi

# Check if git is available
if ! command -v git >/dev/null 2>&1; then
    echo "Error: Git is not installed"
    exit 1
fi


# Clone repository
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
fi

git clone "$REPO_URL" "$INSTALL_DIR"
INSTALL_DIR=$(realpath "$INSTALL_DIR")

chmod +x "$INSTALL_DIR/utils/update.sh"
chmod +x "$INSTALL_DIR/utils/install.sh"
echo "files installed to $INSTALL_DIR"

# Create systemd service file
cat > /etc/systemd/system/penny-update.service << 'EOF'
[Unit]
Description=Update Penny Git Repository
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/sudo /etc/penny/update.sh
User=root
EOF

# Create systemd timer file
cat > /etc/systemd/system/penny-update.timer << 'EOF'
[Unit]
Description=Run Penny Update Every 5 Minutes
Requires=penny-update.service

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Reload systemd and start timer
systemctl daemon-reload
systemctl enable penny-update.timer
systemctl start penny-update.timer

echo "Update service created and started. Runs every 5 minutes."



