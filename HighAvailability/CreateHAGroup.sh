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
# shellcheck source=Utilities/Cluster.sh
source "${UTILITYPATH}/Cluster.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Variable args: group_name + node names - hybrid parsing
if [[ $# -lt 2 ]]; then
    __err__ "Missing required arguments"
    echo "Usage: $0 <group_name> <node_name_1> [<node_name_2> ...]"
    exit 64
fi

GROUP_NAME="$1"
shift
NODES=("$@")

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    __check_cluster_membership__

    # Convert nodes array to comma-separated string
    local nodes_string
    nodes_string=$(
        IFS=,
        echo "${NODES[*]}"
    )

    __warn__ "HA Groups are deprecated since Proxmox VE 9.0 - use 'ha-manager rules add node-affinity' instead"
    __info__ "Creating HA group '${GROUP_NAME}' with nodes: ${nodes_string}"

    if ha-manager groupadd "${GROUP_NAME}" --nodes "${nodes_string}" --comment "HA group created by script" 2>&1; then
        __ok__ "HA group '${GROUP_NAME}' created successfully!"
    else
        __err__ "Failed to create HA group '${GROUP_NAME}'"
        exit 1
    fi
}

main "$@"

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-11-20: Updated to use utility functions
# - 2025-11-20: ArgumentParser.sh sourced (hybrid for variable args)
# - 2025-11-20: Pending validation
# - 2025-11-20: Added deprecation warning for HA groups per PVE Guide Section 15.6.2
#
# Fixes:
# - 2025-11-20: Fixed ha-manager groupadd command per PVE Guide Section 15.6.2
# - 2025-11-20: Fixed variable name typo (group_name -> GROUP_NAME)
#
# Known issues:
# - Pending validation
# -
#

