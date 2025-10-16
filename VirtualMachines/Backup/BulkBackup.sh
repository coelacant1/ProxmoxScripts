#!/bin/bash
#
# BulkBackup.sh
#
# Backs up virtual machines (VMs) within a Proxmox VE cluster to a specified storage.
# Automatically detects which node each VM is on and executes the backup cluster-wide.
# Supports multiple backup modes (snapshot, suspend, stop).
#
# Usage:
#   ./BulkBackup.sh <first_vm_id> <last_vm_id> <storage> [mode]
#
# Arguments:
#   first_vm_id - The ID of the first VM to back up.
#   last_vm_id  - The ID of the last VM to back up.
#   storage     - The target storage location for the backup.
#   mode        - Optional. Backup mode: snapshot, suspend, or stop (default: snapshot).
#
# Examples:
#   ./BulkBackup.sh 500 525 local
#   ./BulkBackup.sh 500 525 pbs-backup snapshot
#   ./BulkBackup.sh 500 525 local stop
#
# Function Index:
#   - usage
#   - parse_args
#   - backup_vm
#   - main
#

set -u

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Global variables
BACKUP_MODE="snapshot"

# --- usage -------------------------------------------------------------------
usage() {
    cat <<-USAGE
Usage: ${0##*/} <first_vm_id> <last_vm_id> <storage> [mode]

Backs up VMs across the entire cluster to specified storage.
Automatically detects which node each VM is on.

Arguments:
  first_vm_id  - The ID of the first VM to back up
  last_vm_id   - The ID of the last VM to back up
  storage      - Target storage location for backups
  mode         - Backup mode (optional, default: snapshot)

Backup Modes:
  snapshot     - Create backup while VM is running (default)
  suspend      - Suspend VM, backup, then resume
  stop         - Stop VM, backup, then restart

Examples:
  ${0##*/} 500 525 local
  ${0##*/} 500 525 pbs-backup snapshot
  ${0##*/} 500 525 local stop

Notes:
  - Snapshot mode is fastest and least disruptive
  - Stop mode ensures consistent backup but causes downtime
  - Backups are stored in VMA format with compression
USAGE
}

# --- parse_args --------------------------------------------------------------
parse_args() {
    if [[ $# -lt 3 ]]; then
        __err__ "Missing required arguments"
        usage
        exit 64
    fi

    FIRST_VM_ID="$1"
    LAST_VM_ID="$2"
    STORAGE="$3"
    
    if [[ $# -ge 4 ]]; then
        BACKUP_MODE="$4"
        
        # Validate backup mode
        if [[ ! "$BACKUP_MODE" =~ ^(snapshot|suspend|stop)$ ]]; then
            __err__ "Invalid backup mode: ${BACKUP_MODE}"
            __err__ "Must be one of: snapshot, suspend, stop"
            exit 64
        fi
    fi

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
}

# --- backup_vm ---------------------------------------------------------------
backup_vm() {
    local vmid="$1"
    local node
    
    node=$(__get_vm_node__ "$vmid")
    
    if [[ -z "$node" ]]; then
        __update__ "VM ${vmid} not found in cluster, skipping"
        return 0
    fi
    
    __update__ "Backing up VM ${vmid} on node ${node} to ${STORAGE} (mode: ${BACKUP_MODE})..."
    
    # Build vzdump command
    local backup_cmd="vzdump ${vmid} --storage ${STORAGE} --mode ${BACKUP_MODE} --compress gzip --node ${node}"
    
    # Execute backup
    if eval "$backup_cmd" 2>/dev/null; then
        __ok__ "VM ${vmid} backed up successfully from ${node}"
        return 0
    else
        __err__ "Failed to back up VM ${vmid}"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    
    __info__ "Bulk backup (cluster-wide): VMs ${FIRST_VM_ID} to ${LAST_VM_ID}"
    __info__ "Target storage: ${STORAGE}"
    __info__ "Backup mode: ${BACKUP_MODE}"
    
    # Verify storage exists
    if ! pvesm status 2>/dev/null | grep -q "^${STORAGE}"; then
        __err__ "Storage '${STORAGE}' not found or not accessible"
        __err__ "Available storages:"
        pvesm status 2>/dev/null | awk 'NR>1 {print "  - " $1}'
        exit 1
    fi
    
    # Estimate backup time warning
    local vm_count=$((LAST_VM_ID - FIRST_VM_ID + 1))
    __info__ "Estimated VMs to backup: ${vm_count}"
    
    if [[ "$BACKUP_MODE" == "stop" ]]; then
        __warn__ "Stop mode selected - VMs will experience downtime during backup"
    fi
    
    # Confirm before proceeding
    if ! __prompt_user_yn__ "Proceed with backup?"; then
        __info__ "Backup cancelled by user"
        exit 0
    fi
    
    local failed_count=0
    local processed_count=0
    local skipped_count=0
    local start_time=$(date +%s)
    
    for (( vm_id=FIRST_VM_ID; vm_id<=LAST_VM_ID; vm_id++ )); do
        # Check if VM exists
        local node
        node=$(__get_vm_node__ "$vm_id")
        
        if [[ -z "$node" ]]; then
            ((skipped_count++))
            continue
        fi
        
        if backup_vm "$vm_id"; then
            ((processed_count++))
        else
            ((failed_count++))
        fi
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Summary
    __info__ "Backup summary:"
    __info__ "  Backed up: ${processed_count}"
    __info__ "  Skipped: ${skipped_count}"
    __info__ "  Failed: ${failed_count}"
    __info__ "  Duration: ${duration} seconds"
    
    if (( failed_count > 0 )); then
        __err__ "Backup completed with ${failed_count} failure(s)"
        exit 1
    else
        __ok__ "All backups completed successfully"
    fi
}

parse_args "$@"
main

# Testing status:
#   - 2025-10-14: Converted to cluster-wide with multiple backup modes
