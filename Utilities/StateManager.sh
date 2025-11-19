#!/bin/bash
#
# StateManager.sh
#
# State management framework for saving, restoring, and comparing VM/CT states.
# Enables configuration snapshots, state tracking, and rollback capabilities.
#
# Usage:
#   source "${UTILITYPATH}/StateManager.sh"
#
# Features:
#   - Save VM/CT configurations to JSON
#   - Restore configurations from snapshots
#   - Compare states and detect changes
#   - Track configuration history
#   - Support rollback operations
#   - Bulk state operations
#
# Function Index:
#   - __state_log__
#   - __state_save_vm__
#   - __state_restore_vm__
#   - __state_compare_vm__
#   - __state_export_vm__
#   - __state_save_ct__
#   - __state_restore_ct__
#   - __state_compare_ct__
#   - __state_export_ct__
#   - __state_save_bulk__
#   - __state_restore_bulk__
#   - __state_snapshot_cluster__
#   - __state_list__
#   - __state_info__
#   - __state_delete__
#   - __state_cleanup__
#   - __state_diff__
#   - __state_show_changes__
#   - __state_validate__
#

# Source Logger for structured logging
if [[ -n "${UTILITYPATH:-}" && -f "${UTILITYPATH}/Logger.sh" ]]; then
    # shellcheck source=Utilities/Logger.sh
    source "${UTILITYPATH}/Logger.sh"
fi

# Safe logging wrapper
__state_log__() {
    local level="$1"
    local message="$2"
    if declare -f __log__ >/dev/null 2>&1; then
        __log__ "$level" "$message" "STATE"
    fi
}

# Source dependencies
source "${UTILITYPATH}/Operations.sh"
source "${UTILITYPATH}/Communication.sh"

# Default state directory
STATE_DIR="${STATE_DIR:-/var/lib/proxmox-states}"

# Ensure state directory exists
mkdir -p "$STATE_DIR" 2>/dev/null

###############################################################################
# VM State Management
###############################################################################

# --- __state_save_vm__ -------------------------------------------------------
# @function __state_save_vm__
# @description Save VM configuration to state file.
# @usage __state_save_vm__ <vmid> [state_name]
# @param 1 VMID
# @param 2 State name (default: timestamp)
# @return 0 on success, 1 on error
#
# State file format: JSON with metadata and configuration
__state_save_vm__() {
    __state_log__ "DEBUG" "__state_save_vm__: Function called with $# arguments"
    local vmid="$1"
    local state_name="${2:-$(date +%Y%m%d_%H%M%S)}"

    __state_log__ "INFO" "Saving state for VM $vmid as '$state_name'"
    __state_log__ "DEBUG" "__state_save_vm__: vmid=$vmid, state_name=$state_name"

    # Validate VM exists
    __state_log__ "DEBUG" "__state_save_vm__: Checking if VM $vmid exists"
    if ! __vm_exists__ "$vmid"; then
        __state_log__ "ERROR" "VM $vmid does not exist"
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi
    __state_log__ "DEBUG" "__state_save_vm__: VM exists check passed"

    local state_file="${STATE_DIR}/vm_${vmid}_${state_name}.json"
    __state_log__ "DEBUG" "State will be saved to: $state_file"

    # Get VM configuration
    __state_log__ "DEBUG" "__state_save_vm__: Getting VM configuration"
    local config=$(qm config "$vmid" 2>/dev/null)
    if [[ -z "$config" ]]; then
        __state_log__ "ERROR" "Failed to get VM $vmid configuration"
        echo "Error: Failed to get VM configuration" >&2
        return 1
    fi
    __state_log__ "DEBUG" "__state_save_vm__: Retrieved VM configuration successfully"

    # Get VM status
    __state_log__ "DEBUG" "__state_save_vm__: Getting VM status and node"
    local status=$(__vm_get_status__ "$vmid")
    local node=$(__get_vm_node__ "$vmid")
    __state_log__ "DEBUG" "__state_save_vm__: status=$status, node=$node"

    # Create JSON state file
    {
        echo "{"
        echo "  \"type\": \"vm\","
        echo "  \"vmid\": $vmid,"
        echo "  \"name\": \"$state_name\","
        echo "  \"timestamp\": \"$(date -Iseconds)\","
        echo "  \"status\": \"$status\","
        echo "  \"node\": \"$node\","
        echo "  \"config\": {"

        # Parse and format configuration
        local first=true
        while IFS=': ' read -r key value; do
            [[ -z "$key" ]] && continue

            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi

            # Escape special characters in value
            value=$(echo "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')
            echo -n "    \"$key\": \"$value\""
        done <<<"$config"

        echo ""
        echo "  }"
        echo "}"
    } >"$state_file"

    __state_log__ "INFO" "State file created successfully: $state_file"
    echo "State saved: $state_file"
    return 0
}

# --- __state_restore_vm__ ----------------------------------------------------
# @function __state_restore_vm__
# @description Restore VM configuration from state file.
# @usage __state_restore_vm__ <vmid> <state_name> [--force]
# @param 1 VMID
# @param 2 State name
# @param --force Apply changes without confirmation
# @return 0 on success, 1 on error
__state_restore_vm__() {
    __state_log__ "DEBUG" "__state_restore_vm__: Function called with $# arguments"
    local vmid="$1"
    local state_name="$2"
    local force=false

    if [[ "$3" == "--force" ]]; then
        force=true
    fi
    __state_log__ "DEBUG" "__state_restore_vm__: vmid=$vmid, state_name=$state_name, force=$force"

    local state_file="${STATE_DIR}/vm_${vmid}_${state_name}.json"
    __state_log__ "DEBUG" "__state_restore_vm__: state_file=$state_file"

    if [[ ! -f "$state_file" ]]; then
        __state_log__ "ERROR" "State file not found: $state_file"
        echo "Error: State file not found: $state_file" >&2
        return 1
    fi

    # Validate VM exists
    __state_log__ "DEBUG" "__state_restore_vm__: Checking if VM $vmid exists"
    if ! __vm_exists__ "$vmid"; then
        __state_log__ "ERROR" "VM $vmid does not exist"
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    # Show what will change
    if [[ "$force" != "true" ]]; then
        __state_log__ "DEBUG" "__state_restore_vm__: Showing changes (not forced)"
        __state_show_changes__ "$vmid" "$state_name" || return 1

        read -p "Apply these changes? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            __state_log__ "INFO" "Restore cancelled by user"
            echo "Restore cancelled"
            return 1
        fi
    fi

    # Extract and apply configuration
    __state_log__ "DEBUG" "__state_restore_vm__: Extracting configuration from state file"
    local config=$(jq -r '.config | to_entries[] | "\(.key)=\(.value)"' "$state_file")

    local node=$(__get_vm_node__ "$vmid")
    __state_log__ "DEBUG" "__state_restore_vm__: Applying configuration changes"

    while IFS='=' read -r key value; do
        if qm set "$vmid" --"$key" "$value" 2>/dev/null; then
            __state_log__ "DEBUG" "__state_restore_vm__: Set $key=$value"
            echo "Set $key=$value"
        else
            __state_log__ "WARN" "Failed to set $key=$value"
            echo "Warning: Failed to set $key=$value" >&2
        fi
    done <<<"$config"

    __state_log__ "INFO" "VM $vmid restored from state: $state_name"
    echo "VM $vmid restored from state: $state_name"
    return 0
}

# --- __state_compare_vm__ ----------------------------------------------------
# @function __state_compare_vm__
# @description Compare current VM state with saved state.
# @usage __state_compare_vm__ <vmid> <state_name>
# @param 1 VMID
# @param 2 State name
# @return 0 if identical, 1 if different
__state_compare_vm__() {
    __state_log__ "DEBUG" "__state_compare_vm__: Function called with $# arguments"
    local vmid="$1"
    local state_name="$2"
    __state_log__ "DEBUG" "__state_compare_vm__: vmid=$vmid, state_name=$state_name"

    local state_file="${STATE_DIR}/vm_${vmid}_${state_name}.json"

    if [[ ! -f "$state_file" ]]; then
        __state_log__ "ERROR" "State file not found: $state_file"
        echo "Error: State file not found: $state_file" >&2
        return 1
    fi

    if ! __vm_exists__ "$vmid"; then
        __state_log__ "ERROR" "VM $vmid does not exist"
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    # Get current config
    __state_log__ "DEBUG" "__state_compare_vm__: Getting current configuration"
    local current_config=$(qm config "$vmid" 2>/dev/null)

    # Get saved config
    __state_log__ "DEBUG" "__state_compare_vm__: Getting saved configuration"
    local saved_config=$(jq -r '.config | to_entries[] | "\(.key): \(.value)"' "$state_file")

    # Compare
    __state_log__ "DEBUG" "__state_compare_vm__: Comparing configurations"
    local differences=0

    while IFS=': ' read -r key value; do
        local current_value=$(echo "$current_config" | grep "^${key}:" | cut -d':' -f2- | sed 's/^ //')
        local saved_value=$(echo "$saved_config" | grep "^${key}:" | cut -d':' -f2- | sed 's/^ //')

        if [[ "$current_value" != "$saved_value" ]]; then
            __state_log__ "DEBUG" "__state_compare_vm__: Difference found in $key"
            echo "Changed: $key"
            echo "  Current: $current_value"
            echo "  Saved:   $saved_value"
            ((differences += 1))
        fi
    done <<<"$saved_config"

    if ((differences == 0)); then
        __state_log__ "INFO" "No differences found between current and saved state"
        echo "No differences found"
        return 0
    else
        __state_log__ "INFO" "Found $differences difference(s) between current and saved state"
        echo "Found $differences difference(s)"
        return 1
    fi
}

# --- __state_export_vm__ -----------------------------------------------------
# @function __state_export_vm__
# @description Export VM state to portable format.
# @usage __state_export_vm__ <vmid> <output_file>
# @param 1 VMID
# @param 2 Output file path
# @return 0 on success, 1 on error
__state_export_vm__() {
    __state_log__ "DEBUG" "__state_export_vm__: Function called with $# arguments"
    local vmid="$1"
    local output_file="$2"
    __state_log__ "DEBUG" "__state_export_vm__: vmid=$vmid, output_file=$output_file"

    if ! __vm_exists__ "$vmid"; then
        __state_log__ "ERROR" "VM $vmid does not exist"
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    # Save to temporary state
    local temp_state="export_$(date +%s)"
    __state_log__ "DEBUG" "__state_export_vm__: Creating temporary state: $temp_state"
    __state_save_vm__ "$vmid" "$temp_state" >/dev/null || return 1

    # Copy to output location
    local state_file="${STATE_DIR}/vm_${vmid}_${temp_state}.json"
    __state_log__ "DEBUG" "__state_export_vm__: Copying to output file"
    cp "$state_file" "$output_file"

    # Cleanup temp state
    __state_log__ "DEBUG" "__state_export_vm__: Cleaning up temporary state"
    rm -f "$state_file"

    __state_log__ "INFO" "VM $vmid exported to: $output_file"
    echo "VM $vmid exported to: $output_file"
    return 0
}

###############################################################################
# CT State Management
###############################################################################

# --- __state_save_ct__ -------------------------------------------------------
# @function __state_save_ct__
# @description Save CT configuration to state file.
# @usage __state_save_ct__ <ctid> [state_name]
# @param 1 CTID
# @param 2 State name (default: timestamp)
# @return 0 on success, 1 on error
__state_save_ct__() {
    __state_log__ "DEBUG" "__state_save_ct__: Function called with $# arguments"
    local ctid="$1"
    local state_name="${2:-$(date +%Y%m%d_%H%M%S)}"
    __state_log__ "INFO" "Saving state for CT $ctid as '$state_name'"
    __state_log__ "DEBUG" "__state_save_ct__: ctid=$ctid, state_name=$state_name"

    if ! __ct_exists__ "$ctid"; then
        __state_log__ "ERROR" "CT $ctid does not exist"
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    local state_file="${STATE_DIR}/ct_${ctid}_${state_name}.json"
    __state_log__ "DEBUG" "State will be saved to: $state_file"

    # Get CT configuration
    __state_log__ "DEBUG" "__state_save_ct__: Getting CT configuration"
    local config=$(pct config "$ctid" 2>/dev/null)
    if [[ -z "$config" ]]; then
        __state_log__ "ERROR" "Failed to get CT $ctid configuration"
        echo "Error: Failed to get CT configuration" >&2
        return 1
    fi

    # Get CT status
    __state_log__ "DEBUG" "__state_save_ct__: Getting CT status"
    local status=$(__ct_get_status__ "$ctid")

    # Create JSON state file
    {
        echo "{"
        echo "  \"type\": \"ct\","
        echo "  \"ctid\": $ctid,"
        echo "  \"name\": \"$state_name\","
        echo "  \"timestamp\": \"$(date -Iseconds)\","
        echo "  \"status\": \"$status\","
        echo "  \"config\": {"

        local first=true
        while IFS=': ' read -r key value; do
            [[ -z "$key" ]] && continue

            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi

            value=$(echo "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')
            echo -n "    \"$key\": \"$value\""
        done <<<"$config"

        echo ""
        echo "  }"
        echo "}"
    } >"$state_file"

    __state_log__ "INFO" "State file created successfully: $state_file"
    echo "State saved: $state_file"
    return 0
}

# --- __state_restore_ct__ ----------------------------------------------------
# @function __state_restore_ct__
# @description Restore CT configuration from state file.
# @usage __state_restore_ct__ <ctid> <state_name> [--force]
# @param 1 CTID
# @param 2 State name
# @param --force Apply without confirmation
# @return 0 on success, 1 on error
__state_restore_ct__() {
    __state_log__ "DEBUG" "__state_restore_ct__: Function called with $# arguments"
    local ctid="$1"
    local state_name="$2"
    local force=false

    if [[ "$3" == "--force" ]]; then
        force=true
    fi
    __state_log__ "DEBUG" "__state_restore_ct__: ctid=$ctid, state_name=$state_name, force=$force"

    local state_file="${STATE_DIR}/ct_${ctid}_${state_name}.json"
    __state_log__ "DEBUG" "__state_restore_ct__: state_file=$state_file"

    if [[ ! -f "$state_file" ]]; then
        __state_log__ "ERROR" "State file not found: $state_file"
        echo "Error: State file not found: $state_file" >&2
        return 1
    fi

    if ! __ct_exists__ "$ctid"; then
        __state_log__ "ERROR" "CT $ctid does not exist"
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    # Show changes if not forced
    if [[ "$force" != "true" ]]; then
        __state_log__ "DEBUG" "__state_restore_ct__: Showing changes (not forced)"
        __state_compare_ct__ "$ctid" "$state_name" || true

        read -p "Apply these changes? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            __state_log__ "INFO" "Restore cancelled by user"
            echo "Restore cancelled"
            return 1
        fi
    fi

    # Extract and apply configuration
    __state_log__ "DEBUG" "__state_restore_ct__: Extracting and applying configuration"
    local config=$(jq -r '.config | to_entries[] | "\(.key)=\(.value)"' "$state_file")

    while IFS='=' read -r key value; do
        if pct set "$ctid" -"$key" "$value" 2>/dev/null; then
            __state_log__ "DEBUG" "__state_restore_ct__: Set $key=$value"
            echo "Set $key=$value"
        else
            __state_log__ "WARN" "Failed to set $key=$value"
            echo "Warning: Failed to set $key=$value" >&2
        fi
    done <<<"$config"

    __state_log__ "INFO" "CT $ctid restored from state: $state_name"
    echo "CT $ctid restored from state: $state_name"
    return 0
}

# --- __state_compare_ct__ ----------------------------------------------------
# @function __state_compare_ct__
# @description Compare current CT state with saved state.
# @usage __state_compare_ct__ <ctid> <state_name>
# @param 1 CTID
# @param 2 State name
# @return 0 if identical, 1 if different
__state_compare_ct__() {
    __state_log__ "DEBUG" "__state_compare_ct__: Function called with $# arguments"
    local ctid="$1"
    local state_name="$2"
    __state_log__ "DEBUG" "__state_compare_ct__: ctid=$ctid, state_name=$state_name"

    local state_file="${STATE_DIR}/ct_${ctid}_${state_name}.json"

    if [[ ! -f "$state_file" ]]; then
        __state_log__ "ERROR" "State file not found: $state_file"
        echo "Error: State file not found: $state_file" >&2
        return 1
    fi

    if ! __ct_exists__ "$ctid"; then
        __state_log__ "ERROR" "CT $ctid does not exist"
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    # Get current config
    __state_log__ "DEBUG" "__state_compare_ct__: Getting current configuration"
    local current_config=$(pct config "$ctid" 2>/dev/null)

    # Get saved config
    __state_log__ "DEBUG" "__state_compare_ct__: Getting saved configuration"
    local saved_config=$(jq -r '.config | to_entries[] | "\(.key): \(.value)"' "$state_file")

    # Compare
    __state_log__ "DEBUG" "__state_compare_ct__: Comparing configurations"
    local differences=0

    while IFS=': ' read -r key value; do
        local current_value=$(echo "$current_config" | grep "^${key}:" | cut -d':' -f2- | sed 's/^ //')
        local saved_value=$(echo "$saved_config" | grep "^${key}:" | cut -d':' -f2- | sed 's/^ //')

        if [[ "$current_value" != "$saved_value" ]]; then
            __state_log__ "DEBUG" "__state_compare_ct__: Difference found in $key"
            echo "Changed: $key"
            echo "  Current: $current_value"
            echo "  Saved:   $saved_value"
            ((differences += 1))
        fi
    done <<<"$saved_config"

    if ((differences == 0)); then
        __state_log__ "INFO" "No differences found"
        echo "No differences found"
        return 0
    else
        __state_log__ "INFO" "Found $differences difference(s)"
        echo "Found $differences difference(s)"
        return 1
    fi
}

# --- __state_export_ct__ -----------------------------------------------------
# @function __state_export_ct__
# @description Export CT state to portable format.
# @usage __state_export_ct__ <ctid> <output_file>
# @param 1 CTID
# @param 2 Output file path
# @return 0 on success, 1 on error
__state_export_ct__() {
    __state_log__ "DEBUG" "__state_export_ct__: Function called with $# arguments"
    local ctid="$1"
    local output_file="$2"
    __state_log__ "DEBUG" "__state_export_ct__: ctid=$ctid, output_file=$output_file"

    if ! __ct_exists__ "$ctid"; then
        __state_log__ "ERROR" "CT $ctid does not exist"
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    local temp_state="export_$(date +%s)"
    __state_log__ "DEBUG" "__state_export_ct__: Creating temporary state: $temp_state"
    __state_save_ct__ "$ctid" "$temp_state" >/dev/null || return 1

    local state_file="${STATE_DIR}/ct_${ctid}_${temp_state}.json"
    __state_log__ "DEBUG" "__state_export_ct__: Copying to output file"
    cp "$state_file" "$output_file"
    rm -f "$state_file"

    __state_log__ "INFO" "CT $ctid exported to: $output_file"
    echo "CT $ctid exported to: $output_file"
    return 0
}

###############################################################################
# Bulk Operations
###############################################################################

# --- __state_save_bulk__ -----------------------------------------------------
# @function __state_save_bulk__
# @description Save state for multiple VMs/CTs.
# @usage __state_save_bulk__ <type> <start_id> <end_id> [state_name]
# @param 1 Type (vm or ct)
# @param 2 Start ID
# @param 3 End ID
# @param 4 State name (default: timestamp)
# @return 0 on success, 1 if any failed
__state_save_bulk__() {
    __state_log__ "DEBUG" "__state_save_bulk__: Function called with $# arguments"
    local type="$1"
    local start_id="$2"
    local end_id="$3"
    local state_name="${4:-$(date +%Y%m%d_%H%M%S)}"
    __state_log__ "INFO" "Starting bulk save: type=$type, start_id=$start_id, end_id=$end_id, state_name=$state_name"

    local success=0
    local failed=0

    for ((id = start_id; id <= end_id; id++)); do
        __state_log__ "DEBUG" "__state_save_bulk__: Processing ID $id"
        if [[ "$type" == "vm" ]]; then
            if __state_save_vm__ "$id" "$state_name" 2>/dev/null; then
                ((success += 1))
                __state_log__ "DEBUG" "__state_save_bulk__: VM $id saved successfully"
            else
                ((failed += 1))
                __state_log__ "DEBUG" "__state_save_bulk__: VM $id save failed"
            fi
        elif [[ "$type" == "ct" ]]; then
            if __state_save_ct__ "$id" "$state_name" 2>/dev/null; then
                ((success += 1))
                __state_log__ "DEBUG" "__state_save_bulk__: CT $id saved successfully"
            else
                ((failed += 1))
                __state_log__ "DEBUG" "__state_save_bulk__: CT $id save failed"
            fi
        fi
    done

    __state_log__ "INFO" "Bulk state save complete: $success succeeded, $failed failed"
    echo "Bulk state save complete: $success succeeded, $failed failed"

    if ((failed > 0)); then
        return 1
    else
        return 0
    fi
}

# --- __state_restore_bulk__ --------------------------------------------------
# @function __state_restore_bulk__
# @description Restore state for multiple VMs/CTs.
# @usage __state_restore_bulk__ <type> <start_id> <end_id> <state_name> [--force]
# @param 1 Type (vm or ct)
# @param 2 Start ID
# @param 3 End ID
# @param 4 State name
# @param --force Apply without confirmation
# @return 0 on success, 1 if any failed
__state_restore_bulk__() {
    __state_log__ "DEBUG" "__state_restore_bulk__: Function called with $# arguments"
    local type="$1"
    local start_id="$2"
    local end_id="$3"
    local state_name="$4"
    local force_flag=""

    if [[ "$5" == "--force" ]]; then
        force_flag="--force"
    fi
    __state_log__ "INFO" "Starting bulk restore: type=$type, start_id=$start_id, end_id=$end_id, state_name=$state_name, force=$force_flag"

    local success=0
    local failed=0

    for ((id = start_id; id <= end_id; id++)); do
        __state_log__ "DEBUG" "__state_restore_bulk__: Processing ID $id"
        if [[ "$type" == "vm" ]]; then
            if __state_restore_vm__ "$id" "$state_name" $force_flag 2>/dev/null; then
                ((success += 1))
                __state_log__ "DEBUG" "__state_restore_bulk__: VM $id restored successfully"
            else
                ((failed += 1))
                __state_log__ "DEBUG" "__state_restore_bulk__: VM $id restore failed"
            fi
        elif [[ "$type" == "ct" ]]; then
            if __state_restore_ct__ "$id" "$state_name" $force_flag 2>/dev/null; then
                ((success += 1))
                __state_log__ "DEBUG" "__state_restore_bulk__: CT $id restored successfully"
            else
                ((failed += 1))
                __state_log__ "DEBUG" "__state_restore_bulk__: CT $id restore failed"
            fi
        fi
    done

    __state_log__ "INFO" "Bulk state restore complete: $success succeeded, $failed failed"
    echo "Bulk state restore complete: $success succeeded, $failed failed"

    if ((failed > 0)); then
        return 1
    else
        return 0
    fi
}

# --- __state_snapshot_cluster__ ----------------------------------------------
# @function __state_snapshot_cluster__
# @description Save state of all VMs and CTs in cluster.
# @usage __state_snapshot_cluster__ [state_name]
# @param 1 State name (default: timestamp)
# @return 0 on success, 1 if any failed
__state_snapshot_cluster__() {
    __state_log__ "DEBUG" "__state_snapshot_cluster__: Function called with $# arguments"
    local state_name="${1:-cluster_$(date +%Y%m%d_%H%M%S)}"
    __state_log__ "INFO" "Creating cluster snapshot: $state_name"

    echo "Creating cluster snapshot: $state_name"

    # Get all VM IDs
    __state_log__ "DEBUG" "__state_snapshot_cluster__: Getting VM list"
    local vm_ids=$(qm list 2>/dev/null | awk 'NR>1 {print $1}')

    # Get all CT IDs
    __state_log__ "DEBUG" "__state_snapshot_cluster__: Getting CT list"
    local ct_ids=$(pct list 2>/dev/null | awk 'NR>1 {print $1}')

    local vm_success=0
    local vm_failed=0
    local ct_success=0
    local ct_failed=0

    # Save VM states
    __state_log__ "DEBUG" "__state_snapshot_cluster__: Saving VM states"
    for vmid in $vm_ids; do
        if __state_save_vm__ "$vmid" "$state_name" &>/dev/null; then
            ((vm_success += 1))
        else
            ((vm_failed += 1))
        fi
    done

    # Save CT states
    __state_log__ "DEBUG" "__state_snapshot_cluster__: Saving CT states"
    for ctid in $ct_ids; do
        if __state_save_ct__ "$ctid" "$state_name" &>/dev/null; then
            ((ct_success += 1))
        else
            ((ct_failed += 1))
        fi
    done

    __state_log__ "INFO" "Cluster snapshot complete: VMs($vm_success succeeded, $vm_failed failed), CTs($ct_success succeeded, $ct_failed failed)"
    echo "Cluster snapshot complete:"
    echo "  VMs: $vm_success succeeded, $vm_failed failed"
    echo "  CTs: $ct_success succeeded, $ct_failed failed"

    if ((vm_failed > 0 || ct_failed > 0)); then
        return 1
    else
        return 0
    fi
}

###############################################################################
# State File Management
###############################################################################

# --- __state_list__ ----------------------------------------------------------
# @function __state_list__
# @description List all saved states.
# @usage __state_list__ [type] [id]
# @param 1 Type filter (vm or ct, optional)
# @param 2 ID filter (optional)
# @return 0 always
__state_list__() {
    __state_log__ "DEBUG" "__state_list__: Function called with $# arguments"
    local type_filter="$1"
    local id_filter="$2"
    __state_log__ "DEBUG" "__state_list__: type_filter=$type_filter, id_filter=$id_filter"

    local pattern="*"

    if [[ -n "$type_filter" ]] && [[ -n "$id_filter" ]]; then
        pattern="${type_filter}_${id_filter}_*.json"
    elif [[ -n "$type_filter" ]]; then
        pattern="${type_filter}_*.json"
    fi
    __state_log__ "DEBUG" "__state_list__: Using pattern: $pattern"

    echo "Saved states in $STATE_DIR:"
    echo ""

    find "$STATE_DIR" -name "$pattern" -type f 2>/dev/null | while read -r file; do
        local filename=$(basename "$file")
        local timestamp=$(jq -r '.timestamp' "$file" 2>/dev/null || echo "unknown")
        local type=$(jq -r '.type' "$file" 2>/dev/null || echo "unknown")
        local id=$(jq -r 'if .type == "vm" then .vmid else .ctid end' "$file" 2>/dev/null || echo "unknown")
        local name=$(jq -r '.name' "$file" 2>/dev/null || echo "unknown")

        echo "$filename"
        echo "  Type: $type, ID: $id, Name: $name"
        echo "  Timestamp: $timestamp"
        echo ""
    done
    __state_log__ "DEBUG" "__state_list__: List operation complete"
}

# --- __state_info__ ----------------------------------------------------------
# @function __state_info__
# @description Show detailed information about a state file.
# @usage __state_info__ <type> <id> <state_name>
# @param 1 Type (vm or ct)
# @param 2 ID
# @param 3 State name
# @return 0 on success, 1 if not found
__state_info__() {
    __state_log__ "DEBUG" "__state_info__: Function called with $# arguments"
    local type="$1"
    local id="$2"
    local state_name="$3"
    __state_log__ "DEBUG" "__state_info__: type=$type, id=$id, state_name=$state_name"

    local state_file="${STATE_DIR}/${type}_${id}_${state_name}.json"

    if [[ ! -f "$state_file" ]]; then
        __state_log__ "ERROR" "State file not found: $state_file"
        echo "Error: State file not found: $state_file" >&2
        return 1
    fi

    __state_log__ "INFO" "Displaying state information for: $state_file"
    echo "State Information:"
    echo "  File: $state_file"
    jq '.' "$state_file"

    return 0
}

# --- __state_delete__ --------------------------------------------------------
# @function __state_delete__
# @description Delete a state file.
# @usage __state_delete__ <type> <id> <state_name>
# @param 1 Type (vm or ct)
# @param 2 ID
# @param 3 State name
# @return 0 on success, 1 if not found
__state_delete__() {
    __state_log__ "DEBUG" "__state_delete__: Function called with $# arguments"
    local type="$1"
    local id="$2"
    local state_name="$3"
    __state_log__ "DEBUG" "__state_delete__: type=$type, id=$id, state_name=$state_name"

    local state_file="${STATE_DIR}/${type}_${id}_${state_name}.json"

    if [[ ! -f "$state_file" ]]; then
        __state_log__ "ERROR" "State file not found: $state_file"
        echo "Error: State file not found: $state_file" >&2
        return 1
    fi

    rm -f "$state_file"
    __state_log__ "INFO" "Deleted state file: $state_file"
    echo "Deleted state: $state_file"
    return 0
}

# --- __state_cleanup__ -------------------------------------------------------
# @function __state_cleanup__
# @description Clean up old state files.
# @usage __state_cleanup__ [--days <n>]
# @param --days Number of days to keep (default: 30)
# @return 0 always
__state_cleanup__() {
    __state_log__ "DEBUG" "__state_cleanup__: Function called with $# arguments"
    local days=30

    if [[ "$1" == "--days" ]]; then
        days="$2"
    fi
    __state_log__ "INFO" "Cleaning up state files older than $days days"

    echo "Cleaning up state files older than $days days..."

    local count=0
    find "$STATE_DIR" -name "*.json" -type f -mtime "+$days" 2>/dev/null | while read -r file; do
        rm -f "$file"
        ((count += 1))
        __state_log__ "DEBUG" "__state_cleanup__: Deleted $(basename "$file")"
        echo "Deleted: $(basename "$file")"
    done

    __state_log__ "INFO" "Cleanup complete: $count files removed"
    echo "Cleanup complete: $count files removed"
    return 0
}

###############################################################################
# Comparison and Validation
###############################################################################

# --- __state_diff__ ----------------------------------------------------------
# @function __state_diff__
# @description Show differences between two states.
# @usage __state_diff__ <type> <id> <state1> <state2>
# @param 1 Type (vm or ct)
# @param 2 ID
# @param 3 First state name
# @param 4 Second state name
# @return 0 if identical, 1 if different
__state_diff__() {
    local type="$1"
    local id="$2"
    local state1="$3"
    local state2="$4"

    __state_log__ "DEBUG" "Comparing states: $state1 vs $state2 for $type $id"

    local file1="${STATE_DIR}/${type}_${id}_${state1}.json"
    local file2="${STATE_DIR}/${type}_${id}_${state2}.json"

    if [[ ! -f "$file1" ]]; then
        __state_log__ "ERROR" "State file not found: $file1"
        echo "Error: State file not found: $file1" >&2
        return 1
    fi

    if [[ ! -f "$file2" ]]; then
        __state_log__ "ERROR" "State file not found: $file2"
        echo "Error: State file not found: $file2" >&2
        return 1
    fi

    echo "Comparing states: $state1 vs $state2"
    echo ""

    # Extract configs
    local config1=$(jq -r '.config' "$file1")
    local config2=$(jq -r '.config' "$file2")

    # Compare
    local differences=0

    # Check all keys from both configs
    local all_keys=$(jq -r '.config | keys[]' "$file1" "$file2" | sort -u)

    while read -r key; do
        local value1=$(jq -r ".config.\"$key\" // empty" "$file1")
        local value2=$(jq -r ".config.\"$key\" // empty" "$file2")

        if [[ "$value1" != "$value2" ]]; then
            echo "Changed: $key"
            echo "  $state1: $value1"
            echo "  $state2: $value2"
            ((differences += 1))
        fi
    done <<<"$all_keys"

    if ((differences == 0)); then
        __state_log__ "INFO" "No differences found between $state1 and $state2"
        echo "No differences found"
        return 0
    else
        __state_log__ "INFO" "Found $differences difference(s) between $state1 and $state2"
        echo ""
        echo "Found $differences difference(s)"
        return 1
    fi
}

# --- __state_show_changes__ --------------------------------------------------
# @function __state_show_changes__
# @description Show changes that will be applied during restore.
# @usage __state_show_changes__ <vmid_or_ctid> <state_name>
# @param 1 VM or CT ID
# @param 2 State name
# @return 0 always
__state_show_changes__() {
    __state_log__ "DEBUG" "__state_show_changes__: Function called with $# arguments"
    local id="$1"
    local state_name="$2"
    __state_log__ "DEBUG" "__state_show_changes__: id=$id, state_name=$state_name"

    # Try VM first
    if [[ -f "${STATE_DIR}/vm_${id}_${state_name}.json" ]]; then
        __state_log__ "DEBUG" "__state_show_changes__: Found VM state file"
        __state_compare_vm__ "$id" "$state_name"
    elif [[ -f "${STATE_DIR}/ct_${id}_${state_name}.json" ]]; then
        __state_log__ "DEBUG" "__state_show_changes__: Found CT state file"
        __state_compare_ct__ "$id" "$state_name"
    else
        __state_log__ "ERROR" "State file not found for ID $id"
        echo "Error: State file not found for ID $id" >&2
        return 1
    fi
}

# --- __state_validate__ ------------------------------------------------------
# @function __state_validate__
# @description Validate a state file.
# @usage __state_validate__ <state_file>
# @param 1 State file path
# @return 0 if valid, 1 if invalid
__state_validate__() {
    __state_log__ "DEBUG" "__state_validate__: Function called with $# arguments"
    local state_file="$1"
    __state_log__ "DEBUG" "__state_validate__: state_file=$state_file"

    if [[ ! -f "$state_file" ]]; then
        __state_log__ "ERROR" "File not found: $state_file"
        echo "Error: File not found: $state_file" >&2
        return 1
    fi

    # Validate JSON
    __state_log__ "DEBUG" "__state_validate__: Validating JSON syntax"
    if ! jq empty "$state_file" 2>/dev/null; then
        __state_log__ "ERROR" "Invalid JSON in state file"
        echo "Error: Invalid JSON in state file" >&2
        return 1
    fi

    # Check required fields
    __state_log__ "DEBUG" "__state_validate__: Checking required fields"
    local type=$(jq -r '.type' "$state_file" 2>/dev/null)
    local config=$(jq -r '.config' "$state_file" 2>/dev/null)

    if [[ -z "$type" ]] || [[ "$type" == "null" ]]; then
        __state_log__ "ERROR" "Missing 'type' field in state file"
        echo "Error: Missing 'type' field" >&2
        return 1
    fi

    if [[ -z "$config" ]] || [[ "$config" == "null" ]]; then
        __state_log__ "ERROR" "Missing 'config' field in state file"
        echo "Error: Missing 'config' field" >&2
        return 1
    fi

    __state_log__ "INFO" "State file is valid"
    echo "State file is valid"
    return 0
}

###############################################################################
# Example Usage (commented out)
###############################################################################
#
# # Save VM state
# __state_save_vm__ 100 "before_update"
#
# # Make changes...
#
# # Compare with saved state
# __state_compare_vm__ 100 "before_update"
#
# # Restore if needed
# __state_restore_vm__ 100 "before_update"
#
# # Bulk operations
# __state_save_bulk__ vm 100 110 "pre_migration"
# __state_restore_bulk__ vm 100 110 "pre_migration" --force
#
# # Cluster snapshot
# __state_snapshot_cluster__ "weekly_backup"
#
# # List states
# __state_list__ vm 100
#
# # Compare states
# __state_diff__ vm 100 "before" "after"
#
