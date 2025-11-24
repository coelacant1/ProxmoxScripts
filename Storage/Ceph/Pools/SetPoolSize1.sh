#!/bin/bash
#
# SetPoolSize1.sh
#
# Sets the size parameter of a Ceph pool to 1, disabling data replication.
#
# WARNING: Setting size=1 means NO data replication. Any OSD failure will result
# in data loss. Before running this script, you must enable mon_allow_pool_size_one
# using AllowPoolSize1.sh (required for Ceph Pacific, Quincy, Squid).
#
# Only use for test/development environments or single-node clusters where
# data redundancy is not possible.
#
# Usage:
#   SetPoolSize1.sh <pool_name>
#
# Arguments:
#   pool_name - Name of the Ceph storage pool
#
# Examples:
#   SetPoolSize1.sh testpool
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

__parse_args__ "pool_name:string" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __warn__ "Setting size=1 disables ALL data replication"
    __warn__ "Any OSD failure = COMPLETE DATA LOSS"
    __warn__ "Prerequisites:"
    __warn__ "  1. Run AllowPoolSize1.sh first (required for modern Ceph)"
    __warn__ "  2. Consider setting min_size=1 as well (see SetPoolMinSize1.sh)"
    __warn__ "Only suitable for test/development or single-node clusters"

    if ! __prompt_user_yn__ "Set size=1 for pool '$POOL_NAME' (NO replication)?"; then
        __info__ "Operation cancelled"
        exit 0
    fi

    __update__ "Setting size=1 for pool '$POOL_NAME'"
    if output=$(ceph osd pool set "$POOL_NAME" size 1 --yes-i-really-mean-it 2>&1); then
        __ok__ "size set to 1 for pool '$POOL_NAME'"
        __info__ "Note: You may also need to set min_size=1 using SetPoolMinSize1.sh"
    else
        __err__ "Failed to set size for pool '$POOL_NAME': $output"
        __err__ "Did you run AllowPoolSize1.sh first?"
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
# - 2025-11-21: Added safety warnings and prerequisite documentation
# - 2025-11-21: Added user confirmation prompt
# - 2025-11-21: Fixed error output handling (capture stderr properly)
# - 2025-11-21: Added reminder about min_size setting
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# - 2025-11-21: FIXED: Output capture was incorrect (stdout instead of stderr)
# - 2025-11-21: FIXED: Missing warning about AllowPoolSize1.sh prerequisite
# - 2025-11-21: FIXED: Missing safety warnings about data loss
#
# Known issues:
# -
#

