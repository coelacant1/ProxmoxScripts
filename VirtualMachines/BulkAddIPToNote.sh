#!/bin/bash
#
# BulkAddIPToNote.sh
#
# Retrieves the IP address of each QEMU virtual machine (VM) in a specified range within the
# Proxmox VE cluster and updates or appends this information to the notes field of the respective VM.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# If the VM has Cloud-Init or QEMU Guest Agent, the IP will be retrieved from there.
# Otherwise, it will attempt to scan the network for the IP based on the MAC address using arp-scan.
#
# If the notes field already has "IP Address: ...", that line will be updated
# with the new IP, rather than adding a duplicate line.
#
# Usage:
#   ./BulkAddIPToNote.sh <first_vm_id> <last_vm_id>
#
# Arguments:
#   first_vm_id - The ID of the first VM to process.
#   last_vm_id  - The ID of the last VM to process.
#
# Examples:
#   ./BulkAddIPToNote.sh 400 430
#   This will update notes for VMs 400-430 regardless of which nodes they are on
#
# Function Index:
#   - usage
#   - parse_args
#   - update_vm_note
#   - main
#

set -u

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Queries.sh
source "${UTILITYPATH}/Queries.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- usage -------------------------------------------------------------------
usage() {
    cat <<-USAGE
Usage: ${0##*/} <first_vm_id> <last_vm_id>

Updates VM notes with IP addresses across the entire cluster.
Automatically detects which node each VM is on.

Arguments:
  first_vm_id  - The ID of the first VM to update
  last_vm_id   - The ID of the last VM to update

Examples:
  ${0##*/} 400 430
USAGE
}

# --- parse_args --------------------------------------------------------------
parse_args() {
    if [[ $# -lt 2 ]]; then
        __err__ "Missing required arguments"
        usage
        exit 64
    fi

    FIRST_VM_ID="$1"
    LAST_VM_ID="$2"

    if ! [[ "$FIRST_VM_ID" =~ ^[0-9]+$ ]] || ! [[ "$LAST_VM_ID" =~ ^[0-9]+$ ]]; then
        __err__ "VM IDs must be numeric"
        exit 64
    fi

    if (( FIRST_VM_ID > LAST_VM_ID )); then
        __err__ "First VM ID must be less than or equal to last VM ID"
        exit 64
    fi
}

# --- update_vm_note ----------------------------------------------------------
update_vm_note() {
    local vmid="$1"
    local node
    
    node=$(__get_vm_node__ "$vmid")
    
    if [[ -z "$node" ]]; then
        __update__ "VM ${vmid} not found in cluster, skipping"
        return 0
    fi
    
    __update__ "Processing VM ${vmid} on node ${node}..."
    
    # Try to retrieve IP address via guest agent
    local ip_address
    ip_address=$(qm guest exec "$vmid" "ip -o -4 addr list eth0 | awk '{print \$4}' | cut -d/ -f1" 2>/dev/null || true)
    
    if [[ -z "$ip_address" ]]; then
        __update__ "  Unable to retrieve IP via guest agent, trying ARP scan..."
        
        # Get the MAC address (assuming net0)
        local mac_address
        mac_address=$(qm config "$vmid" --node "$node" 2>/dev/null | grep -E '^net[0-9]+:' | grep -oE '([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}' | head -n1)
        
        if [[ -z "$mac_address" ]]; then
            __update__ "  Could not retrieve MAC address for VM ${vmid}"
            ip_address="Could not determine IP address"
        else
            # Get the bridge/VLAN
            local vlan
            vlan=$(qm config "$vmid" --node "$node" 2>/dev/null | grep -E '^net[0-9]+:' | grep -oP 'bridge=\K[^,]+' | head -n1)
            
            if [[ -n "$vlan" ]]; then
                # Run arp-scan to find IP by MAC
                ip_address=$(arp-scan --interface="$vlan" --localnet 2>/dev/null | grep -i "$mac_address" | awk '{print $1}' | head -n1)
                
                if [[ -z "$ip_address" ]]; then
                    __update__ "  Unable to determine IP via ARP scan"
                    ip_address="Could not determine IP address"
                else
                    __update__ "  Retrieved IP via ARP scan: ${ip_address}"
                fi
            else
                ip_address="Could not determine IP address"
            fi
        fi
    else
        __update__ "  Retrieved IP via guest agent: ${ip_address}"
    fi
    
    # Retrieve existing notes
    local existing_notes
    existing_notes=$(qm config "$vmid" --node "$node" 2>/dev/null | sed -n 's/^notes: //p' || true)
    
    # Update or append IP address line
    local updated_notes
    if echo "$existing_notes" | grep -q "^IP Address:"; then
        # Update existing line
        updated_notes=$(echo "$existing_notes" | sed -E "s|^IP Address:.*|IP Address: $ip_address|")
    else
        # Append new line
        if [[ -n "$existing_notes" ]]; then
            updated_notes="${existing_notes}

IP Address: $ip_address"
        else
            updated_notes="IP Address: $ip_address"
        fi
    fi
    
    # Update VM notes
    if qm set "$vmid" --description "$updated_notes" --node "$node" 2>/dev/null; then
        __ok__ "Updated notes for VM ${vmid} on ${node}: ${ip_address}"
    else
        __err__ "Failed to update notes for VM ${vmid}"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    __install_or_prompt__ "arp-scan"
    
    __info__ "Bulk add IP to note (cluster-wide): VMs ${FIRST_VM_ID} to ${LAST_VM_ID}"
    
    local failed_count=0
    local processed_count=0
    
    for (( vm_id=FIRST_VM_ID; vm_id<=LAST_VM_ID; vm_id++ )); do
        if update_vm_note "$vm_id"; then
            ((processed_count++))
        else
            ((failed_count++))
        fi
    done
    
    __info__ "Processed ${processed_count} VM(s)"
    
    if (( failed_count > 0 )); then
        __err__ "Update completed with ${failed_count} failure(s)"
        exit 1
    else
        __ok__ "All VM notes updated successfully"
    fi
}

parse_args "$@"
main

# Testing status:
#   - 2025-10-14: Converted to cluster-wide with standard structure
