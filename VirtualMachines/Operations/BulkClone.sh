#!/bin/bash
#
# BulkClone.sh
#
# Clones a source VM into multiple new VMs with sequential IDs and names.
# All clones are created on the same node as the source VM.
#
# Usage:
#   BulkClone.sh <source_vmid> <base_name> <start_vmid> <count> [--pool <pool_name>]
#
# Arguments:
#   source_vmid - The ID of the VM to be cloned.
#   base_name   - Base name for new VMs (appended with sequential number).
#   start_vmid  - Starting VM ID for the first clone.
#   count       - Number of VMs to clone.
#   --pool      - Optional pool name to add cloned VMs to.
#
# Examples:
#   BulkClone.sh 110 Ubuntu-2C-20GB 400 30
#   BulkClone.sh 110 Ubuntu-2C-20GB 400 30 --pool PoolName
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
# shellcheck source=Utilities/Operations.sh
source "${UTILITYPATH}/Operations.sh"
# shellcheck source=Utilities/Cluster.sh
source "${UTILITYPATH}/Cluster.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments using declarative API
__parse_args__ "source_vmid:vmid base_name:string start_vmid:vmid count:number --pool:string:?" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    # Verify source VM exists
    if ! __vm_exists__ "$SOURCE_VMID"; then
        __err__ "Source VM ID ${SOURCE_VMID} not found"
        exit 1
    fi

    # Get source VM node for remote execution
    local source_node
    source_node=$(__get_vm_node__ "$SOURCE_VMID")

    # Calculate end VMID
    local end_vmid=$((START_VMID + COUNT - 1))

    __info__ "Cloning VM ${SOURCE_VMID} (on node ${source_node}) to create ${COUNT} new VMs (${START_VMID}-${end_vmid})"
    [[ -n "$POOL" ]] && __info__ "VMs will be added to pool: ${POOL}"

    # Track success and failures
    local success=0
    local failed=0

    # Clone VMs sequentially
    for ((i = 0; i < COUNT; i++)); do
        local target_vmid=$((START_VMID + i))
        local name_index=$((i + 1))
        local vm_name="${BASE_NAME}${name_index}"
        local current=$((i + 1))

        __update__ "Cloning VM ${target_vmid} (${current}/${COUNT})..."

        # Build clone command
        local clone_cmd="qm clone ${SOURCE_VMID} ${target_vmid} --name ${vm_name}"
        [[ -n "$POOL" ]] && clone_cmd+=" --pool ${POOL}"

        # Execute clone on source VM's node
        if __node_exec__ "$source_node" "$clone_cmd" &>/dev/null; then
            ((success += 1))
        else
            __warn__ "Failed to clone VM ${target_vmid}"
            ((failed += 1))
        fi
    done

    # Display summary
    echo ""
    __info__ "Cloning Summary:"
    __info__ "  Total: ${COUNT}"
    __info__ "  Success: ${success}"
    [[ $failed -gt 0 ]] && __warn__ "  Failed: ${failed}" || __info__ "  Failed: ${failed}"

    if [[ $failed -gt 0 ]]; then
        __err__ "Some clones failed. Check the messages above for details."
        exit 1
    fi

    __ok__ "Cloning completed successfully!"
}

main

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-24
#
# Changes:
# - 2025-11-20: Pending validation on Proxmox VE cluster
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# -
#
# Known issues:
# - Pending validation on Proxmox VE cluster
# -
#

