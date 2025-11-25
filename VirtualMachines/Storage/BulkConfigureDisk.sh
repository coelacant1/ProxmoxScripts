#!/bin/bash
#
# BulkConfigureDisk.sh
#
# Configures hard disk options for a range of virtual machines (VMs) on a Proxmox VE cluster.
# Supports comprehensive disk configuration including cache mode, discard, IO thread, read-only,
# SSD emulation, backup inclusion, replication settings, and async I/O.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   BulkConfigureDisk.sh 100 110 scsi0 --discard on --ssd 1
#   BulkConfigureDisk.sh 100 110 virtio0 --cache writeback --iothread 1 --aio native
#   BulkConfigureDisk.sh 100 110 scsi0 --ro 1 --backup 0
#   BulkConfigureDisk.sh 400 410 scsi0 --cache writeback --discard on --iothread 1 --ssd 1 --aio native
#   BulkConfigureDisk.sh 100 110 scsi1 --backup 0 --replicate 0
#
# Arguments:
#   start_id               - Starting VM ID in the range
#   end_id                 - Ending VM ID in the range
#   disk                   - Disk identifier (e.g., scsi0, virtio0, sata0, ide0)
#   --cache <mode>         - Cache mode: none, writethrough, writeback, directsync, unsafe
#   --discard <on|ignore>  - Enable discard/TRIM support (on or ignore)
#   --iothread <0|1>       - Enable IO thread (0=off, 1=on) - virtio-scsi only
#   --ro <0|1>             - Read-only mode (0=read-write, 1=read-only)
#   --ssd <0|1>            - SSD emulation (0=off, 1=on)
#   --backup <0|1>         - Include in backup (0=exclude, 1=include)
#   --replicate <0|1>      - Include in replication (0=skip, 1=replicate)
#   --aio <native|threads> - Async I/O mode (native or threads)
#
# Cache Modes: none (safest), writethrough (safe), writeback (fast), directsync, unsafe (dangerous)
#
# Notes:
#   - At least one disk option must be specified
#   - IO threads only work with virtio-scsi controllers
#   - Discard requires guest OS support
#   - Writeback cache is fastest but has higher data loss risk
#
# Function Index:
#   - validate_custom_options
#   - get_existing_option
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/BulkOperations.sh
source "${UTILITYPATH}/BulkOperations.sh"
# shellcheck source=Utilities/Cluster.sh
source "${UTILITYPATH}/Cluster.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- validate_custom_options -------------------------------------------------
# @function validate_custom_options
# @description Validates disk-specific configuration options not covered by ArgumentParser.
validate_custom_options() {
    # Validate disk identifier format
    if ! [[ "$DISK" =~ ^(ide|sata|scsi|virtio|efidisk)[0-9]+$ ]]; then
        __err__ "Invalid disk identifier format: ${DISK}"
        __err__ "Use format: ide0, sata0, scsi0, virtio0, etc."
        exit 64
    fi

    # Check that at least one disk option is specified
    if [[ -z "$CACHE" && -z "$DISCARD" && -z "$IOTHREAD" && -z "$RO" &&
        -z "$SSD" && -z "$BACKUP" && -z "$REPLICATE" && -z "$AIO" ]]; then
        __err__ "At least one disk option must be specified"
        exit 64
    fi

    # Validate cache mode
    if [[ -n "$CACHE" ]]; then
        local valid_cache="none writethrough writeback directsync unsafe"
        if ! echo "$valid_cache" | grep -qw "$CACHE"; then
            __err__ "Invalid cache mode: ${CACHE}"
            __err__ "Valid modes: ${valid_cache}"
            exit 64
        fi

        if [[ "$CACHE" == "unsafe" ]]; then
            __warn__ "WARNING: 'unsafe' cache mode can cause data loss!"
        fi
    fi

    # Validate discard setting
    if [[ -n "$DISCARD" ]]; then
        if [[ "$DISCARD" != "on" && "$DISCARD" != "ignore" ]]; then
            __err__ "Discard must be 'on' or 'ignore'"
            exit 64
        fi
    fi

    # Warn about iothread with non-virtio disks
    if [[ -n "$IOTHREAD" && "$IOTHREAD" == "1" && ! "$DISK" =~ ^(scsi|virtio) ]]; then
        __warn__ "IO threads only work with SCSI or VirtIO disks"
    fi

    # Validate AIO mode
    if [[ -n "$AIO" ]]; then
        if [[ "$AIO" != "native" && "$AIO" != "threads" ]]; then
            __err__ "AIO must be 'native' or 'threads'"
            exit 64
        fi
    fi
}

# --- get_existing_option -----------------------------------------------------
# @function get_existing_option
# @description Extracts a specific option value from disk configuration string.
# @param 1 Existing disk options string
# @param 2 Option name to extract
# @return Option value
get_existing_option() {
    local existing_options="$1"
    local opt="$2"
    echo "$existing_options" | grep -oP "${opt}=\K[^,]+" || true
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    # Parse arguments using ArgumentParser
    __parse_args__ "start_id:vmid end_id:vmid disk:string --cache:string:? --discard:string:? --iothread:boolean:? --ro:boolean:? --ssd:boolean:? --backup:boolean:? --replicate:boolean:? --aio:string:?" "$@"

    # Additional custom validation
    validate_custom_options

    __info__ "Bulk configure disk: VMs ${START_ID} to ${END_ID} (cluster-wide)"
    __info__ "Disk: ${DISK}"
    [[ -n "$CACHE" ]] && __info__ "  Cache: ${CACHE}"
    [[ -n "$DISCARD" ]] && __info__ "  Discard: ${DISCARD}"
    [[ -n "$IOTHREAD" ]] && __info__ "  IO Thread: ${IOTHREAD}"
    [[ -n "$RO" ]] && __info__ "  Read-Only: ${RO}"
    [[ -n "$SSD" ]] && __info__ "  SSD Emulation: ${SSD}"
    [[ -n "$BACKUP" ]] && __info__ "  Backup: ${BACKUP}"
    [[ -n "$REPLICATE" ]] && __info__ "  Replicate: ${REPLICATE}"
    [[ -n "$AIO" ]] && __info__ "  AIO: ${AIO}"

    # Confirm action
    if ! __prompt_user_yn__ "Configure disk ${DISK} for VMs ${START_ID}-${END_ID}?"; then
        __info__ "Operation cancelled by user"
        exit 0
    fi

    # Local callback for bulk operation
    configure_disk_callback() {
        local vmid="$1"
        local node

        node=$(__get_vm_node__ "$vmid")

        if [[ -z "$node" ]]; then
            __update__ "VM ${vmid} not found in cluster"
            return 1
        fi

        __update__ "Configuring disk ${DISK} for VM ${vmid} on node ${node}..."

        # Get current disk configuration
        local current_config
        current_config=$(qm config "$vmid" --node "$node" 2>/dev/null | grep "^${DISK}:" | cut -d' ' -f2- || echo "")

        if [[ -z "$current_config" ]]; then
            __update__ "VM ${vmid} has no ${DISK} disk"
            return 1
        fi

        # Build new configuration by modifying existing options
        local new_config="$current_config"

        # Update cache mode
        if [[ -n "$CACHE" ]]; then
            if echo "$new_config" | grep -q "cache="; then
                new_config=$(echo "$new_config" | sed "s/cache=[^,]*/cache=${CACHE}/")
            else
                new_config="${new_config},cache=${CACHE}"
            fi
        fi

        # Update discard
        if [[ -n "$DISCARD" ]]; then
            if echo "$new_config" | grep -q "discard="; then
                new_config=$(echo "$new_config" | sed "s/discard=[^,]*/discard=${DISCARD}/")
            else
                new_config="${new_config},discard=${DISCARD}"
            fi
        fi

        # Update iothread
        if [[ -n "$IOTHREAD" ]]; then
            if echo "$new_config" | grep -q "iothread="; then
                new_config=$(echo "$new_config" | sed "s/iothread=[^,]*/iothread=${IOTHREAD}/")
            else
                new_config="${new_config},iothread=${IOTHREAD}"
            fi
        fi

        # Update read-only
        if [[ -n "$RO" ]]; then
            if echo "$new_config" | grep -q "ro="; then
                new_config=$(echo "$new_config" | sed "s/ro=[^,]*/ro=${RO}/")
            else
                new_config="${new_config},ro=${RO}"
            fi
        fi

        # Update SSD emulation
        if [[ -n "$SSD" ]]; then
            if echo "$new_config" | grep -q "ssd="; then
                new_config=$(echo "$new_config" | sed "s/ssd=[^,]*/ssd=${SSD}/")
            else
                new_config="${new_config},ssd=${SSD}"
            fi
        fi

        # Update backup setting
        if [[ -n "$BACKUP" ]]; then
            if echo "$new_config" | grep -q "backup="; then
                new_config=$(echo "$new_config" | sed "s/backup=[^,]*/backup=${BACKUP}/")
            else
                new_config="${new_config},backup=${BACKUP}"
            fi
        fi

        # Update replicate setting
        if [[ -n "$REPLICATE" ]]; then
            if echo "$new_config" | grep -q "replicate="; then
                new_config=$(echo "$new_config" | sed "s/replicate=[^,]*/replicate=${REPLICATE}/")
            else
                new_config="${new_config},replicate=${REPLICATE}"
            fi
        fi

        # Update AIO mode
        if [[ -n "$AIO" ]]; then
            if echo "$new_config" | grep -q "aio="; then
                new_config=$(echo "$new_config" | sed "s/aio=[^,]*/aio=${AIO}/")
            else
                new_config="${new_config},aio=${AIO}"
            fi
        fi

        # Apply configuration
        if qm set "$vmid" --node "$node" "--${DISK}" "$new_config" 2>&1; then
            return 0
        else
            return 1
        fi
    }

    # Use BulkOperations framework
    __bulk_vm_operation__ --name "Disk Configuration" --report "$START_ID" "$END_ID" configure_disk_callback

    # Display summary
    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "All disk configurations completed successfully!"
}

main "$@"

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-11-04: Refactored to use ArgumentParser.sh declarative parsing
# - 2025-11-20: Removed manual usage() and parse_args() functions
# - 2025-11-20: Now uses __parse_args__ with automatic validation
# - 2025-11-20: Fixed __prompt_yes_no__ -> __prompt_user_yn__
# - 2025-11-20: Added missing Cluster.sh source for __get_vm_node__
#
# Fixes:
# - Fixed __prompt_yes_no__ -> __prompt_user_yn__
#
# Known issues:
# -
#

