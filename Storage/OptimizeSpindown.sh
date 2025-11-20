#!/bin/bash
#
# OptimizeSpindown.sh
#
# A script to install and configure a systemd service for spinning down idle drives in Proxmox (or general Linux),
# as well as a method to uninstall hdparm and remove the service, reverting to default.
#
# Usage:
#   # Install/Configure:
#   OptimizeSpindown.sh <time_in_minutes> <device_path1> [<device_path2> ...]
#
#   # Uninstall (removes hdparm, spindown service, and helper script):
#   OptimizeSpindown.sh uninstall
#
# Examples:
#   # Set a 15-minute spindown for /dev/sda and /dev/sdb
#   OptimizeSpindown.sh 15 /dev/sda /dev/sdb
#
#   # Uninstall and remove all changes
#   OptimizeSpindown.sh uninstall
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

###############################################################################
# Global Variables
###############################################################################
HELPER_SCRIPT="/usr/bin/spindown-logic.sh"
SERVICE_FILE="/etc/systemd/system/spindown.service"

###############################################################################
# Main
###############################################################################
__check_root__ # Ensure the script is run as root

# Check arguments
if [[ $# -lt 1 ]]; then
    __err__ "Missing required arguments"
    echo "Usage:"
    echo "  $0 <time_in_minutes> <device_path1> [<device_path2> ...]"
    echo "  $0 uninstall"
    exit 64
fi

###############################################################################
# Uninstall Mode
###############################################################################
if [[ "$1" == "uninstall" ]]; then
    echo "Uninstall mode selected. Reverting changes..."

    # Stop and disable the service if it exists
    if systemctl is-enabled spindown.service &>/dev/null; then
        systemctl stop spindown.service || true
        systemctl disable spindown.service || true
    fi

    # Remove the systemd service file
    if [[ -f "$SERVICE_FILE" ]]; then
        rm -f "$SERVICE_FILE"
        echo "Removed \"$SERVICE_FILE\""
    fi

    # Remove the helper script
    if [[ -f "$HELPER_SCRIPT" ]]; then
        rm -f "$HELPER_SCRIPT"
        echo "Removed \"$HELPER_SCRIPT\""
    fi

    # Remove hdparm if installed
    if command -v hdparm &>/dev/null; then
        echo "Removing hdparm..."
        apt-get remove -y hdparm || echo "Warning: Could not remove hdparm automatically."
    fi

    systemctl daemon-reload
    echo "Uninstall complete. System reverted to default for drive spindown configuration."
    exit 0
fi

###############################################################################
# Installation Mode
###############################################################################
# Validate arguments
if [[ $# -lt 2 ]]; then
    __err__ "Missing required arguments for installation mode"
    echo "Usage: $0 <time_in_minutes> <device_path1> [<device_path2> ...]"
    exit 64
fi

SPINDOWN_MINUTES="$1"
shift
DEVICES=("$@")

# Validate SPINDOWN_MINUTES
if ! [[ "$SPINDOWN_MINUTES" =~ ^[0-9]+$ ]]; then
    __err__ "<time_in_minutes> must be a positive integer"
    exit 64
fi

# Install hdparm if missing
__install_or_prompt__ "hdparm" || {
    echo "Error: 'hdparm' is required but cannot be installed."
    exit 4
}

# Prompt whether to keep newly installed packages at the end
__prompt_keep_installed_packages__

###############################################################################
# Convert Minutes to hdparm -S Value
###############################################################################
if [[ "$SPINDOWN_MINUTES" -le 20 ]]; then
    HDPARM_VALUE=$((SPINDOWN_MINUTES * 12))
else
    HDPARM_VALUE=241
fi

###############################################################################
# Create Helper Script
###############################################################################
cat <<EOF >"$HELPER_SCRIPT"
#!/bin/bash
#
# spindown-logic.sh
#
# Auto-generated script for spinning down drives.
# Do not edit directly; edits may be overwritten by the installation script.

set -euo pipefail

echo "Applying hdparm spindown settings..."
EOF

for devPath in "${DEVICES[@]}"; do
    echo "hdparm -S $HDPARM_VALUE \"$devPath\" || echo \"Warning: Failed to set spindown on $devPath\"" >>"$HELPER_SCRIPT"
done

chmod +x "$HELPER_SCRIPT"

###############################################################################
# Create Systemd Service
###############################################################################
cat <<EOF >"$SERVICE_FILE"
[Unit]
Description=Spin down drives after idle time
After=multi-user.target

[Service]
Type=oneshot
ExecStart=$HELPER_SCRIPT
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable spindown.service
systemctl start spindown.service

###############################################################################
# Final Output
###############################################################################
echo "Spindown service installed and started."
echo "Drives: \"${DEVICES[*]}\""
echo "Spindown time (minutes): \"$SPINDOWN_MINUTES\""
echo "hdparm -S value used: \"$HDPARM_VALUE\""
echo "Done."

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-11-20: ArgumentParser.sh sourced (hybrid for uninstall vs variable args)
# - 2025-11-20: Pending validation
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# -
#
# Known issues:
# - Pending validation
# -
#

