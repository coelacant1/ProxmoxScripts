#!/bin/bash
#
# BulkChangeIP.sh
#
# Updates IP addresses of a range of VMs within a Proxmox VE environment.
# Assigns each VM a unique static IP incrementing from a starting IP address,
# updates network bridge configuration, and regenerates Cloud-Init image.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   ./BulkChangeIP.sh <start_vm_id> <end_vm_id> <start_ip/cidr> <bridge> [gateway]
#
# Arguments:
#   start_vm_id  - The ID of the first VM to update.
#   end_vm_id    - The ID of the last VM to update.
#   start_ip/cidr - Starting IP address with CIDR notation (e.g., 192.168.1.50/24).
#   bridge       - Network bridge (e.g., vmbr0).
#   gateway      - Optional. Gateway IP address.
#
# Examples:
#   ./BulkChangeIP.sh 400 430 192.168.1.50/24 vmbr0 192.168.1.1
#   ./BulkChangeIP.sh 400 430 192.168.1.50/24 vmbr0
#
# Function Index:
#   - usage
#   - parse_args
#   - change_ip
#   - main
#

set -u

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- usage -------------------------------------------------------------------
# @function usage
# @description Prints usage information and exits.
usage() {
    cat <<-USAGE
Usage: ${0##*/} <start_vm_id> <end_vm_id> <start_ip/cidr> <bridge> [gateway] [node]

Updates IP addresses for a range of VMs with incrementing IPs.

Arguments:
  start_vm_id   - The ID of the first VM to update
  end_vm_id     - The ID of the last VM to update
  start_ip/cidr - Starting IP with CIDR (e.g., 192.168.1.50/24)
  bridge        - Network bridge (e.g., vmbr0)
  gateway       - Optional gateway IP address
Examples:
USAGE
}

# --- parse_args --------------------------------------------------------------
# @function parse_args
# @description Parses and validates command-line arguments.
# @param @ All command-line arguments
parse_args() {
    if [[ $# -lt 4 ]]; then
        __err__ "Missing required arguments"
        usage
        exit 64
    fi

    START_VM_ID="$1"
    END_VM_ID="$2"
    START_IP_CIDR="$3"
    BRIDGE="$4"
    GATEWAY="${5:-}"
        # Validate VM IDs are numeric
    if ! [[ "$START_VM_ID" =~ ^[0-9]+$ ]] || ! [[ "$END_VM_ID" =~ ^[0-9]+$ ]]; then
        __err__ "VM IDs must be numeric"
        exit 64
    fi

    # Validate range
    if (( START_VM_ID > END_VM_ID )); then
        __err__ "Start VM ID must be less than or equal to end VM ID"
        exit 64
    fi
    
    # Parse IP and CIDR
    IFS='/' read -r START_IP SUBNET_MASK <<< "$START_IP_CIDR"
}

# --- change_ip ---------------------------------------------------------------
# @function change_ip
# @description Changes IP configuration for a VM.
# @param 1 VM ID
# @param 2 New IP address
change_ip() {
    local vmid="$1"
    local new_ip="$2"
    local node
    
    node=$(__get_vm_node__ "$vmid")
    
    if [[ -z "$node" ]]; then
        __update__ "VM ${vmid} not found in cluster, skipping"
        return 0
    fi
    
    __update__ "Updating VM ${vmid} with IP ${new_ip}/${SUBNET_MASK} on node ${node}..."
    
    local ipconfig="ip=${new_ip}/${SUBNET_MASK}"
    [[ -n "$GATEWAY" ]] && ipconfig="${ipconfig},gw=${GATEWAY}"
    
    if qm set "$vmid" --ipconfig0 "$ipconfig" --node "$node" 2>/dev/null; then
        if qm set "$vmid" --net0 "virtio,bridge=${BRIDGE}" --node "$node" 2>/dev/null; then
            qm cloudinit dump "$vmid" --node "$node" 2>/dev/null || true
            __ok__ "IP updated for VM ${vmid}: ${new_ip}/${SUBNET_MASK} on ${node}"
        else
            __err__ "Failed to update network bridge for VM ${vmid}"
            return 1
        fi
    else
        __err__ "Failed to update IP for VM ${vmid}"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
# @function main
# @description Main script logic - iterates through VM range and updates IPs.
main() {
    __check_root__
    __check_proxmox__
    
    __info__ "Bulk change IP: VMs ${START_VM_ID} to ${END_VM_ID} (cluster-wide)"
    __info__ "Starting IP: ${START_IP}/${SUBNET_MASK}, Bridge: ${BRIDGE}"
    [[ -n "$GATEWAY" ]] && __info__ "Gateway: ${GATEWAY}"
        # Convert start IP to integer for incrementing
    local start_ip_int
    start_ip_int=$(__ip_to_int__ "$START_IP")
    
    # Update IPs for VMs in the specified range
    local failed_count=0
    local processed_count=0
    for (( vmid=START_VM_ID; vmid<=END_VM_ID; vmid++ )); do
        local current_ip_int=$((start_ip_int + vmid - START_VM_ID))
        local new_ip
        new_ip=$(__int_to_ip__ "$current_ip_int")
        
        if change_ip "$vmid" "$new_ip"; then
            ((processed_count++))
        else
            ((failed_count++))
        fi
    done
    
    __info__ "Processed ${processed_count} VM(s)"
    
    
    
    if (( failed_count > 0 )); then
        __err__ "Operation completed with ${failed_count} failure(s)"
        exit 1
    else
        __ok__ "IP addresses updated successfully for all VMs"
    fi
}

parse_args "$@"
main

# Testing status:
#   - 2025-10-14: Updated to follow contributing guidelines, converted to cluster-wide
