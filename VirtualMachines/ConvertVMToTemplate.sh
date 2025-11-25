#!/bin/bash
#
# ConvertVMToTemplate.sh
#
# Converts a specific VM (qemu) to a template. Templates cannot be started but can
# be cloned to create new VMs quickly. This is useful for creating base images.
#
# The script performs the following:
#   1. Verifies the VMID exists and is a VM (not a container)
#   2. Checks if VM is currently running (must be stopped first)
#   3. Optionally creates a backup before conversion
#   4. Converts the VM to a template
#   5. Optionally sets a description for the template
#
# Usage:
#   ConvertVMToTemplate.sh <vmid> [options]
#
# Arguments:
#   vmid - The VM ID to convert to a template
#
# Optional Arguments:
#   --backup              - Create a backup before converting
#   --backup-storage <s>  - Storage for backup (default: local)
#   --description <desc>  - Set template description
#   --force               - Skip confirmation prompt
#
# Examples:
#   # Convert VM 100 to template
#   ConvertVMToTemplate.sh 100
#
#   # Convert with backup
#   ConvertVMToTemplate.sh 100 --backup --backup-storage PBS-Backup
#
#   # Convert with description
#   ConvertVMToTemplate.sh 100 --description "Ubuntu 22.04 Base Template"
#
#   # Force conversion without prompt
#   ConvertVMToTemplate.sh 100 --force
#
# Notes:
#   - VMs must be stopped before conversion
#   - Containers (LXC) cannot be converted to templates using this script
#   - Templates can be converted back to VMs using the Proxmox web UI
#   - Consider cleaning the VM before conversion (remove SSH keys, logs, etc.)
#
# Function Index:
#   - create_backup
#   - convert_to_template
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Cluster.sh
source "${UTILITYPATH}/Cluster.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

__parse_args__ "vmid:vmid --backup:flag --backup-storage:storage:local --description:string:? --force:flag" "$@"

# --- create_backup -----------------------------------------------------------
# @function create_backup
# @description Creates a backup of the VM before conversion
create_backup() {
    __info__ "Creating backup of VM ${VMID} to storage: ${BACKUP_STORAGE}"

    # Validate backup storage exists
    if ! pvesm status --storage "$BACKUP_STORAGE" &>/dev/null; then
        __err__ "Backup storage '${BACKUP_STORAGE}' not found"
        __info__ "Available storages:"
        pvesm status | tail -n +2 | awk '{print "  - " $1}'
        exit 1
    fi

    # Get VM name for backup
    local vm_name
    vm_name=$(qm config "$VMID" | grep -E "^name:" | awk '{print $2}')
    vm_name="${vm_name:-VM-${VMID}}"

    __info__ "Backup name: ${vm_name}"

    # Create backup
    if vzdump "$VMID" --storage "$BACKUP_STORAGE" --mode snapshot --compress zstd 2>&1; then
        __ok__ "Backup created successfully"
    else
        __err__ "Backup failed"
        if [[ "$FORCE" != "true" ]] && ! __prompt_user_yn__ "Continue with conversion anyway?"; then
            __info__ "Operation cancelled"
            exit 1
        fi
        __warn__ "Proceeding without backup"
    fi
}

# --- convert_to_template -----------------------------------------------------
# @function convert_to_template
# @description Converts the VM to a template
convert_to_template() {
    __info__ "Converting VM ${VMID} to template"

    # Add description if provided
    if [[ -n "$DESCRIPTION" ]]; then
        __info__ "Setting template description"
        if qm set "$VMID" --description "$DESCRIPTION" 2>&1; then
            __ok__ "Description set"
        else
            __warn__ "Failed to set description (will continue anyway)"
        fi
    fi

    # Perform conversion
    if qm template "$VMID" 2>&1; then
        __ok__ "VM ${VMID} successfully converted to template"
        return 0
    else
        __err__ "Failed to convert VM ${VMID} to template"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
# @function main
# @description Main script logic
main() {
    __check_root__
    __check_proxmox__

    # Validate VM exists
    __info__ "Validating VMID ${VMID}"
    if ! __validate_vmid__ "$VMID"; then
        __err__ "VMID ${VMID} is not a valid VM"
        __info__ "Available VMs:"
        qm list | tail -n +2 | awk '{print "  VMID " $1 ": " $2}'
        exit 1
    fi
    __ok__ "VMID ${VMID} is a valid VM"

    # Get VM info
    __info__ "Retrieving VM information"
    local vm_name
    local vm_memory
    local vm_cores
    local vm_disk

    vm_name=$(qm config "$VMID" | grep -E "^name:" | awk '{print $2}' || echo "VM-${VMID}")
    vm_memory=$(qm config "$VMID" | grep -E "^memory:" | awk '{print $2}' || echo "Unknown")
    vm_cores=$(qm config "$VMID" | grep -E "^cores:" | awk '{print $2}' || echo "Unknown")
    vm_disk=$(qm config "$VMID" | grep -E "^(scsi|sata|virtio)0:" | awk '{print $2}' || echo "Unknown")

    __ok__ "VM information retrieved"

    # Display VM details
    echo
    echo "VM Details:"
    echo "==========="
    echo "  VMID:   ${VMID}"
    echo "  Name:   ${vm_name}"
    echo "  Memory: ${vm_memory} MB"
    echo "  Cores:  ${vm_cores}"
    echo "  Disk:   ${vm_disk}"
    echo

    if [[ -n "$DESCRIPTION" ]]; then
        echo "  Template Description: ${DESCRIPTION}"
        echo
    fi

    # Check VM status and stop if needed
    __info__ "Checking VM status"
    if [[ "$FORCE" == "true" ]]; then
        if ! __check_vm_status__ "$VMID" --stop --force; then
            __err__ "Failed to stop VM ${VMID}"
            exit 1
        fi
    else
        if ! __check_vm_status__ "$VMID" --stop; then
            __info__ "Operation cancelled"
            exit 0
        fi
    fi
    __ok__ "VM ${VMID} is stopped and ready for conversion"

    # Confirm conversion
    if [[ "$FORCE" != "true" ]]; then
        echo
        __warn__ "This will convert VM ${VMID} (${vm_name}) to a template"
        __warn__ "Templates cannot be started, only cloned"
        echo

        if ! __prompt_user_yn__ "Proceed with conversion?"; then
            __info__ "Operation cancelled"
            exit 0
        fi
    fi

    # Create backup if requested
    if [[ "$BACKUP" == "true" ]]; then
        echo
        create_backup
    fi

    # Convert to template
    echo
    convert_to_template

    # Display final status
    echo
    __info__ "Template information:"
    qm config "$VMID" | head -15

    echo
    __ok__ "Conversion complete!"
    __info__ "Template ${VMID} (${vm_name}) is ready for cloning"
    __info__ "Use 'qm clone ${VMID} <new-vmid>' to create VMs from this template"
}

###############################################################################
# Script Entry Point
###############################################################################
main "$@"

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-24
#
# Changes:
# - 2025-11-24: Validated against PVE Guide Chapter 10 (qm template command)
# - 2025-11-20: Uses utility functions
# - 2025-11-20: Updated to use ArgumentParser.sh
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# -
#
# Known issues:
# -
#

