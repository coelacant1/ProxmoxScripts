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
        echo "Usage: $0 <group_name> <resource_id_1> [<resource_id_2> ...]"
        exit 64
    fi

    local group_name="$1"
    shift
    local -a resource_ids=("$@")

    # Validate group name is not purely numeric
    if [[ "$group_name" =~ ^[0-9]+$ ]]; then
        __err__ "Group name '${group_name}' cannot be purely numeric"
        exit 1
    fi

    __info__ "Adding ${#resource_ids[@]} resource(s) to HA group '${group_name}'"

    # Get all cluster resources
    local -a all_cluster_lxc
    local -a all_cluster_vms
    mapfile -t all_cluster_lxc < <(__get_cluster_cts__)
    mapfile -t all_cluster_vms < <(__get_cluster_vms__)

    local success=0
    local failed=0

    for resource_id in "${resource_ids[@]}"; do
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

        __update__ "Adding ${resource_type}:${resource_id} to HA group ${group_name}"
        if pvesh create /cluster/ha/resources --sid "${resource_type}:${resource_id}" --group "${group_name}" 2>&1; then
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
#   - Pending validation
