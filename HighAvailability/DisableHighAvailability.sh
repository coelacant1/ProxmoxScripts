#!/bin/bash
#
# DisableHighAvailability.sh
#
# Disables High Availability on a single Proxmox node by removing HA resources
# tied to that node and stopping HA services.
#
# Usage:
#   DisableHighAvailability.sh <node_name>
#
# Arguments:
#   node_name - Name of the node to disable HA on
#
# Examples:
#   DisableHighAvailability.sh pve-node2
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
# shellcheck source=Utilities/Discovery.sh
source "${UTILITYPATH}/Discovery.sh"
# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
__parse_args__ "target_node_name:node" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    __check_cluster_membership__

    __info__ "Disabling HA on node: ${TARGET_NODE_NAME}"

    # Resolve node name to IP
    local node_ip
    if ! node_ip=$(__get_ip_from_name__ "$TARGET_NODE_NAME"); then
        __err__ "Could not resolve node name '${TARGET_NODE_NAME}' to IP"
        exit 1
    fi
    __info__ "Node ${TARGET_NODE_NAME} resolved to IP: ${node_ip}"

    # Find HA resources currently running on this node
    __info__ "Checking for HA resources on node ${TARGET_NODE_NAME}"
    local ha_resources
    ha_resources=$(ha-manager status 2>/dev/null | awk -v node="$TARGET_NODE_NAME" '$1 == "service" && $2 ~ /^(vm|ct):/ && $3 == "("node"," {print $2}')

    if [[ -z "$ha_resources" ]]; then
        __info__ "No HA resources found on node ${TARGET_NODE_NAME}"
    else
        __info__ "Removing HA resources:"
        local removed=0
        local failed=0

        while IFS= read -r res; do
            __update__ "Removing HA resource: ${res}"
            if ha-manager remove "${res}" 2>&1; then
                __ok__ "Removed ${res}"
                removed=$((removed + 1))
            else
                __warn__ "Failed to remove ${res}"
                failed=$((failed + 1))
            fi
        done <<<"$ha_resources"

        echo
        __info__ "Removed ${removed} HA resource(s)"
        [[ $failed -gt 0 ]] && __warn__ "${failed} failed to remove"
    fi

    # Stop and disable HA services on the target node
    __info__ "Stopping and disabling HA services on ${TARGET_NODE_NAME}"
    __update__ "Stopping pve-ha-crm and pve-ha-lrm"
    ssh "root@${node_ip}" "systemctl stop pve-ha-crm pve-ha-lrm" 2>/dev/null || true

    __update__ "Disabling pve-ha-crm and pve-ha-lrm on startup"
    ssh "root@${node_ip}" "systemctl disable pve-ha-crm pve-ha-lrm" 2>/dev/null || true

    __ok__ "HA disabled on node ${TARGET_NODE_NAME} successfully!"
    __info__ "Verify with: ssh root@${node_ip} 'systemctl status pve-ha-crm pve-ha-lrm'"

    __prompt_keep_installed_packages__
}

main

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-11-20: Updated to use utility functions and ArgumentParser
# - 2025-11-20: Pending validation
# - 2025-11-20: Removed jq dependency - using ha-manager status instead
#
# Fixes:
# - 2025-11-20: Fixed ha-manager command usage per PVE Guide Section 15.3 and 15.4.1
# - 2025-11-20: Fixed arithmetic operations for set -e compatibility
#
# Known issues:
# - Pending validation
# -
#

