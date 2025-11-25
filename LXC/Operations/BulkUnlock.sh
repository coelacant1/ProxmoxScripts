#!/bin/bash
#
# BulkUnlock.sh
#
# Unlocks a range of LXC containers within a Proxmox VE environment.
# Automatically detects which node each container is on and executes the operation cluster-wide.
#
# Usage:
#   BulkUnlock.sh <first_ct_id> <last_ct_id>
#
# Arguments:
#   first_ct_id - The ID of the first container to unlock.
#   last_ct_id  - The ID of the last container to unlock.
#
# Examples:
#   BulkUnlock.sh 100 105
#   This will unlock containers 100-105 regardless of which nodes they are on
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
# shellcheck source=Utilities/BulkOperations.sh
source "${UTILITYPATH}/BulkOperations.sh"
# shellcheck source=Utilities/Operations.sh
source "${UTILITYPATH}/Operations.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
__parse_args__ "start_vmid:vmid end_vmid:vmid" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __info__ "Bulk unlock (cluster-wide): Containers ${START_VMID} to ${END_VMID}"

    # Local callback for bulk operation
    unlock_ct_callback() {
        local vmid="$1"
        __ct_unlock__ "$vmid"
    }

    # Use BulkOperations framework
    __bulk_ct_operation__ --name "Unlock" --report "$START_VMID" "$END_VMID" unlock_ct_callback

    # Display summary
    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "All containers unlocked successfully!"
}

main

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-11-20: Pending validation
# - 2025-11-20: Updated to use ArgumentParser and BulkOperations framework
# - 2025-11-20: Validated against CONTRIBUTING.md and PVE Guide Chapter 11
# - Uses __ct_unlock__ utility function per Section 11.12 (line 988)
#
# Fixes:
# - Fixed ArgumentParser types (vmid instead of int)
#
# Known issues:
# - Pending validation
# -
#

