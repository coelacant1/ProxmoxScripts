#!/bin/bash
#
# BulkRemoteMigrate.sh
#
# Migrates virtual machines (VMs) from this Proxmox cluster to a target remote Proxmox node.
# Utilizes the Proxmox API for migration and requires authentication using an API token.
# Removes existing Cloud-Init drives before migration and adjusts VM IDs based on offset.
# Automatically detects which node each VM is on in the source cluster.
#
# Usage:
#   ./BulkRemoteMigrate.sh <first_vm_id> <last_vm_id> <target_host> <api_token> <fingerprint> <target_storage> <vm_offset> <target_network>
#
# Arguments:
#   first_vm_id     - The ID of the first VM to migrate.
#   last_vm_id      - The ID of the last VM to migrate.
#   target_host     - The hostname or IP address of the target Proxmox server.
#   api_token       - The API token used for authentication.
#   fingerprint     - The SSL fingerprint of the target Proxmox server.
#   target_storage  - The storage identifier on the target node.
#   vm_offset       - Integer value to offset VM IDs to avoid conflicts.
#   target_network  - The network bridge on the target server.
#
# Examples:
#   ./BulkRemoteMigrate.sh 400 410 192.168.1.20 user@pve!tokenid=abc-123 AA:BB:CC local-lvm 1000 vmbr0
#   This will migrate VMs 400-410 from their current nodes to the remote target
#
# Function Index:
#   - usage
#   - parse_args
#   - migrate_vm
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
# @function usage
# @description Prints usage information and exits.
usage() {
    cat <<-USAGE
Usage: ${0##*/} <first_vm_id> <last_vm_id> <target_host> <api_token> <fingerprint> <target_storage> <vm_offset> <target_network>

Migrates VMs from current cluster to a remote target Proxmox node.
Automatically detects which node each VM is on.

Arguments:
  first_vm_id     - The ID of the first VM to migrate
  last_vm_id      - The ID of the last VM to migrate
  target_host     - Target Proxmox server hostname or IP
  api_token       - API token for authentication
  fingerprint     - SSL fingerprint of target server
  target_storage  - Storage identifier on target node
  vm_offset       - Integer to offset VM IDs on target
  target_network  - Network bridge on target server

Examples:
  ${0##*/} 400 410 192.168.1.20 user@pve!tokenid=abc local-lvm 1000 vmbr0
USAGE
}

# --- parse_args --------------------------------------------------------------
# @function parse_args
# @description Parses and validates command-line arguments.
# @param @ All command-line arguments
parse_args() {
    if [[ $# -lt 8 ]]; then
        __err__ "Missing required arguments"
        usage
        exit 64
    fi

    FIRST_VM_ID="$1"
    LAST_VM_ID="$2"
    TARGET_HOST="$3"
    API_TOKEN="apitoken=$4"
    FINGERPRINT="$5"
    TARGET_STORAGE="$6"
    VM_OFFSET="$7"
    TARGET_NETWORK="$8"
    # Validate VM IDs are numeric
    if ! [[ "$FIRST_VM_ID" =~ ^[0-9]+$ ]] || ! [[ "$LAST_VM_ID" =~ ^[0-9]+$ ]]; then
        __err__ "VM IDs must be numeric"
        exit 64
    fi

    # Validate range
    if (( FIRST_VM_ID > LAST_VM_ID )); then
        __err__ "First VM ID must be less than or equal to last VM ID"
        exit 64
    fi

    # Validate VM offset is numeric
    if ! [[ "$VM_OFFSET" =~ ^[0-9]+$ ]]; then
        __err__ "VM offset must be numeric"
        exit 64
    fi
}

# --- migrate_vm --------------------------------------------------------------
# @function migrate_vm
# @description Migrates a single VM to the target node.
# @param 1 VM ID to migrate
migrate_vm() {
    local vmid="$1"
    local source_node
    local target_vmid=$((vmid + VM_OFFSET))
    
    source_node=$(__get_vm_node__ "$vmid")
    
    if [[ -z "$source_node" ]]; then
        __update__ "VM ${vmid} not found in cluster, skipping"
        return 0
    fi
    
    __update__ "Removing Cloud-Init drive (ide2) for VM ${vmid} on ${source_node}..."
    qm set "$vmid" --delete ide2 --node "$source_node" 2>/dev/null || true
    
    __update__ "Migrating VM ${vmid} (on ${source_node}) to VM ${target_vmid} on ${TARGET_HOST}..."
    
    local migrate_cmd="qm remote-migrate ${vmid} ${target_vmid} '${API_TOKEN},host=${TARGET_HOST},fingerprint=${FINGERPRINT}' --target-bridge ${TARGET_NETWORK} --target-storage ${TARGET_STORAGE} --online"
    
    if eval "$migrate_cmd" 2>/dev/null; then
        __ok__ "VM ${vmid} migrated successfully to ${target_vmid} on ${TARGET_HOST}"
    else
        __err__ "Failed to migrate VM ${vmid}"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
# @function main
# @description Main script logic - iterates through VM range and migrates each.
main() {
    __check_root__
    __check_proxmox__
    
    __info__ "Bulk remote migrate (cluster-wide): VMs ${FIRST_VM_ID} to ${LAST_VM_ID}"
    __info__ "Target: ${TARGET_HOST}, Offset: ${VM_OFFSET}"
    
    # Migrate VMs in the specified range
    local failed_count=0
    local processed_count=0
    
    for (( vm_id=FIRST_VM_ID; vm_id<=LAST_VM_ID; vm_id++ )); do
        if migrate_vm "$vm_id"; then
            ((processed_count++))
        else
            ((failed_count++))
        fi
    done
    
    __info__ "Processed ${processed_count} VM(s)"
    
    if (( failed_count > 0 )); then
        __err__ "Migration completed with ${failed_count} failure(s)"
        exit 1
    else
        __ok__ "All VMs migrated successfully"
    fi
}

parse_args "$@"
main

# Testing status:
#   - 2025-10-14: Updated to follow contributing guidelines, converted to cluster-wide
