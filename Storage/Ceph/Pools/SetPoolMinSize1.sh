#!/bin/bash
#
# SetPoolMinSize1.sh
#
# Sets the min_size parameter of a Ceph pool to 1, allowing degraded mode operation.
#
# CRITICAL WARNING: The Proxmox VE documentation states "Do not set a min_size of 1."
# A pool with min_size of 1 allows I/O when only 1 replica exists, which can lead to:
# - Data loss
# - Incomplete placement groups
# - Unfound objects
#
# Only use this for test/development environments where data loss is acceptable.
# Production environments should maintain min_size of 2 or higher.
#
# Usage:
#   SetPoolMinSize1.sh <pool_name>
#
# Arguments:
#   pool_name - Name of the Ceph storage pool
#
# Examples:
#   SetPoolMinSize1.sh mypool
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

    __err__ "CRITICAL: Proxmox VE documentation states 'Do not set a min_size of 1'"
    __warn__ "Setting min_size=1 can lead to:"
    __warn__ "  - Data loss with single replica"
    __warn__ "  - Incomplete placement groups"
    __warn__ "  - Unfound objects"
    __warn__ "Only suitable for test/development where data loss is acceptable"

    if ! __prompt_user_yn__ "Set min_size=1 for pool '$POOL_NAME' (NOT recommended)?"; then
        __info__ "Operation cancelled"
        exit 0
    fi

    __update__ "Setting min_size=1 for pool '$POOL_NAME'"
    if output=$(ceph osd pool set "$POOL_NAME" min_size 1 --yes-i-really-mean-it 2>&1); then
        __ok__ "min_size set to 1 for pool '$POOL_NAME'"
    else
        __err__ "Failed to set min_size for pool '$POOL_NAME': $output"
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
# - 2025-11-21: Added critical safety warnings per PVE Guide Section 8.9.1
# - 2025-11-21: Added user confirmation prompt for dangerous operation
# - 2025-11-21: Fixed error output handling (capture stderr properly)
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# - 2025-11-21: FIXED CRITICAL: Added PVE Guide-mandated warning about min_size=1 dangers
# - 2025-11-21: FIXED: Output capture was incorrect (stdout instead of stderr)
#
# Known issues:
# -
#

