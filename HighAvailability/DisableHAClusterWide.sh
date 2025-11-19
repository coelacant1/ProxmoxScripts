#!/bin/bash
#
# DisableHAClusterWide.sh
#
# Disables High Availability across the entire cluster by removing all HA resources
# and stopping HA services on all nodes.
#
# Usage:
#   DisableHAClusterWide.sh
#
# Examples:
#   DisableHAClusterWide.sh
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

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    __check_cluster_membership__
    __install_or_prompt__ "jq"

    __warn__ "This will disable HA cluster-wide and remove all HA resources"
    if ! __prompt_user_yn__ "Proceed with HA cluster-wide disable?"; then
        __info__ "Operation cancelled"
        exit 0
    fi

    __info__ "Disabling HA on entire cluster"

    # Retrieve and remove all HA resources
    __info__ "Retrieving all HA resources"
    local all_resources
    all_resources=$(pvesh get /cluster/ha/resources --output-format json 2>/dev/null | jq -r '.[].sid')

    if [[ -z "$all_resources" ]]; then
        __info__ "No HA resources found"
    else
        __info__ "Removing HA resources:"
        local removed=0
        local failed=0

        while IFS= read -r res; do
            __update__ "Removing HA resource: ${res}"
            if pvesh delete "/cluster/ha/resources/${res}" 2>&1; then
                __ok__ "Removed ${res}"
                ((removed += 1))
            else
                __warn__ "Failed to remove ${res}"
                ((failed += 1))
            fi
        done <<<"$all_resources"

        echo
        __info__ "Removed ${removed} HA resource(s)"
        [[ $failed -gt 0 ]] && __warn__ "${failed} failed to remove"
    fi

    # Stop and disable HA services on all nodes
    __info__ "Disabling HA services on all nodes"
    local -a remote_node_ips
    mapfile -t remote_node_ips < <(__get_remote_node_ips__)

    for node_ip in "${remote_node_ips[@]}"; do
        __update__ "Processing node ${node_ip}"
        __update__ "  Stopping HA services"
        ssh "root@${node_ip}" "systemctl stop pve-ha-crm pve-ha-lrm" 2>/dev/null || true

        __update__ "  Disabling HA services on startup"
        ssh "root@${node_ip}" "systemctl disable pve-ha-crm pve-ha-lrm" 2>/dev/null || true

        __ok__ "HA disabled on ${node_ip}"
    done

    __ok__ "HA disabled cluster-wide successfully!"
    __info__ "HA services stopped and disabled on all nodes"

    __prompt_keep_installed_packages__
}

main

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
