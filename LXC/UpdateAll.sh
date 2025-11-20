#!/bin/bash
#
# UpdateAll.sh
#
# Updates packages (apt-get update && upgrade) for all LXC containers across the entire cluster.
# Containers must be running for updates to work. Supports Debian/Ubuntu (apt-get), Alpine (apk), and Fedora (dnf) distributions.
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
# shellcheck source=Utilities/Operations.sh
source "${UTILITYPATH}/Operations.sh"
# shellcheck source=Utilities/Cluster.sh
source "${UTILITYPATH}/Cluster.sh"

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
            success=$((success + 1))
        else
            __warn__ "Failed to update container ${vmid}"
            failed=$((failed + 1))
        fi
    done

    # Display summary
    echo ""
    __info__ "Update Summary:"
    __info__ "  Total: ${#all_cts[@]}"
    __info__ "  Success: ${success}"
    if [[ $failed -gt 0 ]]; then
        __warn__ "  Failed: ${failed}"
    else
        __info__ "  Failed: ${failed}"
    fi

    if [[ $failed -gt 0 ]]; then
        __err__ "Some updates failed. Check the messages above for details."
        exit 1
    fi

    __ok__ "All containers updated successfully!"
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
# - 2025-11-20: Validated against PVE Guide v9.1-1 and CONTRIBUTING.md
#
# Fixes:
# - Fixed arithmetic increment syntax per CONTRIBUTING.md Section 3.7
# - Fixed if-then-else pattern per shellcheck SC2015
#
# Known issues:
# - Containers must be running for updates to work
# - Pending validation
#

