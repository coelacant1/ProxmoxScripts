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
    __install_or_prompt__ "jq"

    __info__ "Disabling HA on node: ${TARGET_NODE_NAME}"

    # Resolve node name to IP
    local node_ip
    if ! node_ip=$(__get_ip_from_name__ "$TARGET_NODE_NAME"); then
        __err__ "Could not resolve node name '${TARGET_NODE_NAME}' to IP"
        exit 1
    fi
    __info__ "Node ${TARGET_NODE_NAME} resolved to IP: ${node_ip}"

    # Find HA resources referencing this node
    __info__ "Checking for HA resources on node ${TARGET_NODE_NAME}"
    local ha_resources
    ha_resources=$(pvesh get /cluster/ha/resources --output-format json 2>/dev/null \
        | jq -r '.[] | select(.statePath | contains("'"$TARGET_NODE_NAME"'")) | .sid')

    if [[ -z "$ha_resources" ]]; then
        __info__ "No HA resources found for node ${TARGET_NODE_NAME}"
    else
        __info__ "Removing HA resources:"
        local removed=0
        local failed=0

        while IFS= read -r res; do
            __update__ "Removing HA resource: ${res}"
            if pvesh delete "/cluster/ha/resources/${res}" 2>&1; then
                __ok__ "Removed ${res}"
                ((removed++))
            else
                __warn__ "Failed to remove ${res}"
                ((failed++))
            fi
        done <<< "$ha_resources"

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

# Testing status:
#   - Updated to use utility functions and ArgumentParser
#   - Pending validation
