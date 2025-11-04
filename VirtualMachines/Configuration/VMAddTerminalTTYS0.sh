#!/bin/bash
#
# VMAddTerminalTTYS0.sh
#
# Configures serial console (ttyS0) on a Debian-based system for VM terminal access.
# Creates getty service and updates GRUB for console output to serial port.
#
# Usage:
#   VMAddTerminalTTYS0.sh
#
# Examples:
#   VMAddTerminalTTYS0.sh
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

    # Create /etc/init directory
    __info__ "Creating /etc/init directory"
    mkdir -p /etc/init
    chmod 755 /etc/init

    # Create ttyS0 configuration
    __info__ "Creating /etc/init/ttyS0.conf"
    cat <<'EOF' > /etc/init/ttyS0.conf
# ttyS0 - getty
#
# This service maintains a getty on ttyS0 from the point the system is
# started until it is shut down again.
start on stopped rc RUNLEVEL=[12345]
stop on runlevel [!12345]
respawn
exec /sbin/getty -L 115200 ttyS0 vt102
EOF

    # Update GRUB configuration
    __info__ "Updating GRUB configuration"
    sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="quiet console=tty0 console=ttyS0,115200"/' /etc/default/grub

    # Update GRUB
    __info__ "Running update-grub"
    update-grub

    __ok__ "Serial console ttyS0 configured successfully!"
    __info__ "Reboot for changes to take effect"
}

main

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
