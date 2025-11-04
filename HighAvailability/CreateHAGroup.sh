#!/bin/bash
#
# CreateHAGroup.sh
#
# Creates a High Availability group in a Proxmox cluster and assigns nodes to it.
#
# Usage:
#   CreateHAGroup.sh <group_name> <node_name_1> [<node_name_2> ...]
#
# Arguments:
#   group_name   - Name for the HA group
#   node_name_* - One or more node names to add to the group
#
# Examples:
#   CreateHAGroup.sh Primary pve01 pve02
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
        echo "Usage: $0 <group_name> <node_name_1> [<node_name_2> ...]"
        exit 64
    fi

    local group_name="$1"
    shift
    local -a nodes=("$@")

    # Convert nodes array to comma-separated string
    local nodes_string
    nodes_string=$(IFS=,; echo "${nodes[*]}")

    __info__ "Creating HA group '${group_name}' with nodes: ${nodes_string}"

    if pvesh create /cluster/ha/groups \
        --group "${group_name}" \
        --nodes "${nodes_string}" \
        --comment "HA group created by script" 2>&1; then
        __ok__ "HA group '${group_name}' created successfully!"
    else
        __err__ "Failed to create HA group '${group_name}'"
        exit 1
    fi
}

main "$@"

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
