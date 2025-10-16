#!/bin/bash
#
# BulkAddSSHKey.sh
#
# Adds an SSH public key to a range of virtual machines (VMs) within a Proxmox VE environment.
# Appends a new SSH public key for each VM and regenerates the Cloud-Init image to apply changes.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   ./BulkAddSSHKey.sh <start_vm_id> <end_vm_id> <ssh_public_key>
#
# Arguments:
#   start_vm_id    - The ID of the first VM to update.
#   end_vm_id      - The ID of the last VM to update.
#   ssh_public_key - The SSH public key to add.
#
# Examples:
#   ./BulkAddSSHKey.sh 400 430 "ssh-rsa AAAAB3Nza... user@host"
#   This will add the SSH key to VMs 400-430 regardless of which nodes they are on
#
# Function Index:
#   - usage
#   - parse_args
#   - add_ssh_key
#   - cleanup
#   - main
#

set -u

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR
trap 'cleanup' EXIT

TMP_FILES=()

# --- usage -------------------------------------------------------------------
# @function usage
# @description Prints usage information and exits.
usage() {
    cat <<-USAGE
Usage: ${0##*/} <start_vm_id> <end_vm_id> <ssh_public_key>

Adds SSH public key to a range of VMs across the entire cluster.
Automatically detects which node each VM is on.

Arguments:
  start_vm_id    - The ID of the first VM to update
  end_vm_id      - The ID of the last VM to update
  ssh_public_key - SSH public key to add

Examples:
  ${0##*/} 400 430 "ssh-rsa AAAAB3Nza... user@host"
USAGE
}

# --- parse_args --------------------------------------------------------------
# @function parse_args
# @description Parses and validates command-line arguments.
# @param @ All command-line arguments
parse_args() {
    if [[ $# -lt 3 ]]; then
        __err__ "Missing required arguments"
        usage
        exit 64
    fi

    START_VM_ID="$1"
    END_VM_ID="$2"
    SSH_PUBLIC_KEY="$3"

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
}

# --- cleanup -----------------------------------------------------------------
# @function cleanup
# @description Cleans up temporary files.
cleanup() {
    for tmp_file in "${TMP_FILES[@]}"; do
        [[ -f "$tmp_file" ]] && rm -f "$tmp_file"
    done
}

# --- add_ssh_key -------------------------------------------------------------
# @function add_ssh_key
# @description Adds SSH key to a VM and regenerates Cloud-Init.
# @param 1 VM ID
add_ssh_key() {
    local vmid="$1"
    local node
    
    node=$(__get_vm_node__ "$vmid")
    
    if [[ -z "$node" ]]; then
        __update__ "VM ${vmid} not found in cluster, skipping"
        return 0
    fi
    
    local temp_file
    temp_file="$(mktemp)"
    TMP_FILES+=("$temp_file")
    
    __update__ "Adding SSH public key to VM ${vmid} on node ${node}..."
    if qm cloudinit get "$vmid" ssh-authorized-keys > "$temp_file" 2>/dev/null; then
        echo "$SSH_PUBLIC_KEY" >> "$temp_file"
        if qm set "$vmid" --sshkeys "$temp_file" --node "$node" 2>/dev/null; then
            qm cloudinit dump "$vmid" --node "$node" 2>/dev/null || true
            __ok__ "SSH key added to VM ${vmid} on ${node}"
        else
            __err__ "Failed to set SSH key for VM ${vmid}"
            return 1
        fi
    else
        __err__ "Failed to retrieve SSH keys for VM ${vmid}"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
# @function main
# @description Main script logic - iterates through VM range and adds SSH keys.
main() {
    __check_root__
    __check_proxmox__
    
    __info__ "Bulk add SSH key (cluster-wide): VMs ${START_VM_ID} to ${END_VM_ID}"
    
    # Add SSH keys to VMs in the specified range
    local failed_count=0
    local processed_count=0
    
    for (( vmid=START_VM_ID; vmid<=END_VM_ID; vmid++ )); do
        if add_ssh_key "$vmid"; then
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
        __ok__ "SSH keys added successfully to all VMs"
    fi
}

parse_args "$@"
main

# Testing status:
#   - 2025-10-14: Updated to follow contributing guidelines, added cluster support
