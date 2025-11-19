#!/bin/bash
#
# BulkStartAtBoot.sh
#
# Enables automatic start at boot for a range of LXC containers.
# Automatically detects which node each container is on and executes the operation cluster-wide.
#
# Usage:
#   BulkStartAtBoot.sh <start_ct_id> <end_ct_id>
#
# Arguments:
#   start_ct_id - Starting container ID
#   end_ct_id   - Ending container ID
#
# Examples:
#   BulkStartAtBoot.sh 400 430
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
__parse_args__ "start_vmid:int end_vmid:int" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __info__ "Bulk enable start at boot: Containers ${START_VMID} to ${END_VMID} (cluster-wide)"

    set_onboot_callback() {
        local vmid="$1"
        __ct_set_onboot__ "$vmid" 1
    }

    __bulk_ct_operation__ --name "Enable Start at Boot" --report "$START_VMID" "$END_VMID" set_onboot_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "Start at boot enabled successfully!"
}

main

# Testing status:
#   - Updated to use ArgumentParser and BulkOperations framework
#   - Pending validation
