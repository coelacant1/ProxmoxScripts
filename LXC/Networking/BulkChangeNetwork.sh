#!/bin/bash
#
# BulkChangeNetwork.sh
#
# Changes the network interface configuration for a range of LXC containers.
# Updates bridge and/or interface name settings.
# Automatically detects which node each container is on and executes the operation cluster-wide.
#
# Usage:
#   BulkChangeNetwork.sh <start_ct_id> <end_ct_id> <bridge> [interface_name]
#
# Arguments:
#   start_ct_id    - Starting container ID
#   end_ct_id      - Ending container ID
#   bridge         - Network bridge (e.g., vmbr0, vmbr1)
#   interface_name - Optional interface name (default: eth0)
#
# Examples:
#   BulkChangeNetwork.sh 400 402 vmbr1
#   BulkChangeNetwork.sh 400 402 vmbr1 eth1
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
__parse_args__ "start_vmid:vmid end_vmid:vmid bridge:bridge interface_name:string:?" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    # Set default interface name
    INTERFACE_NAME="${INTERFACE_NAME:-eth0}"

    __info__ "Bulk change network: Containers ${START_VMID} to ${END_VMID} (cluster-wide)"
    __info__ "Bridge: ${BRIDGE}, Interface: ${INTERFACE_NAME}"

    change_network_callback() {
        local vmid="$1"
        local net_config="name=${INTERFACE_NAME},bridge=${BRIDGE}"
        __ct_set_network__ "$vmid" "$net_config"
    }

    __bulk_ct_operation__ --name "Change Network" --report "$START_VMID" "$END_VMID" change_network_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "Network configuration updated successfully!"
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
# - 2025-11-20: Validated against PVE Guide v9.1-1 (Chapter 11) and CONTRIBUTING.md
#
# Fixes:
# - Fixed: Changed ArgumentParser types (vmid, bridge) for proper validation
#
# Known issues:
# - Pending validation
# -
#

