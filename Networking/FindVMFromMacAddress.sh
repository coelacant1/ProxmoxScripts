#!/bin/bash
#
# FindVMFromMacAddress.sh
#
# Retrieves network configuration and MAC addresses for all VMs across cluster.
#
# Usage:
#   FindVMFromMacAddress.sh
#
# Examples:
#   FindVMFromMacAddress.sh
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Cluster.sh
source "${UTILITYPATH}/Cluster.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    __install_or_prompt__ "jq"
    __check_cluster_membership__

    __info__ "Scanning VMs for MAC addresses (cluster-wide)"

    local nodes
    nodes=$(pvesh get /nodes --output-format=json | jq -r '.[] | .node')

    local total_vms=0

    for node in $nodes; do
        __info__ "Checking node: $node"

        local vm_ids
        vm_ids=$(pvesh get /nodes/"$node"/qemu --output-format=json 2>/dev/null | jq -r '.[] | .vmid' || true)

        for vm_id in $vm_ids; do
            echo "  VMID $vm_id:"
            pvesh get /nodes/"$node"/qemu/"$vm_id"/config 2>/dev/null \
                | grep -i 'net' \
                | grep -i 'macaddr' \
                | sed 's/^/    /' || echo "    No MAC addresses found"
            total_vms=$((total_vms + 1))
        done
    done

    echo
    __ok__ "MAC address scan completed"
    __info__ "Total VMs scanned: $total_vms"
    __prompt_keep_installed_packages__
}

main

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-11-20: Updated to use utility functions
# - 2025-11-20: Pending validation
# - 2025-11-20: Validated against CONTRIBUTING.md and PVE Guide
# - Added missing main() call
#
# Fixes:
# - Fixed arithmetic increment syntax (line 54)
#
# Known issues:
# - Pending validation
# -
#

