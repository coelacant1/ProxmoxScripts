#!/bin/bash
#
# VMAddTerminalTTYS0.sh
#
# Configures serial console (ttyS0) inside a Debian-based VM guest OS for terminal access.
# This script should be run INSIDE the VM guest, not on the Proxmox host.
# Supports both upstart (older) and systemd (modern) init systems.
# Updates GRUB to enable console output to serial port ttyS0.
#
# Usage:
#   VMAddTerminalTTYS0.sh
#
# Examples:
#   VMAddTerminalTTYS0.sh
#
# Notes:
#   - Must be run as root inside the VM guest
#   - Requires reboot to take effect
#   - For Proxmox VM serial configuration, use: qm set <vmid> --serial0 socket --vga serial0
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

# --- main --------------------------------------------------------------------
main() {
    __check_root__

    __info__ "Configuring serial console ttyS0"

    # Detect init system
    if [[ -d /run/systemd/system ]]; then
        __info__ "Detected systemd init system"

        # Enable getty on ttyS0 via systemd
        __info__ "Enabling serial-getty@ttyS0.service"
        systemctl enable serial-getty@ttyS0.service

    elif command -v initctl >/dev/null 2>&1; then
        __info__ "Detected upstart init system"

        # Create /etc/init directory
        __info__ "Creating /etc/init directory"
        mkdir -p /etc/init
        chmod 755 /etc/init

        # Create ttyS0 configuration for upstart
        __info__ "Creating /etc/init/ttyS0.conf"
        cat <<'EOF' >/etc/init/ttyS0.conf
# ttyS0 - getty
#
# This service maintains a getty on ttyS0 from the point the system is
# started until it is shut down again.
start on stopped rc RUNLEVEL=[12345]
stop on runlevel [!12345]
respawn
exec /sbin/getty -L 115200 ttyS0 vt102
EOF
    else
        __err__ "Unsupported init system. Only systemd and upstart are supported."
        exit 1
    fi

    # Update GRUB configuration
    __info__ "Updating GRUB configuration"

    # Check if already configured to avoid duplication
    if grep -q "console=ttyS0" /etc/default/grub; then
        __info__ "GRUB already configured with serial console"
    else
        # Use sed to append console parameters if not present
        if grep -q '^GRUB_CMDLINE_LINUX=' /etc/default/grub; then
            sed -i '/^GRUB_CMDLINE_LINUX=/ s/"$/ console=tty0 console=ttyS0,115200"/' /etc/default/grub
        else
            echo 'GRUB_CMDLINE_LINUX="quiet console=tty0 console=ttyS0,115200"' >> /etc/default/grub
        fi
    fi

    # Update GRUB
    __info__ "Running update-grub"
    if ! update-grub; then
        __err__ "Failed to update GRUB"
        exit 1
    fi

    __ok__ "Serial console ttyS0 configured successfully!"
    __info__ "Reboot for changes to take effect"
}

main

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-24
#
# Changes:
# - 2025-11-24: Added systemd support for modern systems
# - 2025-11-24: Added upstart detection and fallback
# - 2025-11-24: Fixed GRUB configuration to prevent duplication on multiple runs
# - 2025-11-24: Added init system detection logic
# - 2025-11-24: Clarified script purpose (runs inside VM guest, not on host)
# - 2025-11-24: Added Proxmox VM serial configuration reference in header
# - 2025-11-20: Updated to use utility functions
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# - 2025-11-24: Fixed sed command that would append parameters on every run
# - 2025-11-24: Added check for existing console configuration
# - 2025-11-24: Added error handling for update-grub failure
#
# Known issues:
# -
#
# Technical Context:
# This script configures the GUEST OS (inside the VM) to enable serial console access.
# It does NOT configure Proxmox VM settings. For Proxmox VM configuration, use:
#   qm set <vmid> --serial0 socket --vga serial0
#
# Serial console workflow:
# 1. On Proxmox host: qm set <vmid> --serial0 socket --vga serial0
# 2. Inside VM guest: Run this script to configure getty and GRUB
# 3. Reboot VM
# 4. Access via: qm terminal <vmid>
#
# References:
# - PVE Guide Chapter 10: VM serial ports (line 2284-2285)
# - PVE Guide Cloud-Init section: serial console examples (lines 787, 828)
# - systemd serial-getty@.service: Standard systemd serial console service
#

