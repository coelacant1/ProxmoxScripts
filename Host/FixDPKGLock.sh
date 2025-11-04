#!/bin/bash
#
# FixDPKGLock.sh
#
# Removes stale dpkg lock files and repairs interrupted dpkg operations.
#
# Usage:
#   FixDPKGLock.sh
#
# Examples:
#   FixDPKGLock.sh
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
    __check_proxmox__

    __info__ "Fixing dpkg locks and repairing package database"

    # Remove stale locks
    __info__ "Removing stale dpkg locks"
    rm -f "/var/lib/dpkg/lock-frontend"
    rm -f "/var/lib/dpkg/lock"
    rm -f "/var/lib/apt/lists/lock"
    rm -f "/var/cache/apt/archives/lock"
    rm -f "/var/lib/dpkg/lock"*
    __ok__ "Stale locks removed"

    # Reconfigure dpkg
    __info__ "Reconfiguring dpkg"
    if dpkg --configure -a 2>&1; then
        __ok__ "dpkg configured successfully"
    else
        __err__ "Failed to configure dpkg"
        exit 1
    fi

    # Update apt cache
    __info__ "Updating apt cache"
    if apt-get update 2>&1; then
        __ok__ "apt cache updated successfully"
    else
        __err__ "Failed to update apt cache"
        exit 1
    fi

    __ok__ "dpkg locks fixed and system ready!"
}

main

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
