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

# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Cluster.sh
source "${UTILITYPATH}/Cluster.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

__parse_args__ "storage_name:storage mount_path:path" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    __check_cluster_membership__

    __info__ "Fixing stale mount for storage: $STORAGE_NAME"
    __info__ "Mount path: $MOUNT_PATH"

    # Disable storage
    __update__ "Disabling storage: $STORAGE_NAME"
    if pvesm set "${STORAGE_NAME}" --disable 1 2>&1; then
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

        if ssh root@"${node_ip}" "umount -f '${MOUNT_PATH}' 2>/dev/null && rm -rf '${MOUNT_PATH}' 2>/dev/null"; then
            __ok__ "Cleaned up: $node_ip"
            success=$((success + 1))
        else
            __warn__ "Cleanup issues on: $node_ip"
            failed=$((failed + 1))
        fi
    done

    # Re-enable storage
    __update__ "Re-enabling storage: $STORAGE_NAME"
    if pvesm set "${STORAGE_NAME}" --disable 0 2>&1; then
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

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-24
#
# Changes:
# - 2025-11-24: Fixed arithmetic increment syntax (CONTRIBUTING.md Section 3.7)
# - 2025-11-20: Updated to use utility functions
# - 2025-11-20: Updated to use ArgumentParser.sh
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# - 2025-11-24: Changed ((var += 1)) to var=$((var + 1)) for set -e compatibility
#
# Known issues:
# -
#

