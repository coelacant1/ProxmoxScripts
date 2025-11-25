#!/bin/bash
#
# BulkChangeStorage.sh
#
# Updates the storage location in VM configuration files for a range of VMs on a Proxmox node.
# Useful for moving VMs to a different storage solution or reorganizing storage resources.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   BulkChangeStorage.sh <start_id> <end_id> <current_storage> <new_storage>
#
# Arguments:
#   start_id         - The starting VM ID for the operation.
#   end_id           - The ending VM ID for the operation.
#   current_storage  - The current storage identifier to replace.
#   new_storage      - The new storage identifier.
#
# Examples:
#   BulkChangeStorage.sh 100 200 local-lvm local-zfs
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
# shellcheck source=Utilities/Cluster.sh
source "${UTILITYPATH}/Cluster.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
__parse_args__ "start_vmid:vmid end_vmid:vmid current_storage:storage new_storage:storage" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __info__ "Bulk change storage: VMs ${START_VMID} to ${END_VMID} (cluster-wide)"
    __info__ "Changing ${CURRENT_STORAGE} to ${NEW_STORAGE}"

    # Local callback for bulk operation
    change_storage_callback() {
        local vmid="$1"
        local node

        node=$(__get_vm_node__ "$vmid")

        if [[ -z "$node" ]]; then
            __update__ "VM ${vmid} not found in cluster"
            return 1
        fi

        local config_file="/etc/pve/nodes/${node}/qemu-server/${vmid}.conf"

        if [[ ! -f "$config_file" ]]; then
            __update__ "VM ${vmid} config does not exist"
            return 1
        fi

        if grep -q "$CURRENT_STORAGE" "$config_file"; then
            __update__ "Updating storage for VM ${vmid}..."
            if sed -i "s/$CURRENT_STORAGE/$NEW_STORAGE/g" "$config_file" 2>/dev/null; then
                return 0
            else
                return 1
            fi
        else
            __update__ "${CURRENT_STORAGE} not found in VM ${vmid} config"
            return 0
        fi
    }

    # Use BulkOperations framework
    __bulk_vm_operation__ --name "Storage Change" --report "$START_VMID" "$END_VMID" change_storage_callback

    # Display summary
    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "All storage updates completed successfully!"
}

main

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-11-20: Updated to use ArgumentParser and BulkOperations framework
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# -
#
# Known issues:
# -
#

