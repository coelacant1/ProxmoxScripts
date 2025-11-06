#!/bin/bash
#
# RemoveClusterNode.sh
#
# Safely removes a node from a Proxmox cluster.
# Cleans up SSH references and node directories on remaining nodes.
#
# Usage:
#   RemoveClusterNode.sh [--force] <node_name>
#
# Arguments:
#   node_name - Name of the node to remove
#   --force   - Allow removal even if node has VMs/containers
#
# Examples:
#   RemoveClusterNode.sh node3
#   RemoveClusterNode.sh --force node3
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Queries.sh
source "${UTILITYPATH}/Queries.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

__parse_args__ "node_name:node --force:flag" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    __install_or_prompt__ "jq"
    __check_cluster_membership__

    # Check for VMs/containers unless --force
    if [[ "$FORCE" != "true" ]]; then
        __info__ "Checking for VMs/containers on node ${NODE_NAME}"

        local vms_on_node
        vms_on_node=$(
            pvesh get /cluster/resources --type vm --output-format json 2>/dev/null \
            | jq -r --arg N "$NODE_NAME" '.[] | select(.node == $N) | "\(.type) \(.vmid)"'
        )

        if [[ -n "$vms_on_node" ]]; then
            __err__ "The following VMs/containers still reside on node ${NODE_NAME}:"
            echo "$vms_on_node"
            __err__ "Migrate or remove them first, or use --force to override"
            exit 1
        fi
    fi

    __warn__ "This will remove node ${NODE_NAME} from the cluster"
    if ! __prompt_yes_no__ "Proceed?"; then
        __info__ "Operation cancelled"
        exit 0
    fi

    __info__ "Preparing node ${NODE_NAME} for removal"

    # Stop cluster services on target node
    local host
    host=$(__get_ip_from_name__ "$NODE_NAME") || true

    if [[ -n "$host" ]]; then
        __info__ "Stopping cluster services on ${NODE_NAME}"
        ssh -t -o StrictHostKeyChecking=no "root@${host}" \
            "systemctl stop pve-cluster corosync && pmxcfs -l && rm -r /etc/corosync/* /etc/pve/corosync.conf && killall pmxcfs && systemctl start pve-cluster" 2>/dev/null || true
    fi

    # Remove node from cluster
    __info__ "Removing node ${NODE_NAME} from cluster membership"

    local node_count
    node_count=$(__get_number_of_cluster_nodes__)

    if [[ "$node_count" -le 2 ]]; then
        __info__ "Small cluster detected, adjusting quorum"
        sleep 15
        systemctl restart corosync
        sleep 2
        pvecm expected 1
        sleep 2

        __info__ "Attempting node removal (will retry until successful)"
        while ! pvecm delnode "$NODE_NAME" 2>/dev/null; do
            __update__ "Retrying in 5 seconds..."
            sleep 5
        done
    else
        pvecm delnode "$NODE_NAME"
    fi

    __ok__ "Node ${NODE_NAME} removed from cluster"

    # Clean SSH references on remaining nodes
    __info__ "Cleaning SSH references on remaining nodes"
    local online_nodes
    online_nodes=$(pvecm nodes | awk '!/Name/ {print $3}')

    for node in $online_nodes; do
        [[ "$node" == "$NODE_NAME" ]] && continue
        [[ -z "$node" ]] && continue

        __update__ "Cleaning SSH references on ${node}"
        ssh "root@${node}" "ssh-keygen -R '${NODE_NAME}' >/dev/null 2>&1 || true"
        ssh "root@${node}" "ssh-keygen -R '${NODE_NAME}.local' >/dev/null 2>&1 || true"
        ssh "root@${node}" "sed -i '/${NODE_NAME}/d' /etc/ssh/ssh_known_hosts 2>/dev/null || true"
        ssh "root@${node}" "rm -rf /etc/pve/nodes/${NODE_NAME} 2>/dev/null || true"
    done

    __ok__ "SSH references cleaned on all remaining nodes"
    __ok__ "Node ${NODE_NAME} removed successfully!"
    __info__ "You can now safely re-add a node with this name"

    __prompt_keep_installed_packages__
}

main "$@"

# Testing status:
#   - Updated to use utility functions
#   - Updated to use ArgumentParser.sh
#   - Pending validation
