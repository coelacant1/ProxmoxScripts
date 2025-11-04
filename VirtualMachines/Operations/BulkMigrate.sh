#!/bin/bash
#
# BulkMigrate.sh
#
# Migrates virtual machines within a Proxmox VE cluster to a specified target node.
# Supports migration by VM ID range, resource pool, or all local VMs.
#
# Usage:
#   BulkMigrate.sh --range <start_vmid> <end_vmid> --target <node>
#   BulkMigrate.sh --pool <pool_name> --target <node>
#   BulkMigrate.sh --local --target <node>
#
# Arguments:
#   --range <start> <end> - Migrate VMs in specified ID range
#   --pool <pool_name>    - Migrate all VMs in resource pool
#   --local               - Migrate all VMs on local node
#   --target <node>       - Target node for migration
#   --offline             - Force offline migration (default: online)
#   --storage <storage>   - Target storage (default: same as source)
#
# Examples:
#   BulkMigrate.sh --range 400 430 --target pve02
#   BulkMigrate.sh --pool production --target pve03 --offline
#
# Function Index:
#   - main
#   - migrate_callback
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/ProxmoxAPI.sh
source "${UTILITYPATH}/ProxmoxAPI.sh"
# shellcheck source=Utilities/BulkOperations.sh
source "${UTILITYPATH}/BulkOperations.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
__parse_args__ "--range:flag start_vmid?:vmid end_vmid?:vmid --pool:flag pool_name?:string --local:flag --target:string --offline:flag --storage?:string" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    # Validate mode selection
    local mode_count=0
    [[ "$RANGE" == "true" ]] && ((mode_count++))
    [[ "$POOL" == "true" ]] && ((mode_count++))
    [[ "$LOCAL" == "true" ]] && ((mode_count++))

    if (( mode_count == 0 )); then
        __err__ "Mode not specified. Use --range, --pool, or --local"
        exit 64
    elif (( mode_count > 1 )); then
        __err__ "Multiple modes specified. Use only one of: --range, --pool, --local"
        exit 64
    fi

    # Validate range mode
    if [[ "$RANGE" == "true" ]] && { [[ -z "$START_VMID" ]] || [[ -z "$END_VMID" ]]; }; then
        __err__ "--range requires <start_vmid> and <end_vmid>"
        exit 64
    fi

    # Validate pool mode
    if [[ "$POOL" == "true" ]] && [[ -z "$POOL_NAME" ]]; then
        __err__ "--pool requires <pool_name>"
        exit 64
    fi

    # Set migration type
    local migration_type="online"
    [[ "$OFFLINE" == "true" ]] && migration_type="offline"

    # Display operation info
    __info__ "Target node: ${TARGET}"
    __info__ "Migration type: ${migration_type}"
    [[ -n "${STORAGE:-}" ]] && __info__ "Target storage: ${STORAGE}"

    # Get VM list based on mode
    local -a vm_list=()
    if [[ "$RANGE" == "true" ]]; then
        __info__ "Mode: Range (${START_VMID}-${END_VMID})"
        for (( vmid=START_VMID; vmid<=END_VMID; vmid++ )); do
            vm_list+=("$vmid")
        done
    elif [[ "$POOL" == "true" ]]; then
        __info__ "Mode: Pool (${POOL_NAME})"
        readarray -t vm_list < <(__get_pool_vms__ "$POOL_NAME")
        if [[ ${#vm_list[@]} -eq 0 ]]; then
            __err__ "No VMs found in pool '${POOL_NAME}'"
            exit 1
        fi
    elif [[ "$LOCAL" == "true" ]]; then
        __info__ "Mode: Local node"
        readarray -t vm_list < <(__get_server_vms__ "local")
        if [[ ${#vm_list[@]} -eq 0 ]]; then
            __err__ "No VMs found on local node"
            exit 1
        fi
    fi

    __info__ "VMs to process: ${#vm_list[@]}"

    if ! __prompt_user_yn__ "Proceed with migration?"; then
        __info__ "Migration cancelled by user"
        exit 0
    fi

    # Local callback for migration operation
    migrate_callback() {
        local vmid="$1"
        local source_node

        source_node=$(__get_vm_node__ "$vmid")

        if [[ "$source_node" == "$TARGET" ]]; then
            return 2  # Skip: already on target
        fi

        local migrate_cmd="qm migrate {vmid} ${TARGET}"
        [[ "$migration_type" == "online" ]] && migrate_cmd="${migrate_cmd} --online"
        [[ -n "${STORAGE:-}" ]] && migrate_cmd="${migrate_cmd} --targetstorage ${STORAGE}"

        __vm_node_exec__ "$vmid" "$migrate_cmd"
    }

    # Use BulkOperations framework
    __bulk_vm_operation__ --name "Migrate VMs" --report --list "${vm_list[@]}" -- migrate_callback

    # Display summary
    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "Migration completed successfully!"
}

main

# Testing status:
#   - 2025-10-28: Updated to follow contributing guidelines with BulkOperations framework
