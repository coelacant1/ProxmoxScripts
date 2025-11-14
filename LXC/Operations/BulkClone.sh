#!/bin/bash
#
# BulkClone.sh
#
# Clones a source container into multiple new containers with sequential IDs, names, and IP addresses.
# All clones are created on the same node as the source container.
#
# Usage:
#   BulkClone.sh <source_ctid> <base_name> <start_ctid> <count> <start_ip/cidr> <bridge> [gateway] [--pool <pool_name>]
#
# Arguments:
#   source_ctid  - The ID of the container to be cloned.
#   base_name    - Base name for new containers (appended with sequential number).
#   start_ctid   - Starting container ID for the first clone.
#   count        - Number of containers to clone.
#   start_ip/cidr - Starting IP address with CIDR notation (e.g., 192.168.1.50/24).
#   bridge       - Network bridge to use (e.g., vmbr0).
#   gateway      - Optional gateway IP address (e.g., 192.168.1.1).
#   --pool       - Optional pool name to add cloned containers to.
#
# Examples:
#   BulkClone.sh 110 Ubuntu-2C-20GB 400 30 192.168.1.50/24 vmbr0
#   BulkClone.sh 110 Ubuntu-2C-20GB 400 30 192.168.1.50/24 vmbr0 192.168.1.1
#   BulkClone.sh 110 Ubuntu-2C-20GB 400 30 192.168.1.50/24 vmbr0 192.168.1.1 --pool PoolName
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Operations.sh
source "${UTILITYPATH}/Operations.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
__parse_args__ "source_vmid:vmid base_name:string start_vmid:vmid count:number start_ip_cidr:string bridge:string gateway:string:? --pool:string:?" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    # Verify source container exists
    if ! __ct_exists__ "$SOURCE_VMID"; then
        __err__ "Source container ID ${SOURCE_VMID} not found"
        exit 1
    fi

    # Get source container node for remote execution
    local source_node
    source_node=$(__get_vm_node__ "$SOURCE_VMID")

    # Calculate end VMID
    local end_vmid=$((START_VMID + COUNT - 1))

    # Parse IP and subnet mask
    IFS='/' read -r start_ip subnet_mask <<< "$START_IP_CIDR"
    local start_ip_int
    start_ip_int=$(__ip_to_int__ "$start_ip")

    __info__ "Cloning container ${SOURCE_VMID} (on node ${source_node}) to create ${COUNT} new containers (${START_VMID}-${end_vmid})"
    __info__ "IP range: ${start_ip}/${subnet_mask} (incrementing)"
    [[ -n "${GATEWAY:-}" ]] && __info__ "Gateway: ${GATEWAY}"
    [[ -n "${POOL:-}" ]] && __info__ "Containers will be added to pool: ${POOL}"

    # Track success and failures
    local success=0
    local failed=0

    # Clone containers sequentially
    for (( i=0; i<COUNT; i++ )); do
        local target_vmid=$((START_VMID + i))
        local name_index=$((i + 1))
        local ct_name="${BASE_NAME}${name_index}"
        local current=$((i + 1))

        # Calculate new IP
        local current_ip_int=$((start_ip_int + i))
        local new_ip
        new_ip=$(__int_to_ip__ "$current_ip_int")

        __update__ "Cloning container ${target_vmid} (${current}/${COUNT}) with IP ${new_ip}..."

        # Build clone command
        local clone_cmd="pct clone ${SOURCE_VMID} ${target_vmid} --hostname ${ct_name}"
        [[ -n "${POOL:-}" ]] && clone_cmd+=" --pool ${POOL}"

        # Execute clone on source container's node
        if __node_exec__ "$source_node" "$clone_cmd" &>/dev/null; then
            # Set network configuration
            local net_cmd="pct set ${target_vmid} -net0 name=eth0,bridge=${BRIDGE},ip=${new_ip}/${subnet_mask}"
            [[ -n "${GATEWAY:-}" ]] && net_cmd+=",gw=${GATEWAY}"

            if __node_exec__ "$source_node" "$net_cmd" &>/dev/null; then
                ((success++))
            else
                __warn__ "Cloned container ${target_vmid} but failed to set network configuration"
                ((failed++))
            fi
        else
            __warn__ "Failed to clone container ${target_vmid}"
            ((failed++))
        fi
    done

    # Display summary
    echo ""
    __info__ "Cloning Summary:"
    __info__ "  Total: ${COUNT}"
    __info__ "  Success: ${success}"
    [[ $failed -gt 0 ]] && __warn__ "  Failed: ${failed}" || __info__ "  Failed: ${failed}"

    if [[ $failed -gt 0 ]]; then
        __err__ "Some clones failed. Check the messages above for details."
        exit 1
    fi

    __ok__ "Cloning completed successfully!"
}

main

# Testing status:
#   - Updated to use ArgumentParser and utility functions
#   - Pending validation
