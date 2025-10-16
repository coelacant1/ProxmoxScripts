#!/bin/bash
#
# BulkMoveCloudInit.sh
#
# Automates migration of Cloud-Init disks for LXC containers or VMs within a Proxmox VE environment.
# Allows bulk migration by specifying a range of VM IDs or selecting all VMs.
# Backs up existing Cloud-Init parameters, deletes current Cloud-Init disk, and recreates it on target storage.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   ./BulkMoveCloudInit.sh <start_vmid|ALL> <end_vmid|target_storage> [target_storage]
#
# Arguments:
#   start_vmid      - The starting VM ID for migration. Use "ALL" to target all VMs.
#   end_vmid        - If start_vmid is a number, this is the ending VM ID.
#                     If start_vmid is "ALL", this argument becomes the target storage.
#   target_storage  - The target storage for the Cloud-Init disk.
#
# Examples:
#   ./BulkMoveCloudInit.sh 100 200 local-lvm
#   ./BulkMoveCloudInit.sh ALL ceph-storage
#
# Function Index:
#   - usage
#   - check_storage_exists
#   - get_current_storage
#   - migrate_cloud_init_disk
#   - parse_args
#   - main
#

set -e

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
Usage: ${0##*/} <start_vmid|ALL> <end_vmid|target_storage> [target_storage] [node]

Migrates Cloud-Init disks to different storage.

Arguments:
  start_vmid      - Starting VM ID or 'ALL' for all VMs
  end_vmid        - Ending VM ID (or target storage if start is 'ALL')
  target_storage  - Target storage identifier
Examples:
USAGE
}

# --- check_storage_exists ----------------------------------------------------
# @function check_storage_exists
# @description Checks if a storage exists.
# @param 1 Storage name
check_storage_exists() {
    local storage=$1
    if ! pvesh get /storage 2>/dev/null | grep -qw "$storage"; then
        __err__ "Storage '${storage}' does not exist"
        exit 1
    fi
}

# --- get_current_storage -----------------------------------------------------
# @function get_current_storage
# @description Gets the current Cloud-Init disk storage.
# @param 1 VM ID
# @param 2 Node name
get_current_storage() {
    local vmid=$1
    local node=$2
    local storage
    storage=$(qm config "$vmid" --node "$node" 2>/dev/null | grep -E 'sata1:|ide2:' | awk -F ':' '{print $2}' | awk -F',' '{print $1}' | awk -F' ' '{print $1}')
    echo "$storage"
}

# --- migrate_cloud_init_disk -------------------------------------------------
# @function migrate_cloud_init_disk
# @description Migrates the Cloud-Init disk for a VM.
# @param 1 VM ID
migrate_cloud_init_disk() {
    local vmid=$1
    local node
    
    node=$(__get_vm_node__ "$vmid")
    
    if [[ -z "$node" ]]; then
        __update__ "VM ${vmid} not found in cluster, skipping"
        return 0
    fi
    
    __update__ "Processing VM ${vmid} on node ${node}..."
    
    # Get current Cloud-Init disk storage
    local CURRENT_STORAGE
    CURRENT_STORAGE=$(get_current_storage "$vmid" "$node")
    
    if [[ -z "$CURRENT_STORAGE" ]]; then
        __update__ "VM ${vmid} does not have a Cloud-Init disk attached, skipping"
        return 0
    fi
    
    # Check if already on target storage
    if [[ "$CURRENT_STORAGE" == "$TARGET_STORAGE" ]]; then
        __update__ "VM ${vmid} Cloud-Init disk already on ${TARGET_STORAGE}, skipping"
        return 0
    fi
    
    __update__ "Backing up Cloud-Init parameters for VM ${vmid}... on ${node}"
    local CI_USER CI_PASSWORD CI_IPCONFIG CI_NAMESERVER CI_SEARCHDOMAIN CI_SSHKEYS
    CI_USER=$(qm config "$vmid" --node "$node" 2>/dev/null | grep -oP '(?<=^ciuser: ).*' || true)
    CI_PASSWORD=$(qm config "$vmid" --node "$node" 2>/dev/null | grep -oP '(?<=^cipassword: ).*' || true)
    CI_IPCONFIG=$(qm config "$vmid" --node "$node" 2>/dev/null | grep -oP '(?<=^ipconfig0: ).*' || true)
    CI_NAMESERVER=$(qm config "$vmid" --node "$node" 2>/dev/null | grep -oP '(?<=^nameserver: ).*' || true)
    CI_SEARCHDOMAIN=$(qm config "$vmid" --node "$node" 2>/dev/null | grep -oP '(?<=^searchdomain: ).*' || true)
    CI_SSHKEYS=$(qm config "$vmid" --node "$node" 2>/dev/null | grep -oP '(?<=^sshkeys: ).*' | sed 's/%0A/\n/g' | sed 's/%20/ /g' || true)
    
    if [[ -z "$CI_USER" ]] && [[ -z "$CI_IPCONFIG" ]]; then
        __update__ "VM ${vmid} does not have Cloud-Init parameters, skipping on ${node}"
        return 0
    fi
    
    __update__ "Deleting existing Cloud-Init disk for VM ${vmid}... on ${node}"
    qm set "$vmid" --delete sata1 --node "$node" 2>/dev/null || qm set "$vmid" --delete ide2 --node "$node" 2>/dev/null || true
    
    # Determine which interface was used
    local CI_INTERFACE="sata1"
    if qm config "$vmid" --node "$node" 2>/dev/null | grep -q "^ide2:"; then
        CI_INTERFACE="ide2"
    fi
    
    __update__ "Re-creating Cloud-Init disk for VM ${vmid} on ${TARGET_STORAGE}... on ${node}"
    local interface_type="${CI_INTERFACE%%[0-9]*}"
    qm set "$vmid" --"${interface_type}" "${TARGET_STORAGE}:cloudinit" --node "$node" 2>/dev/null
    
    __update__ "Restoring Cloud-Init parameters for VM ${vmid}... on ${node}"
    
    # Prepare SSH keys if they exist and are valid
    local TEMP_SSH_FILE=""
    local SSHKEYS_OPTION=""
    if [[ -n "$CI_SSHKEYS" ]] && [[ "$CI_SSHKEYS" =~ ^ssh-(rsa|dss|ed25519|ecdsa) ]]; then
        TEMP_SSH_FILE=$(mktemp)
        echo -e "$CI_SSHKEYS" > "$TEMP_SSH_FILE"
        SSHKEYS_OPTION="--sshkeys ${TEMP_SSH_FILE}"
    fi
    
    # Apply the restored parameters
    local cmd="qm set \"$vmid\" --node \"$node\""
    [[ -n "$CI_USER" ]] && cmd="$cmd --ciuser \"$CI_USER\""
    [[ -n "$CI_PASSWORD" ]] && cmd="$cmd --cipassword \"$CI_PASSWORD\""
    [[ -n "$CI_IPCONFIG" ]] && cmd="$cmd --ipconfig0 \"$CI_IPCONFIG\""
    [[ -n "$CI_NAMESERVER" ]] && cmd="$cmd --nameserver \"$CI_NAMESERVER\""
    [[ -n "$CI_SEARCHDOMAIN" ]] && cmd="$cmd --searchdomain \"$CI_SEARCHDOMAIN\""
    [[ -n "$SSHKEYS_OPTION" ]] && cmd="$cmd $SSHKEYS_OPTION"
    
    if eval "$cmd" 2>/dev/null; then
        __ok__ "Cloud-Init disk migrated for VM ${vmid} on ${node}"
    else
        __err__ "Failed to restore Cloud-Init parameters for VM ${vmid}"
        [[ -n "$TEMP_SSH_FILE" ]] && [[ -f "$TEMP_SSH_FILE" ]] && rm "$TEMP_SSH_FILE"
        return 1
    fi
    
    # Clean up temporary SSH key file
    [[ -n "$TEMP_SSH_FILE" ]] && [[ -f "$TEMP_SSH_FILE" ]] && rm "$TEMP_SSH_FILE"
}

# --- parse_args --------------------------------------------------------------
# @function parse_args
# @description Parses and validates command-line arguments.
# @param @ All command-line arguments
parse_args() {
    if [[ $# -lt 2 ]]; then
        __err__ "Missing required arguments"
        usage
        exit 64
    fi
    
    START_VMID="$1"
    END_VMID="$2"
    TARGET_STORAGE="${3:-}"
    # Determine VM IDs and target storage based on first argument
    if [[ "$START_VMID" == "ALL" ]]; then
        if [[ $# -lt 2 ]]; then
            __err__ "When using 'ALL', you must specify target storage"
            exit 64
        fi
        TARGET_STORAGE="$END_VMID"
        if [[ $# -ge 3 ]]; then
            TARGET_NODE="$3"
        fi
    else
        if [[ $# -lt 3 ]]; then
            __err__ "When specifying VM ID range, target storage must be provided"
            exit 64
        fi
        # Validate that START_VMID and END_VMID are integers
        if ! [[ "$START_VMID" =~ ^[0-9]+$ ]] || ! [[ "$END_VMID" =~ ^[0-9]+$ ]]; then
            __err__ "start_vmid and end_vmid must be positive integers"
            exit 64
        fi
    fi
}

# --- main --------------------------------------------------------------------
# @function main
# @description Main script logic - processes VMs and migrates Cloud-Init disks.
main() {
    __check_root__
    __check_proxmox__
    
    # Validate that TARGET_STORAGE exists
    check_storage_exists "$TARGET_STORAGE"
    
    __info__ "Bulk move Cloud-Init: Target storage ${TARGET_STORAGE} (cluster-wide)"
        # Determine VMIDS
    local VMIDS
    if [[ "$START_VMID" == "ALL" ]]; then
        __info__ "Processing all VMs on node ${node_name}"
        VMIDS=$(qm list --node "$node_name" 2>/dev/null | awk 'NR>1 {print $1}')
    else
        __info__ "Processing VMs ${START_VMID} to ${END_VMID}"
        VMIDS=$(seq "$START_VMID" "$END_VMID")
    fi
    
    # Loop through each VMID and migrate the Cloud-Init disk
    local failed_count=0
    local processed_count=0
    for VMID in $VMIDS; do
        if migrate_cloud_init_disk "$VMID"; then
            ((processed_count++))
        else
            ((failed_count++))
        fi
    done
    
    __info__ "Processed ${processed_count} VM(s)"
    
    
    
    if (( failed_count > 0 )); then
        __err__ "Cloud-Init disk migration completed with ${failed_count} failure(s)"
        exit 1
    else
        __ok__ "Cloud-Init disk migration process completed successfully"
    fi
}

parse_args "$@"
main

# Testing status:
#   - 2025-10-14: Updated to follow contributing guidelines, converted to cluster-wide
