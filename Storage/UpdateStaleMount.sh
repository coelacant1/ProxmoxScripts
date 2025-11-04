#!/bin/bash
#
# UpdateStaleMount.sh
#
# Fixes stale file mounts across Proxmox cluster by unmounting and re-enabling storage.
#
# Usage:
#   UpdateStaleMount.sh <storage_name> <mount_path>
#
# Arguments:
#   storage_name - Proxmox storage ID
#   mount_path - Stale mount point path
#
# Examples:
#   UpdateStaleMount.sh ISO_Storage /mnt/pve/ISO
#   UpdateStaleMount.sh NFS_Backup /mnt/pve/backup
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Queries.sh
source "${UTILITYPATH}/Queries.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    __check_cluster_membership__

    if [[ $# -lt 2 ]]; then
        __err__ "Missing required arguments"
        echo "Usage: $0 <storage_name> <mount_path>"
        exit 64
    fi

    local storage_name="$1"
    local mount_path="$2"

    __info__ "Fixing stale mount for storage: $storage_name"
    __info__ "Mount path: $mount_path"

    # Disable storage
    __update__ "Disabling storage: $storage_name"
    if pvesm set "${storage_name}" --disable 1 2>&1; then
        __ok__ "Storage disabled"
    else
        __err__ "Failed to disable storage"
        exit 1
    fi

    # Get cluster nodes
    __info__ "Retrieving cluster nodes"
    local -a remote_nodes
    mapfile -t remote_nodes < <(__get_remote_node_ips__)

    if [[ ${#remote_nodes[@]} -eq 0 ]]; then
        __warn__ "No remote nodes found"
    else
        __ok__ "Found ${#remote_nodes[@]} remote node(s)"
    fi

    # Unmount and remove on each node
    local success=0
    local failed=0

    for node_ip in "${remote_nodes[@]}"; do
        __update__ "Processing node: $node_ip"

        if ssh root@"${node_ip}" "umount -f '${mount_path}' 2>/dev/null && rm -rf '${mount_path}' 2>/dev/null"; then
            __ok__ "Cleaned up: $node_ip"
            ((success++))
        else
            __warn__ "Cleanup issues on: $node_ip"
            ((failed++))
        fi
    done

    # Re-enable storage
    __update__ "Re-enabling storage: $storage_name"
    if pvesm set "${storage_name}" --disable 0 2>&1; then
        __ok__ "Storage re-enabled"
    else
        __err__ "Failed to re-enable storage"
        exit 1
    fi

    echo
    __info__ "Mount Cleanup Summary:"
    __info__ "  Successful: $success"
    [[ $failed -gt 0 ]] && __warn__ "  Failed: $failed" || __info__ "  Failed: $failed"

    __ok__ "Stale mount updated successfully!"
}

main "$@"

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
