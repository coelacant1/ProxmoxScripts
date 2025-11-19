#!/bin/bash
#
# AllowPoolSize1.sh
#
# Enables the global Ceph setting to allow pools with size=1 (no replication).
# Required for modern Ceph versions (Pacific, Quincy, Squid) before setting pool size to 1.
#
# Usage:
#   AllowPoolSize1.sh
#
# Examples:
#   AllowPoolSize1.sh
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

    __update__ "Enabling mon_allow_pool_size_one globally"
    if ceph config set global mon_allow_pool_size_one true &>/dev/null; then
        __ok__ "Pool size=1 is now allowed globally"
    else
        __err__ "Failed to enable mon_allow_pool_size_one"
    fi
}

main

# Testing status:
#   - Pending validation
