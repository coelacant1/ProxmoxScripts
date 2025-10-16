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
#   ./BulkConfigureDisk.sh <start_id> <end_id> <disk> [options]
#
# Arguments:
#   start_id  - The starting VM ID in the range to be processed
#   end_id    - The ending VM ID in the range to be processed
#   disk      - Disk identifier (e.g., scsi0, virtio0, sata0, ide0)
#
# Disk Configuration Options:
#   --cache <mode>          - Cache mode: none, writethrough, writeback, directsync, unsafe
#   --discard <on|ignore>   - Enable discard/TRIM support (on or ignore)
#   --iothread <0|1>        - Enable IO thread (0=off, 1=on) - virtio-scsi only
#   --ro <0|1>              - Read-only mode (0=read-write, 1=read-only)
#   --ssd <0|1>             - SSD emulation (0=off, 1=on)
#   --backup <0|1>          - Include in backup (0=exclude, 1=include)
#   --replicate <0|1>       - Include in replication (0=skip, 1=replicate)
#   --aio <native|threads>  - Async I/O mode (native or threads)
#
# Examples:
#   # Enable discard and SSD emulation
#   ./BulkConfigureDisk.sh 100 110 scsi0 --discard on --ssd 1
#
#   # Configure for performance with writeback cache and IO threads
#   ./BulkConfigureDisk.sh 100 110 virtio0 --cache writeback --iothread 1 --aio native
#
#   # Set disk as read-only and exclude from backups
#   ./BulkConfigureDisk.sh 100 110 scsi0 --ro 1 --backup 0
#
#   # Full performance configuration
#   ./BulkConfigureDisk.sh 400 410 scsi0 --cache writeback --discard on --iothread 1 --ssd 1 --aio native
#
#   # Exclude from backups and replication
#   ./BulkConfigureDisk.sh 100 110 scsi1 --backup 0 --replicate 0
#
# Cache Modes:
#   - none:        No caching (safest, slowest)
#   - writethrough: Cache reads, write-through writes (safe)
#   - writeback:   Cache reads and writes (fastest, less safe)
#   - directsync:  Direct I/O, no cache (safe, moderate speed)
#   - unsafe:      No flush (fastest, dangerous - data loss risk)
#
# Function Index:
#   - usage
#   - parse_args
#   - validate_options
#   - configure_disk
#   - main
#

set -u

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Global variables
START_ID=""
END_ID=""
DISK=""
CACHE=""
DISCARD=""
IOTHREAD=""
READONLY=""
SSD=""
BACKUP=""
REPLICATE=""
AIO=""

# --- usage -------------------------------------------------------------------
# @function usage
# @description Prints usage information and exits.
usage() {
    cat <<-USAGE
Usage: ${0##*/} <start_id> <end_id> <disk> [options]

Configures hard disk options for a range of VMs cluster-wide.

Arguments:
  start_id  - Starting VM ID
  end_id    - Ending VM ID
  disk      - Disk identifier (e.g., scsi0, virtio0, sata0, ide0)

Disk Options:
  --cache <mode>         - Cache mode (none, writethrough, writeback, directsync, unsafe)
  --discard <on|ignore>  - Enable discard/TRIM support
  --iothread <0|1>       - Enable IO thread (virtio-scsi only)
  --ro <0|1>             - Read-only mode (0=read-write, 1=read-only)
  --ssd <0|1>            - SSD emulation (0=off, 1=on)
  --backup <0|1>         - Include in backup (0=exclude, 1=include)
  --replicate <0|1>      - Include in replication (0=skip, 1=replicate)
  --aio <native|threads> - Async I/O mode

Cache Modes:
  none        - No caching (safest, slowest)
  writethrough- Cache reads, write-through writes (safe, default)
  writeback   - Cache reads and writes (fastest, less safe)
  directsync  - Direct I/O, no cache (safe, moderate)
  unsafe      - No flush (fastest, DANGEROUS - risk of data loss)

Examples:
  # Enable discard and SSD emulation
  ${0##*/} 100 110 scsi0 --discard on --ssd 1

  # Performance configuration
  ${0##*/} 100 110 virtio0 --cache writeback --iothread 1 --aio native

  # Read-only disk excluded from backups
  ${0##*/} 100 110 scsi0 --ro 1 --backup 0

  # Full performance optimization
  ${0##*/} 400 410 scsi0 --cache writeback --discard on --iothread 1 --ssd 1 --aio native

  # Exclude from backups and replication
  ${0##*/} 100 110 scsi1 --backup 0 --replicate 0

Notes:
  - IO threads only work with virtio-scsi controllers
  - Discard requires guest OS support
  - Writeback cache is fastest but has higher data loss risk
  - SSD emulation affects guest OS behavior (TRIM, scheduler)
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

    START_ID="$1"
    END_ID="$2"
    DISK="$3"
    shift 3

    # Validate IDs are numeric
    if ! [[ "$START_ID" =~ ^[0-9]+$ ]] || ! [[ "$END_ID" =~ ^[0-9]+$ ]]; then
        __err__ "VM IDs must be numeric"
        exit 64
    fi

    # Validate range
    if (( START_ID > END_ID )); then
        __err__ "Start ID must be less than or equal to end ID"
        exit 64
    fi

    # Validate disk identifier format
    if ! [[ "$DISK" =~ ^(ide|sata|scsi|virtio|efidisk)[0-9]+$ ]]; then
        __err__ "Invalid disk identifier format: ${DISK}"
        __err__ "Use format: ide0, sata0, scsi0, virtio0, etc."
        exit 64
    fi

    # Parse optional arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cache)
                CACHE="$2"
                shift 2
                ;;
            --discard)
                DISCARD="$2"
                shift 2
                ;;
            --iothread)
                IOTHREAD="$2"
                shift 2
                ;;
            --ro)
                READONLY="$2"
                shift 2
                ;;
            --ssd)
                SSD="$2"
                shift 2
                ;;
            --backup)
                BACKUP="$2"
                shift 2
                ;;
            --replicate)
                REPLICATE="$2"
                shift 2
                ;;
            --aio)
                AIO="$2"
                shift 2
                ;;
            *)
                __err__ "Unknown option: $1"
                usage
                exit 64
                ;;
        esac
    done

    # Check that at least one option is specified
    if [[ -z "$CACHE" && -z "$DISCARD" && -z "$IOTHREAD" && -z "$READONLY" && \
          -z "$SSD" && -z "$BACKUP" && -z "$REPLICATE" && -z "$AIO" ]]; then
        __err__ "At least one disk option must be specified"
        usage
        exit 64
    fi
}

# --- validate_options --------------------------------------------------------
# @function validate_options
# @description Validates disk configuration options.
validate_options() {
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

    # Validate iothread setting
    if [[ -n "$IOTHREAD" && ! "$IOTHREAD" =~ ^[01]$ ]]; then
        __err__ "IO thread must be 0 or 1"
        exit 64
    fi

    # Warn about iothread with non-virtio disks
    if [[ -n "$IOTHREAD" && "$IOTHREAD" == "1" && ! "$DISK" =~ ^(scsi|virtio) ]]; then
        __warn__ "IO threads only work with SCSI or VirtIO disks"
    fi

    # Validate read-only setting
    if [[ -n "$READONLY" && ! "$READONLY" =~ ^[01]$ ]]; then
        __err__ "Read-only must be 0 or 1"
        exit 64
    fi

    # Validate SSD setting
    if [[ -n "$SSD" && ! "$SSD" =~ ^[01]$ ]]; then
        __err__ "SSD must be 0 or 1"
        exit 64
    fi

    # Validate backup setting
    if [[ -n "$BACKUP" && ! "$BACKUP" =~ ^[01]$ ]]; then
        __err__ "Backup must be 0 or 1"
        exit 64
    fi

    # Validate replicate setting
    if [[ -n "$REPLICATE" && ! "$REPLICATE" =~ ^[01]$ ]]; then
        __err__ "Replicate must be 0 or 1"
        exit 64
    fi

    # Validate AIO mode
    if [[ -n "$AIO" ]]; then
        if [[ "$AIO" != "native" && "$AIO" != "threads" ]]; then
            __err__ "AIO must be 'native' or 'threads'"
            exit 64
        fi
    fi
}

# --- configure_disk ----------------------------------------------------------
# @function configure_disk
# @description Configures disk options for a VM.
# @param 1 VM ID
configure_disk() {
    local vmid="$1"
    local node
    
    node=$(__get_vm_node__ "$vmid")
    
    if [[ -z "$node" ]]; then
        __update__ "VM ${vmid} not found in cluster, skipping"
        return 0
    fi
    
    __update__ "Configuring disk ${DISK} for VM ${vmid} on node ${node}..."
    
    # Get current disk configuration
    local current_config
    current_config=$(qm config "$vmid" --node "$node" 2>/dev/null | grep "^${DISK}:" || true)
    
    if [[ -z "$current_config" ]]; then
        __warn__ "Disk ${DISK} not found on VM ${vmid}, skipping"
        return 0
    fi
    
    # Extract the storage path/volume (everything before the first comma or the whole string)
    local disk_volume
    disk_volume=$(echo "$current_config" | sed 's/^[^:]*: *//' | sed 's/,.*//')
    
    # Build disk configuration string
    local disk_config="${disk_volume}"
    
    # Parse and preserve existing options, then apply new ones
    local existing_options
    existing_options=$(echo "$current_config" | sed 's/^[^:]*:[^,]*,*//')
    
    # Function to get existing option value
    get_existing_option() {
        local opt="$1"
        echo "$existing_options" | grep -oP "${opt}=\K[^,]+" || true
    }
    
    # Build options string, using new values or preserving existing ones
    
    # Cache
    if [[ -n "$CACHE" ]]; then
        disk_config+=",cache=${CACHE}"
    else
        local existing_cache=$(get_existing_option "cache")
        [[ -n "$existing_cache" ]] && disk_config+=",cache=${existing_cache}"
    fi
    
    # Discard
    if [[ -n "$DISCARD" ]]; then
        disk_config+=",discard=${DISCARD}"
    else
        local existing_discard=$(get_existing_option "discard")
        [[ -n "$existing_discard" ]] && disk_config+=",discard=${existing_discard}"
    fi
    
    # IO Thread
    if [[ -n "$IOTHREAD" ]]; then
        disk_config+=",iothread=${IOTHREAD}"
    else
        local existing_iothread=$(get_existing_option "iothread")
        [[ -n "$existing_iothread" ]] && disk_config+=",iothread=${existing_iothread}"
    fi
    
    # Read-only
    if [[ -n "$READONLY" ]]; then
        disk_config+=",ro=${READONLY}"
    else
        local existing_ro=$(get_existing_option "ro")
        [[ -n "$existing_ro" ]] && disk_config+=",ro=${existing_ro}"
    fi
    
    # SSD
    if [[ -n "$SSD" ]]; then
        disk_config+=",ssd=${SSD}"
    else
        local existing_ssd=$(get_existing_option "ssd")
        [[ -n "$existing_ssd" ]] && disk_config+=",ssd=${existing_ssd}"
    fi
    
    # Backup
    if [[ -n "$BACKUP" ]]; then
        disk_config+=",backup=${BACKUP}"
    else
        local existing_backup=$(get_existing_option "backup")
        [[ -n "$existing_backup" ]] && disk_config+=",backup=${existing_backup}"
    fi
    
    # Replicate
    if [[ -n "$REPLICATE" ]]; then
        disk_config+=",replicate=${REPLICATE}"
    else
        local existing_replicate=$(get_existing_option "replicate")
        [[ -n "$existing_replicate" ]] && disk_config+=",replicate=${existing_replicate}"
    fi
    
    # AIO
    if [[ -n "$AIO" ]]; then
        disk_config+=",aio=${AIO}"
    else
        local existing_aio=$(get_existing_option "aio")
        [[ -n "$existing_aio" ]] && disk_config+=",aio=${existing_aio}"
    fi
    
    # Preserve other existing options that we don't manage
    local other_options=$(echo "$existing_options" | grep -oP '(size|format|media|snapshot|mbps|mbps_rd|mbps_wr|iops|iops_rd|iops_wr)=[^,]+' || true)
    if [[ -n "$other_options" ]]; then
        while IFS= read -r opt; do
            [[ -n "$opt" ]] && disk_config+=",${opt}"
        done <<< "$other_options"
    fi
    
    # Execute configuration
    local cmd="qm set \"$vmid\" --node \"$node\" --${DISK} \"${disk_config}\""
    
    if eval "$cmd" 2>&1; then
        __ok__ "Disk ${DISK} configured for VM ${vmid} on ${node}"
        __info__ "  Config: ${disk_config}"
        return 0
    else
        __err__ "Failed to configure disk ${DISK} for VM ${vmid}"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
# @function main
# @description Main script logic - iterates through VM range and configures disks.
main() {
    __check_root__
    __check_proxmox__
    
    # Validate options
    validate_options
    
    __info__ "Bulk configure disk: VMs ${START_ID} to ${END_ID} (cluster-wide)"
    __info__ "Disk: ${DISK}"
    [[ -n "$CACHE" ]] && __info__ "  Cache: ${CACHE}"
    [[ -n "$DISCARD" ]] && __info__ "  Discard: ${DISCARD}"
    [[ -n "$IOTHREAD" ]] && __info__ "  IO Thread: ${IOTHREAD}"
    [[ -n "$READONLY" ]] && __info__ "  Read-Only: ${READONLY}"
    [[ -n "$SSD" ]] && __info__ "  SSD Emulation: ${SSD}"
    [[ -n "$BACKUP" ]] && __info__ "  Backup: ${BACKUP}"
    [[ -n "$REPLICATE" ]] && __info__ "  Replicate: ${REPLICATE}"
    [[ -n "$AIO" ]] && __info__ "  Async I/O: ${AIO}"
    
    # Special warning for dangerous settings
    if [[ "$CACHE" == "unsafe" ]]; then
        __warn__ "WARNING: Using 'unsafe' cache mode!"
        __warn__ "This can cause DATA LOSS on host crash or power failure!"
    fi
    
    if [[ "$READONLY" == "1" ]]; then
        __warn__ "Setting disk to READ-ONLY mode"
    fi
    
    # Confirm action
    if ! __prompt_user_yn__ "Configure disk ${DISK} for VMs ${START_ID}-${END_ID}?"; then
        __info__ "Operation cancelled by user"
        exit 0
    fi
    
    # Configure disks for VMs in the specified range
    local failed_count=0
    local processed_count=0
    
    for (( vmid=START_ID; vmid<=END_ID; vmid++ )); do
        if configure_disk "$vmid"; then
            ((processed_count++))
        else
            ((failed_count++))
        fi
    done
    
    echo
    __info__ "Operation complete:"
    __info__ "  Processed: ${processed_count}"
    if (( failed_count > 0 )); then
        __warn__ "  Failed: ${failed_count}"
    fi
    
    if (( failed_count > 0 )); then
        __err__ "Configuration completed with ${failed_count} failure(s)"
        exit 1
    else
        __ok__ "All disk configurations completed successfully"
    fi
}

parse_args "$@"
main

# Testing status:
#   - 2025-10-16: Created comprehensive disk configuration script
