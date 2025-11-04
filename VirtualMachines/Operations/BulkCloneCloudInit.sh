#!/bin/bash
#
# BulkCloneCloudInit.sh
#
# Clones a source VM into multiple new VMs with sequential IDs, names, and
# Cloud-Init network configuration (IP, gateway, bridge). All clones are
# created on the same node as the source VM.
#
# Usage:
#   BulkCloneCloudInit.sh <source_vmid> <base_name> <start_vmid> <count> <start_ip> <bridge> [--gateway <gateway>] [--pool <pool_name>]
#
# Arguments:
#   source_vmid - The ID of the VM to be cloned.
#   base_name   - Base name for new VMs (appended with sequential number).
#   start_vmid  - Starting VM ID for the first clone.
#   count       - Number of VMs to clone.
#   start_ip    - Starting IP address in CIDR notation (e.g., 192.168.1.50/24).
#   bridge      - Network bridge to use (e.g., vmbr0).
#   --gateway   - Optional gateway IP address for network configuration.
#   --pool      - Optional pool name to add cloned VMs to.
#
# Examples:
#   BulkCloneCloudInit.sh 110 Ubuntu-2C-20GB 400 30 192.168.1.50/24 vmbr0
#   BulkCloneCloudInit.sh 110 Ubuntu-2C-20GB 400 30 192.168.1.50/24 vmbr0 --gateway 192.168.1.1
#   BulkCloneCloudInit.sh 110 Ubuntu-2C-20GB 400 30 192.168.1.50/24 vmbr0 --gateway 192.168.1.1 --pool PoolName
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
# shellcheck source=Utilities/ProxmoxAPI.sh
source "${UTILITYPATH}/ProxmoxAPI.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments using declarative API
__parse_args__ "source_vmid:vmid base_name:string start_vmid:vmid count:number start_ip:cidr bridge:bridge --gateway:gateway:? --pool:string:?" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    # Verify source VM exists
    if ! __vm_exists__ "$SOURCE_VMID"; then
        __err__ "Source VM ID ${SOURCE_VMID} not found"
        exit 1
    fi

    # Get source VM node for remote execution
    local source_node
    source_node=$(__get_vm_node__ "$SOURCE_VMID")

    # Extract IP address and subnet mask from CIDR notation
    IFS='/' read -r start_ip_addr subnet_mask <<< "$START_IP"

    # Convert starting IP to integer for incrementing
    local start_ip_int
    start_ip_int=$(__ip_to_int__ "$start_ip_addr")

    # Calculate end VMID
    local end_vmid=$((START_VMID + COUNT - 1))

    __info__ "Cloning VM ${SOURCE_VMID} (on node ${source_node}) to create ${COUNT} new VMs (${START_VMID}-${end_vmid})"
    __info__ "Network: ${START_IP} on bridge ${BRIDGE}"
    [[ -n "$GATEWAY" ]] && __info__ "Gateway: ${GATEWAY}"
    [[ -n "$POOL" ]] && __info__ "VMs will be added to pool: ${POOL}"

    # Track success and failures
    local success=0
    local failed=0

    # Clone VMs sequentially
    for (( i=0; i<COUNT; i++ )); do
        local target_vmid=$((START_VMID + i))
        local name_index=$((i + 1))
        local vm_name="${BASE_NAME}${name_index}"
        local current=$((i + 1))

        # Calculate current IP address
        local current_ip_int=$((start_ip_int + i))
        local current_ip
        current_ip=$(__int_to_ip__ "$current_ip_int")

        __update__ "Cloning VM ${target_vmid} (${current}/${COUNT}) with IP ${current_ip}..."

        # Build clone command
        local clone_cmd="qm clone ${SOURCE_VMID} ${target_vmid} --name ${vm_name}"

        # Execute clone on source VM's node
        if ! __node_exec__ "$source_node" "$clone_cmd" &>/dev/null; then
            __warn__ "Failed to clone VM ${target_vmid}"
            ((failed++))
            continue
        fi

        # Configure Cloud-Init network settings
        local ipconfig="ip=${current_ip}/${subnet_mask}"
        [[ -n "$GATEWAY" ]] && ipconfig+=",gw=${GATEWAY}"

        if ! __node_exec__ "$source_node" "qm set ${target_vmid} --ipconfig0 ${ipconfig}" &>/dev/null; then
            __warn__ "Failed to set IP config for VM ${target_vmid}"
            ((failed++))
            continue
        fi

        # Set network bridge
        if ! __node_exec__ "$source_node" "qm set ${target_vmid} --net0 virtio,bridge=${BRIDGE}" &>/dev/null; then
            __warn__ "Failed to set network bridge for VM ${target_vmid}"
            ((failed++))
            continue
        fi

        # Add to pool if specified
        if [[ -n "$POOL" ]]; then
            if ! __node_exec__ "$source_node" "qm set ${target_vmid} --pool ${POOL}" &>/dev/null; then
                __warn__ "Failed to add VM ${target_vmid} to pool ${POOL}"
                # Don't count this as a failure since VM was cloned successfully
            fi
        fi

        ((success++))
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
#   - Pending validation on Proxmox VE cluster
