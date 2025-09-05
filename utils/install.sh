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




