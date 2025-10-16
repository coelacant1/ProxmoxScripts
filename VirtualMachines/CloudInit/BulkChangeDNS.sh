#!/bin/bash
#
# BulkChangeDNS.sh
#
# Updates DNS search domain and DNS server for a range of VMs within a Proxmox VE environment.
# Sets new DNS settings and regenerates Cloud-Init image to apply changes.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   ./BulkChangeDNS.sh <start_vm_id> <end_vm_id> <dns_server> <dns_search_domain>
#
# Arguments:
#   start_vm_id       - The ID of the first VM to update.
#   end_vm_id         - The ID of the last VM to update.
#   dns_server        - DNS server address.
#   dns_search_domain - DNS search domain.
#
# Examples:
#   ./BulkChangeDNS.sh 400 430 8.8.8.8 example.com
#   This will update DNS settings for VMs 400-430 regardless of which nodes they are on
#
# Function Index:
#   - usage
#   - parse_args
#   - change_dns
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
Usage: ${0##*/} <start_vm_id> <end_vm_id> <dns_server> <dns_search_domain>

Updates DNS settings for a range of VMs across the entire cluster.
Automatically detects which node each VM is on.

Arguments:
  start_vm_id       - The ID of the first VM to update
  end_vm_id         - The ID of the last VM to update
  dns_server        - DNS server address
  dns_search_domain - DNS search domain

Examples:
  ${0##*/} 400 430 8.8.8.8 example.com
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

    START_VMID="$1"
    END_VMID="$2"
    DNS_SERVER="$3"
    DNS_SEARCHDOMAIN="$4"

    # Validate VM IDs are numeric
    if ! [[ "$START_VMID" =~ ^[0-9]+$ ]] || ! [[ "$END_VMID" =~ ^[0-9]+$ ]]; then
        __err__ "VM IDs must be numeric"
        exit 64
    fi

    # Validate range
    if (( START_VMID > END_VMID )); then
        __err__ "Start VM ID must be less than or equal to end VM ID"
        exit 64
    fi
}

# --- change_dns --------------------------------------------------------------
# @function change_dns
# @description Changes DNS settings for a VM.
# @param 1 VM ID
change_dns() {
    local vmid="$1"
    local node
    
    node=$(__get_vm_node__ "$vmid")
    
    if [[ -z "$node" ]]; then
        __update__ "VM ${vmid} not found in cluster, skipping"
        return 0
    fi
    
    __update__ "Updating DNS settings for VM ${vmid} on node ${node}..."
    if qm set "$vmid" --nameserver "$DNS_SERVER" --searchdomain "$DNS_SEARCHDOMAIN" --node "$node" 2>/dev/null; then
        qm cloudinit dump "$vmid" --node "$node" 2>/dev/null || true
        __ok__ "DNS settings updated for VM ${vmid} on ${node}"
    else
        __err__ "Failed to update DNS for VM ${vmid}"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
# @function main
# @description Main script logic - iterates through VM range and updates DNS.
main() {
    __check_root__
    __check_proxmox__
    
    __info__ "Bulk change DNS (cluster-wide): VMs ${START_VMID} to ${END_VMID}"
    __info__ "DNS Server: ${DNS_SERVER}, Search Domain: ${DNS_SEARCHDOMAIN}"
    
    # Update DNS for VMs in the specified range
    local failed_count=0
    local processed_count=0
    
    for (( vmid=START_VMID; vmid<=END_VMID; vmid++ )); do
        if change_dns "$vmid"; then
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
        __ok__ "DNS settings updated successfully for all VMs"
    fi
}

parse_args "$@"
main

# Testing status:
#   - 2025-10-14: Converted to cluster-wide with auto-detection
