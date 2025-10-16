#!/bin/bash
#
# BulkMigrate.sh
#
# Migrates virtual machines (VMs) within a Proxmox VE cluster from their current nodes
# to a specified target node. Supports migration by VM ID range, resource pool, or all
# local VMs. Performs online migration when possible.
#
# Usage:
#   ./BulkMigrate.sh --range <first_vm_id> <last_vm_id> --target <target_node>
#   ./BulkMigrate.sh --pool <pool_name> --target <target_node>
#   ./BulkMigrate.sh --local --target <target_node>
#
# Arguments:
#   --range <first> <last>  - Migrate VMs in the specified ID range
#   --pool <pool_name>      - Migrate all VMs in the specified resource pool
#   --local                 - Migrate all VMs on the local node
#   --target <node>         - Target node (hostname or IP) for migration
#   --offline               - Optional. Force offline migration (default: online)
#   --storage <storage>     - Optional. Target storage (default: same as source)
#
# Examples:
#   ./BulkMigrate.sh --range 400 430 --target pve02
#   ./BulkMigrate.sh --pool production --target pve03
#   ./BulkMigrate.sh --local --target pve01
#   ./BulkMigrate.sh --range 400 410 --target pve02 --offline --storage local-zfs
#
# Function Index:
#   - usage
#   - parse_args
#   - get_vm_list_from_range
#   - get_vm_list_from_pool
#   - get_vm_list_from_local
#   - migrate_vm
#   - main
#

set -u

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Global variables
MODE=""
FIRST_VM_ID=""
LAST_VM_ID=""
POOL_NAME=""
TARGET_NODE=""
MIGRATION_TYPE="online"
TARGET_STORAGE=""

# --- usage -------------------------------------------------------------------
usage() {
    cat <<-USAGE
Usage: ${0##*/} <mode> --target <target_node> [options]

Migrates VMs within the cluster to a specified target node.

Modes:
  --range <first> <last>  Migrate VMs in the specified ID range
  --pool <pool_name>      Migrate all VMs in the specified resource pool
  --local                 Migrate all VMs on the local node

Required:
  --target <node>         Target node (hostname or IP)

Options:
  --offline               Force offline migration (default: online)
  --storage <storage>     Target storage (default: same as source)
  -h, --help              Show this help message

Examples:
  ${0##*/} --range 400 430 --target pve02
  ${0##*/} --pool production --target pve03
  ${0##*/} --local --target pve01
  ${0##*/} --range 400 410 --target pve02 --offline --storage local-zfs

Notes:
  - VMs are automatically detected on their current nodes
  - Online migration is attempted by default
  - VMs already on target node are skipped
  - Migration preserves VM configuration and disk data
USAGE
}

# --- parse_args --------------------------------------------------------------
parse_args() {
    if [[ $# -eq 0 ]]; then
        __err__ "No arguments provided"
        usage
        exit 64
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --range)
                if [[ -n "$MODE" ]]; then
                    __err__ "Multiple modes specified. Use only one of: --range, --pool, --local"
                    exit 64
                fi
                MODE="range"
                shift
                if [[ $# -lt 2 ]]; then
                    __err__ "--range requires two arguments: <first_vm_id> <last_vm_id>"
                    exit 64
                fi
                FIRST_VM_ID="$1"
                LAST_VM_ID="$2"
                shift 2
                ;;
            --pool)
                if [[ -n "$MODE" ]]; then
                    __err__ "Multiple modes specified. Use only one of: --range, --pool, --local"
                    exit 64
                fi
                MODE="pool"
                shift
                if [[ $# -lt 1 ]]; then
                    __err__ "--pool requires an argument: <pool_name>"
                    exit 64
                fi
                POOL_NAME="$1"
                shift
                ;;
            --local)
                if [[ -n "$MODE" ]]; then
                    __err__ "Multiple modes specified. Use only one of: --range, --pool, --local"
                    exit 64
                fi
                MODE="local"
                shift
                ;;
            --target)
                shift
                if [[ $# -lt 1 ]]; then
                    __err__ "--target requires an argument: <target_node>"
                    exit 64
                fi
                TARGET_NODE="$1"
                shift
                ;;
            --offline)
                MIGRATION_TYPE="offline"
                shift
                ;;
            --storage)
                shift
                if [[ $# -lt 1 ]]; then
                    __err__ "--storage requires an argument: <storage_name>"
                    exit 64
                fi
                TARGET_STORAGE="$1"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                __err__ "Unknown argument: $1"
                usage
                exit 64
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "$MODE" ]]; then
        __err__ "Mode not specified. Use --range, --pool, or --local"
        usage
        exit 64
    fi

    if [[ -z "$TARGET_NODE" ]]; then
        __err__ "--target is required"
        usage
        exit 64
    fi

    # Validate range mode parameters
    if [[ "$MODE" == "range" ]]; then
        if ! [[ "$FIRST_VM_ID" =~ ^[0-9]+$ ]] || ! [[ "$LAST_VM_ID" =~ ^[0-9]+$ ]]; then
            __err__ "VM IDs must be numeric"
            exit 64
        fi
        
        if (( FIRST_VM_ID > LAST_VM_ID )); then
            __err__ "First VM ID must be less than or equal to last VM ID"
            exit 64
        fi
    fi

    # Resolve target node name
    if [[ "$TARGET_NODE" == "local" ]]; then
        TARGET_NODE="$(hostname -s)"
    elif [[ "$TARGET_NODE" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        local resolved_name
        resolved_name="$(__get_name_from_ip__ "$TARGET_NODE")"
        if [[ -z "$resolved_name" ]]; then
            __err__ "Unable to resolve node name from IP: ${TARGET_NODE}"
            exit 1
        fi
        TARGET_NODE="$resolved_name"
    fi
}

# --- get_vm_list_from_range --------------------------------------------------
get_vm_list_from_range() {
    local -a vm_list=()
    
    for (( vmid=FIRST_VM_ID; vmid<=LAST_VM_ID; vmid++ )); do
        vm_list+=("$vmid")
    done
    
    printf '%s\n' "${vm_list[@]}"
}

# --- get_vm_list_from_pool ---------------------------------------------------
get_vm_list_from_pool() {
    __install_or_prompt__ "jq"
    
    __info__ "Retrieving VMs from pool: ${POOL_NAME}"
    
    # Query cluster resources and filter by pool
    local vm_list
    vm_list=$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null | \
        jq -r --arg POOL "$POOL_NAME" '.[] | select(.type=="qemu" and .pool==$POOL) | .vmid' 2>/dev/null)
    
    if [[ -z "$vm_list" ]]; then
        __err__ "No VMs found in pool '${POOL_NAME}' or pool does not exist"
        return 1
    fi
    
    echo "$vm_list"
}

# --- get_vm_list_from_local --------------------------------------------------
get_vm_list_from_local() {
    local local_node
    local_node="$(hostname -s)"
    
    __info__ "Retrieving VMs from local node: ${local_node}"
    
    # Get all VMs on the local node
    local vm_list
    vm_list=$(__get_server_vms__ "local")
    
    if [[ -z "$vm_list" ]]; then
        __err__ "No VMs found on local node '${local_node}'"
        return 1
    fi
    
    echo "$vm_list"
}

# --- migrate_vm --------------------------------------------------------------
migrate_vm() {
    local vmid="$1"
    local source_node
    
    # Get current node for this VM
    source_node=$(__get_vm_node__ "$vmid")
    
    if [[ -z "$source_node" ]]; then
        __update__ "VM ${vmid} not found in cluster, skipping"
        return 0
    fi
    
    # Check if already on target node
    if [[ "$source_node" == "$TARGET_NODE" ]]; then
        __update__ "VM ${vmid} already on target node ${TARGET_NODE}, skipping"
        return 0
    fi
    
    __update__ "Migrating VM ${vmid} from ${source_node} to ${TARGET_NODE}..."
    
    # Build migration command
    local migrate_cmd="qm migrate ${vmid} ${TARGET_NODE}"
    
    # Add migration type
    if [[ "$MIGRATION_TYPE" == "online" ]]; then
        migrate_cmd="${migrate_cmd} --online"
    fi
    
    # Add target storage if specified
    if [[ -n "$TARGET_STORAGE" ]]; then
        migrate_cmd="${migrate_cmd} --targetstorage ${TARGET_STORAGE}"
    fi
    
    # Execute migration
    if eval "$migrate_cmd" 2>/dev/null; then
        __ok__ "VM ${vmid} migrated successfully from ${source_node} to ${TARGET_NODE}"
        return 0
    else
        __err__ "Failed to migrate VM ${vmid} from ${source_node}"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    
    # Display operation summary
    case "$MODE" in
        range)
            __info__ "Bulk migrate (range): VMs ${FIRST_VM_ID} to ${LAST_VM_ID}"
            ;;
        pool)
            __info__ "Bulk migrate (pool): All VMs in pool '${POOL_NAME}'"
            ;;
        local)
            __info__ "Bulk migrate (local): All VMs on local node"
            ;;
    esac
    
    __info__ "Target node: ${TARGET_NODE}"
    __info__ "Migration type: ${MIGRATION_TYPE}"
    [[ -n "$TARGET_STORAGE" ]] && __info__ "Target storage: ${TARGET_STORAGE}"
    
    # Get list of VMs to migrate
    local -a vm_list=()
    case "$MODE" in
        range)
            readarray -t vm_list < <(get_vm_list_from_range)
            ;;
        pool)
            readarray -t vm_list < <(get_vm_list_from_pool)
            if [[ ${#vm_list[@]} -eq 0 ]]; then
                exit 1
            fi
            ;;
        local)
            readarray -t vm_list < <(get_vm_list_from_local)
            if [[ ${#vm_list[@]} -eq 0 ]]; then
                exit 1
            fi
            ;;
    esac
    
    __info__ "VMs to process: ${#vm_list[@]}"
    
    # Confirm before proceeding
    if ! __prompt_user_yn__ "Proceed with migration?"; then
        __info__ "Migration cancelled by user"
        exit 0
    fi
    
    # Migrate each VM
    local failed_count=0
    local skipped_count=0
    local migrated_count=0
    
    for vmid in "${vm_list[@]}"; do
        # Get source node to determine if skip or migrate
        local source_node
        source_node=$(__get_vm_node__ "$vmid")
        
        if [[ -z "$source_node" ]]; then
            ((skipped_count++))
            continue
        fi
        
        if [[ "$source_node" == "$TARGET_NODE" ]]; then
            ((skipped_count++))
            continue
        fi
        
        if migrate_vm "$vmid"; then
            ((migrated_count++))
        else
            ((failed_count++))
        fi
    done
    
    # Summary
    __info__ "Migration summary:"
    __info__ "  Migrated: ${migrated_count}"
    __info__ "  Skipped: ${skipped_count}"
    __info__ "  Failed: ${failed_count}"
    
    if (( failed_count > 0 )); then
        __err__ "Migration completed with ${failed_count} failure(s)"
        exit 1
    else
        __ok__ "All migrations completed successfully"
    fi
}

parse_args "$@"
main

# Testing status:
#   - 2025-10-14: Created with range, pool, and local modes
