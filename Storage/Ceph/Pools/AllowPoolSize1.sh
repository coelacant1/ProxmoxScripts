#!/bin/bash
#
# AllowPoolSize1.sh
#
# Enables the global Ceph setting to allow pools with size=1 (no replication).
# Required for modern Ceph versions (Pacific, Quincy, Squid) before setting pool size to 1.
#
# WARNING: Single replica (size=1) means NO data redundancy. Any OSD failure will result
# in data loss. Only use for test/development environments or single-node clusters where
# data redundancy is not possible.
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

    __warn__ "This will allow pools with size=1 (NO replication)"
    __warn__ "Single replica means ANY OSD failure = DATA LOSS"
    __warn__ "Only suitable for test/development or single-node clusters"

    if ! __prompt_user_yn__ "Enable mon_allow_pool_size_one globally?"; then
        __info__ "Operation cancelled"
        exit 0
    fi

    __update__ "Enabling mon_allow_pool_size_one globally"
    if output=$(ceph config set global mon_allow_pool_size_one true 2>&1); then
        __ok__ "Pool size=1 is now allowed globally"
    else
        __err__ "Failed to enable mon_allow_pool_size_one: $output"
    fi
}

main

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-24
#
# Changes:
# - 2025-11-24: Deep technical validation - confirmed compliant
# - 2025-11-21: Added safety warnings and user confirmation prompt
# - 2025-11-21: Fixed error output handling (capture stderr properly)
# - 2025-11-21: Added detailed warning about data loss risks in header
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# - 2025-11-21: FIXED: Output suppression prevented seeing actual error messages
# - 2025-11-21: FIXED: Missing safety warning about single replica data loss
#
# Known issues:
# -
#

