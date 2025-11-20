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
#   BulkMoveCloudInit.sh <start_vmid|ALL> <end_vmid|target_storage> [target_storage]
#
# Arguments:
#   start_vmid      - The starting VM ID for migration. Use "ALL" to target all VMs.
#   end_vmid        - If start_vmid is a number, this is the ending VM ID.
#                     If start_vmid is "ALL", this argument becomes the target storage.
#   target_storage  - The target storage for the Cloud-Init disk.
#
# Examples:
#   BulkMoveCloudInit.sh 100 200 local-lvm
#   BulkMoveCloudInit.sh ALL ceph-storage
#
# Function Index:
#   - check_storage_exists
#   - get_current_storage
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
# shellcheck source=Utilities/Cluster.sh
source "${UTILITYPATH}/Cluster.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments (handle special case: ALL for all VMs)
if [[ $# -ge 1 ]] && [[ "$1" == "ALL" ]]; then
    # ALL <target_storage>
    __parse_args__ "all:keyword target_storage:storage" "$@"
    START_VMID="ALL"
    END_VMID=""
else
    # <start_vmid> <end_vmid> <target_storage>
    __parse_args__ "start_vmid:vmid end_vmid:vmid target_storage:storage" "$@"
fi

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
get_current_storage() {
    local vmid=$1
    local node=$2
    local storage
    storage=$(qm config "$vmid" --node "$node" 2>/dev/null | grep -E 'sata1:|ide2:' | awk -F ':' '{print $2}' | awk -F',' '{print $1}' | awk -F' ' '{print $1}')
    echo "$storage"
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    # Validate that TARGET_STORAGE exists
    check_storage_exists "$TARGET_STORAGE"

    __info__ "Bulk move Cloud-Init: Target storage ${TARGET_STORAGE} (cluster-wide)"

    # Determine VM IDs to process
    local -a vm_ids=()
    if [[ "$START_VMID" == "ALL" ]]; then
        __info__ "Processing all VMs in cluster"
        local all_vms
        all_vms=$(__get_cluster_vms__)
        read -r -a vm_ids <<<"$all_vms"
    else
        __info__ "Processing VMs ${START_VMID} to ${END_VMID}"
        for ((vmid = START_VMID; vmid <= END_VMID; vmid++)); do
            vm_ids+=("$vmid")
        done
    fi

    # Local callback for bulk operation
    migrate_cloud_init_callback() {
        local vmid="$1"
        local node

        node=$(__get_vm_node__ "$vmid")

        if [[ -z "$node" ]]; then
            __update__ "VM ${vmid} not found in cluster"
            return 1
        fi

        # Get current Cloud-Init disk storage
        local current_storage
        current_storage=$(get_current_storage "$vmid" "$node")

        if [[ -z "$current_storage" ]]; then
            __update__ "VM ${vmid} does not have a Cloud-Init disk attached"
            return 1
        fi

        # Check if already on target storage
        if [[ "$current_storage" == "$TARGET_STORAGE" ]]; then
            __update__ "VM ${vmid} Cloud-Init disk already on ${TARGET_STORAGE}"
            return 0
        fi

        __update__ "Backing up Cloud-Init parameters for VM ${vmid}..."
        local ci_user ci_password ci_ipconfig ci_nameserver ci_searchdomain ci_sshkeys
        ci_user=$(qm config "$vmid" --node "$node" 2>/dev/null | grep -oP '(?<=^ciuser: ).*' || true)
        ci_password=$(qm config "$vmid" --node "$node" 2>/dev/null | grep -oP '(?<=^cipassword: ).*' || true)
        ci_ipconfig=$(qm config "$vmid" --node "$node" 2>/dev/null | grep -oP '(?<=^ipconfig0: ).*' || true)
        ci_nameserver=$(qm config "$vmid" --node "$node" 2>/dev/null | grep -oP '(?<=^nameserver: ).*' || true)
        ci_searchdomain=$(qm config "$vmid" --node "$node" 2>/dev/null | grep -oP '(?<=^searchdomain: ).*' || true)
        ci_sshkeys=$(qm config "$vmid" --node "$node" 2>/dev/null | grep -oP '(?<=^sshkeys: ).*' | sed 's/%0A/\n/g' | sed 's/%20/ /g' || true)

        if [[ -z "$ci_user" ]] && [[ -z "$ci_ipconfig" ]]; then
            __update__ "VM ${vmid} does not have Cloud-Init parameters"
            return 0
        fi

        __update__ "Deleting existing Cloud-Init disk for VM ${vmid}..."
        qm set "$vmid" --delete sata1 --node "$node" 2>/dev/null || qm set "$vmid" --delete ide2 --node "$node" 2>/dev/null || true

        # Determine which interface was used
        local ci_interface="sata1"
        if qm config "$vmid" --node "$node" 2>/dev/null | grep -q "^ide2:"; then
            ci_interface="ide2"
        fi

        __update__ "Re-creating Cloud-Init disk for VM ${vmid} on ${TARGET_STORAGE}..."
        local interface_type="${ci_interface%%[0-9]*}"
        qm set "$vmid" --"${interface_type}" "${TARGET_STORAGE}:cloudinit" --node "$node" 2>/dev/null

        __update__ "Restoring Cloud-Init parameters for VM ${vmid}..."

        # Prepare SSH keys if they exist and are valid
        local temp_ssh_file=""
        local sshkeys_option=""
        if [[ -n "$ci_sshkeys" ]] && [[ "$ci_sshkeys" =~ ^ssh-(rsa|dss|ed25519|ecdsa) ]]; then
            temp_ssh_file=$(mktemp)
            echo -e "$ci_sshkeys" >"$temp_ssh_file"
            sshkeys_option="--sshkeys ${temp_ssh_file}"
        fi

        # Apply the restored parameters
        local cmd="qm set \"$vmid\" --node \"$node\""
        [[ -n "$ci_user" ]] && cmd="$cmd --ciuser \"$ci_user\""
        [[ -n "$ci_password" ]] && cmd="$cmd --cipassword \"$ci_password\""
        [[ -n "$ci_ipconfig" ]] && cmd="$cmd --ipconfig0 \"$ci_ipconfig\""
        [[ -n "$ci_nameserver" ]] && cmd="$cmd --nameserver \"$ci_nameserver\""
        [[ -n "$ci_searchdomain" ]] && cmd="$cmd --searchdomain \"$ci_searchdomain\""
        [[ -n "$sshkeys_option" ]] && cmd="$cmd $sshkeys_option"

        local result=0
        if ! eval "$cmd" 2>/dev/null; then
            result=1
        fi

        # Clean up temporary SSH key file
        [[ -n "$temp_ssh_file" ]] && [[ -f "$temp_ssh_file" ]] && rm "$temp_ssh_file"

        return $result
    }

    # Use BulkOperations framework
    BULK_OPERATION_NAME="Cloud-Init Migration"
    for vmid in "${vm_ids[@]}"; do
        if migrate_cloud_init_callback "$vmid"; then
            ((BULK_SUCCESS += 1))
        else
            ((BULK_FAILED += 1))
            BULK_FAILED_IDS+=("$vmid")
        fi
    done

    # Display summary
    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "Cloud-Init disk migration completed successfully!"
}

main

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-11-20: Updated to use ArgumentParser and BulkOperations framework
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# -
#
# Known issues:
# -
#

