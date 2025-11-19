#!/bin/bash
#
# BulkBackup.sh
#
# Backs up virtual machines (VMs) to specified storage using vzdump.
# Automatically detects which node each VM is on and executes the backup cluster-wide.
#
# Usage:
#   BulkBackup.sh <start_vm_id> <end_vm_id> <storage> [mode]
#
# Arguments:
#   start_vm_id - Starting VM ID
#   end_vm_id   - Ending VM ID
#   storage     - Target storage location for backups
#   mode        - Optional backup mode: snapshot (default), suspend, or stop
#
# Examples:
#   BulkBackup.sh 500 525 local
#   BulkBackup.sh 500 525 pbs-backup snapshot
#   BulkBackup.sh 500 525 local stop
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
# shellcheck source=Utilities/BulkOperations.sh
source "${UTILITYPATH}/BulkOperations.sh"
# shellcheck source=Utilities/Operations.sh
source "${UTILITYPATH}/Operations.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
__parse_args__ "start_vmid:vmid end_vmid:vmid storage:string mode:string:?" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    # Set default mode
    MODE="${MODE:-snapshot}"

    # Validate backup mode
    if [[ ! "$MODE" =~ ^(snapshot|suspend|stop)$ ]]; then
        __err__ "Invalid backup mode: ${MODE}. Must be: snapshot, suspend, or stop"
        exit 1
    fi

    __info__ "Bulk backup (cluster-wide): VMs ${START_VMID} to ${END_VMID}"
    __info__ "Target storage: ${STORAGE}, Mode: ${MODE}"

    # Verify storage exists
    if ! pvesm status 2>/dev/null | grep -q "^${STORAGE}"; then
        __err__ "Storage '${STORAGE}' not found"
        __info__ "Available storages:"
        pvesm status 2>/dev/null | awk 'NR>1 {print "  - " $1}'
        exit 1
    fi

    [[ "$MODE" == "stop" ]] && __warn__ "Stop mode: VMs will experience downtime"

    if ! __prompt_user_yn__ "Proceed with backup?"; then
        __info__ "Backup cancelled"
        exit 0
    fi

    backup_vm_callback() {
        local vmid="$1"
        __vm_backup__ "$vmid" "$STORAGE" "$MODE"
    }

    __bulk_vm_operation__ --name "Backup" --report "$START_VMID" "$END_VMID" backup_vm_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "All backups completed successfully!"
}

main

# Testing status:
#   - Updated to use ArgumentParser and BulkOperations framework
#   - Pending validation
