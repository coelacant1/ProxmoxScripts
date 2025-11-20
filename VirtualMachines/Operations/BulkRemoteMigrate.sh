#!/bin/bash
#
# BulkRemoteMigrate.sh
#
# Migrates virtual machines (VMs) from this Proxmox cluster to a target remote Proxmox node.
# Utilizes the Proxmox API for migration and requires authentication using an API token.
# Removes existing Cloud-Init drives before migration and adjusts VM IDs based on offset.
# Automatically detects which node each VM is on in the source cluster.
#
# Usage:
#   BulkRemoteMigrate.sh <first_vm_id> <last_vm_id> <target_host> <api_token> <fingerprint> <target_storage> <vm_offset> <target_network>
#
# Arguments:
#   first_vm_id     - The ID of the first VM to migrate.
#   last_vm_id      - The ID of the last VM to migrate.
#   target_host     - The hostname or IP address of the target Proxmox server.
#   api_token       - The API token used for authentication.
#   fingerprint     - The SSL fingerprint of the target Proxmox server.
#   target_storage  - The storage identifier on the target node.
#   vm_offset       - Integer value to offset VM IDs to avoid conflicts.
#   target_network  - The network bridge on the target server.
#
# Examples:
#   BulkRemoteMigrate.sh 400 410 192.168.1.20 user@pve!tokenid=abc-123 AA:BB:CC local-lvm 1000 vmbr0
#   This will migrate VMs 400-410 from their current nodes to the remote target
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
__parse_args__ "start_vmid:vmid end_vmid:vmid target_host target_token fingerprint target_storage:storage vm_offset:int target_network" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __info__ "Bulk remote migrate (cluster-wide): VMs ${START_VMID} to ${END_VMID}"
    __info__ "Target: ${TARGET_HOST}, Offset: ${VM_OFFSET}"

    # Local callback for bulk operation
    migrate_vm_callback() {
        local vmid="$1"
        local source_node
        local target_vmid=$((vmid + VM_OFFSET))

        source_node=$(__get_vm_node__ "$vmid")

        if [[ -z "$source_node" ]]; then
            __update__ "VM ${vmid} not found in cluster"
            return 1
        fi

        __update__ "Removing Cloud-Init drive (ide2) for VM ${vmid} on ${source_node}..."
        qm set "$vmid" --delete ide2 --node "$source_node" 2>/dev/null || true

        __update__ "Migrating VM ${vmid} (on ${source_node}) to VM ${target_vmid} on ${TARGET_HOST}..."

        local api_token="apitoken=${TARGET_TOKEN}"
        local migrate_cmd="qm remote-migrate ${vmid} ${target_vmid} '${api_token},host=${TARGET_HOST},fingerprint=${FINGERPRINT}' --target-bridge ${TARGET_NETWORK} --target-storage ${TARGET_STORAGE} --online"

        if eval "$migrate_cmd" 2>/dev/null; then
            return 0
        else
            return 1
        fi
    }

    # Use BulkOperations framework
    __bulk_vm_operation__ --name "Remote Migration" --report "$START_VMID" "$END_VMID" migrate_vm_callback

    # Display summary
    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "All VMs migrated successfully!"
}

main

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-11-20: Updated to use ArgumentParser and BulkOperations framework
#
# Fixes:
# -
#
# Known issues:
# -
#

