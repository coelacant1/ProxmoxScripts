#!/bin/bash
#
# AddResources.sh
#
# Adds VMs/containers to a High Availability group in a Proxmox cluster.
# Automatically detects resource type (VM or CT) across the cluster.
#
# Usage:
#   AddResources.sh <group_name> <resource_id_1> [<resource_id_2> ...]
#
# Arguments:
#   group_name    - Name of the HA group
#   resource_id_* - One or more VM/CT IDs to add
#
# Examples:
#   AddResources.sh Primary 100 101 200
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
# shellcheck source=Utilities/Queries.sh
source "${UTILITYPATH}/Queries.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Variable args: group_name + resource IDs - hybrid parsing
if [[ $# -lt 2 ]]; then
    __err__ "Missing required arguments"
    echo "Usage: $0 <group_name> <resource_id_1> [<resource_id_2> ...]"
    exit 64
fi

GROUP_NAME="$1"
shift
RESOURCE_IDS=("$@")

# Validate group name is not purely numeric
if [[ "$GROUP_NAME" =~ ^[0-9]+$ ]]; then
    __err__ "Group name '${GROUP_NAME}' cannot be purely numeric"
    exit 64
fi

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    __check_cluster_membership__

    __info__ "Adding ${#RESOURCE_IDS[@]} resource(s) to HA group '${GROUP_NAME}'"

    # Get all cluster resources
    local -a all_cluster_lxc
    local -a all_cluster_vms
    mapfile -t all_cluster_lxc < <(__get_cluster_cts__)
    mapfile -t all_cluster_vms < <(__get_cluster_vms__)

    local success=0
    local failed=0

    for resource_id in "${RESOURCE_IDS[@]}"; do
        local resource_type=""

        # Determine resource type
        if [[ " ${all_cluster_lxc[*]} " == *" ${resource_id} "* ]]; then
            resource_type="ct"
        elif [[ " ${all_cluster_vms[*]} " == *" ${resource_id} "* ]]; then
            resource_type="vm"
        else
            __warn__ "Resource ${resource_id} not found in cluster"
            ((failed++))
            continue
        fi

        __update__ "Adding ${resource_type}:${resource_id} to HA group ${GROUP_NAME}"
        if pvesh create /cluster/ha/resources --sid "${resource_type}:${resource_id}" --group "${GROUP_NAME}" 2>&1; then
            __ok__ "Added ${resource_type}:${resource_id}"
            ((success++))
        else
            __warn__ "Failed to add ${resource_type}:${resource_id}"
            ((failed++))
        fi
    done

    echo
    __info__ "HA Resource Addition Summary:"
    __info__ "  Added: ${success}"
    [[ $failed -gt 0 ]] && __warn__ "  Failed: ${failed}" || __info__ "  Failed: ${failed}"

    [[ $failed -gt 0 ]] && exit 1
    __ok__ "All resources added to HA group successfully!"
}

main "$@"

# Testing status:
#   - Updated to use utility functions
#   - ArgumentParser.sh sourced (hybrid for variable args)
#   - Pending validation
