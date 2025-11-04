#!/bin/bash
#
# UpdateAll.sh
#
# Updates packages (apt-get update && upgrade) for all LXC containers across the entire cluster.
# Containers must be running for updates to work.
#
# Usage:
#   UpdateAll.sh
#
# Examples:
#   UpdateAll.sh
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __info__ "Updating all LXC containers across the cluster"
    __warn__ "Containers must be running for updates to work"

    # Get all containers in cluster
    local -a all_cts
    mapfile -t all_cts < <(__get_cluster_cts__)

    if [[ ${#all_cts[@]} -eq 0 ]]; then
        __info__ "No LXC containers found in cluster"
        exit 0
    fi

    __info__ "Found ${#all_cts[@]} container(s) in cluster"

    local success=0
    local failed=0

    for vmid in "${all_cts[@]}"; do
        __update__ "Updating container ${vmid}..."

        if __ct_update_packages__ "$vmid"; then
            ((success++))
        else
            __warn__ "Failed to update container ${vmid}"
            ((failed++))
        fi
    done

    # Display summary
    echo ""
    __info__ "Update Summary:"
    __info__ "  Total: ${#all_cts[@]}"
    __info__ "  Success: ${success}"
    [[ $failed -gt 0 ]] && __warn__ "  Failed: ${failed}" || __info__ "  Failed: ${failed}"

    if [[ $failed -gt 0 ]]; then
        __err__ "Some updates failed. Check the messages above for details."
        exit 1
    fi

    __ok__ "All containers updated successfully!"
}

main

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
