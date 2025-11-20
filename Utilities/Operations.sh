#!/bin/bash
#
# Operations.sh
#
# Wrapper functions for common Proxmox operations with built-in error handling,
# validation, and cluster-awareness. Reduces code duplication and provides
# consistent patterns for VM/CT operations.
#
# Usage:
#   source "${UTILITYPATH}/Operations.sh"
#
# Features:
#   - Cluster-aware operations (automatic node detection)
#   - Built-in error handling and validation
#   - Consistent return codes and error messages
#   - Testable and mockable functions
#   - State management helpers
#
# Function Index:
#   - __api_log__
#   - __vm_exists__
#   - __vm_get_status__
#   - __vm_is_running__
#   - __vm_start__
#   - __vm_stop__
#   - __vm_set_config__
#   - __vm_get_config__
#   - __ct_exists__
#   - __ct_get_status__
#   - __ct_is_running__
#   - __ct_start__
#   - __ct_stop__
#   - __ct_set_config__
#   - __ct_get_config__
#   - __iterate_vms__
#   - __iterate_cts__
#   - __vm_shutdown__
#   - __vm_restart__
#   - __vm_suspend__
#   - __vm_resume__
#   - __vm_list_all__
#   - __vm_wait_for_status__
#   - __ct_shutdown__
#   - __ct_restart__
#   - __ct_list_all__
#   - __ct_wait_for_status__
#   - __ct_exec__
#   - __get_vm_info__
#   - __get_ct_info__
#   - __node_exec__
#   - __vm_node_exec__
#   - __ct_node_exec__
#   - __pve_exec__
#   - __ct_set_cpu__
#   - __ct_set_memory__
#   - __ct_set_onboot__
#   - __ct_unlock__
#   - __ct_delete__
#   - __ct_set_protection__
#   - __vm_unlock__
#   - __vm_delete__
#   - __vm_set_protection__
#   - __vm_reset__
#   - __ct_set_dns__
#   - __ct_set_network__
#   - __ct_change_password__
#   - __ct_add_ssh_key__
#   - __ct_resize_disk__
#   - __vm_resize_disk__
#   - __vm_backup__
#   - __ct_change_storage__
#   - __ct_move_volume__
#   - __ct_update_packages__
#   - __ct_add_ip_to_note__
#   - __vm_add_ip_to_note__
#

# Source Logger for structured logging
if [[ -n "${UTILITYPATH:-}" && -f "${UTILITYPATH}/Logger.sh" ]]; then
    # shellcheck source=Utilities/Logger.sh
    source "${UTILITYPATH}/Logger.sh"
fi

# Safe logging wrapper
__api_log__() {
    local level="$1"
    local message="$2"
    if declare -f __log__ >/dev/null 2>&1; then
        __log__ "$level" "$message" "API"
    fi
}

# Source dependencies
source "${UTILITYPATH}/ArgumentParser.sh"
source "${UTILITYPATH}/Cluster.sh"

###############################################################################
# VM Operations
###############################################################################

# --- __vm_exists__ -----------------------------------------------------------
# @function __vm_exists__
# @description Check if a VM exists (cluster-wide).
# @usage __vm_exists__ <vmid>
# @param 1 VM ID
# @return 0 if exists, 1 if not
__vm_exists__() {
    local vmid="$1"

    __api_log__ "DEBUG" "Checking if VM $vmid exists"

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        __api_log__ "DEBUG" "Invalid VMID: $vmid"
        return 1
    fi

    # Use __get_vm_node__ to check existence
    local node
    node=$(__get_vm_node__ "$vmid" 2>/dev/null)

    if [[ -n "$node" ]]; then
        __api_log__ "DEBUG" "VM $vmid exists on node $node"
        return 0
    else
        __api_log__ "DEBUG" "VM $vmid does not exist"
        return 1
    fi
}

# --- __vm_get_status__ -------------------------------------------------------
# @function __vm_get_status__
# @description Get VM status (running, stopped, paused, etc).
# @usage __vm_get_status__ <vmid>
# @param 1 VM ID
# @return Prints status to stdout, returns 1 on error
__vm_get_status__() {
    local vmid="$1"

    __api_log__ "DEBUG" "Getting status for VM $vmid"

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid VMID: $vmid"
        return 1
    fi

    if ! __vm_exists__ "$vmid"; then
        echo "Error: VM $vmid does not exist" >&2
        __api_log__ "ERROR" "VM $vmid does not exist"
        return 1
    fi

    local node
    node=$(__get_vm_node__ "$vmid")

    # Get status from qm status
    qm status "$vmid" --node "$node" 2>/dev/null | awk '/^status:/ {print $2}'
}

# --- __vm_is_running__ -------------------------------------------------------
# @function __vm_is_running__
# @description Check if VM is running.
# @usage __vm_is_running__ <vmid>
# @param 1 VM ID
# @return 0 if running, 1 if not
__vm_is_running__() {
    local vmid="$1"
    local status

    __api_log__ "DEBUG" "Checking if VM $vmid is running"

    status=$(__vm_get_status__ "$vmid" 2>/dev/null) || {
        __api_log__ "ERROR" "Failed to get status for VM $vmid"
        return 1
    }

    if [[ "$status" == "running" ]]; then
        __api_log__ "DEBUG" "VM $vmid is running"
        return 0
    else
        __api_log__ "DEBUG" "VM $vmid is not running (status: $status)"
        return 1
    fi
}

# --- __vm_start__ ------------------------------------------------------------
# @function __vm_start__
# @description Start a VM (cluster-aware).
# @usage __vm_start__ <vmid> [options]
# @param 1 VM ID
# @param @ Additional qm start options
# @return 0 on success, 1 on error
__vm_start__() {
    local vmid="$1"
    shift

    __api_log__ "INFO" "Starting VM $vmid"

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid VMID: $vmid"
        return 1
    fi

    if ! __vm_exists__ "$vmid"; then
        echo "Error: VM $vmid does not exist" >&2
        __api_log__ "ERROR" "VM $vmid does not exist"
        return 1
    fi

    # Check if already running
    if __vm_is_running__ "$vmid"; then
        echo "VM $vmid is already running" >&2
        __api_log__ "DEBUG" "VM $vmid already running"
        return 0
    fi

    local node
    node=$(__get_vm_node__ "$vmid")

    __api_log__ "DEBUG" "Executing: qm start $vmid --node $node $*"

    if qm start "$vmid" --node "$node" "$@" 2>/dev/null; then
        __api_log__ "INFO" "VM $vmid started successfully on node $node"
        return 0
    else
        echo "Error: Failed to start VM $vmid on node $node" >&2
        __api_log__ "ERROR" "Failed to start VM $vmid on node $node"
        return 1
    fi
}

# --- __vm_stop__ -------------------------------------------------------------
# @function __vm_stop__
# @description Stop a VM (cluster-aware).
# @usage __vm_stop__ <vmid> [--timeout <seconds>] [--force]
# @param 1 VM ID
# @param --timeout Timeout in seconds before force stop
# @param --force Force stop immediately
# @return 0 on success, 1 on error
__vm_stop__() {
    local vmid="$1"
    shift

    local timeout=""
    local force=false

    __api_log__ "INFO" "Stopping VM $vmid"

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --timeout)
                timeout="$2"
                __api_log__ "DEBUG" "Using timeout: $timeout seconds"
                shift 2
                ;;
            --force)
                force=true
                __api_log__ "DEBUG" "Force stop enabled"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid VMID: $vmid"
        return 1
    fi

    if ! __vm_exists__ "$vmid"; then
        __api_log__ "ERROR" "VM $vmid does not exist"
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    # Check if already stopped
    if ! __vm_is_running__ "$vmid"; then
        __api_log__ "INFO" "VM $vmid is already stopped"
        echo "VM $vmid is already stopped" >&2
        return 0
    fi

    local node
    node=$(__get_vm_node__ "$vmid")
    __api_log__ "DEBUG" "VM $vmid is on node: $node"

    local cmd="qm stop \"$vmid\" --node \"$node\""
    [[ -n "$timeout" ]] && cmd+=" --timeout \"$timeout\""
    [[ "$force" == true ]] && cmd+=" --force"

    __api_log__ "DEBUG" "Executing: $cmd"

    if eval "$cmd" 2>/dev/null; then
        __api_log__ "INFO" "Successfully stopped VM $vmid"
        return 0
    else
        __api_log__ "ERROR" "Failed to stop VM $vmid on node $node"
        echo "Error: Failed to stop VM $vmid on node $node" >&2
        return 1
    fi
}

# --- __vm_set_config__ -------------------------------------------------------
# @function __vm_set_config__
# @description Set VM configuration parameter.
# @usage __vm_set_config__ <vmid> --<param> <value> [--<param> <value> ...]
# @param 1 VM ID
# @param @ Configuration parameters (e.g., --memory 2048 --cores 4)
# @return 0 on success, 1 on error
__vm_set_config__() {
    local vmid="$1"
    shift

    __api_log__ "INFO" "Setting configuration for VM $vmid: $*"

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid VMID: $vmid"
        return 1
    fi

    if ! __vm_exists__ "$vmid"; then
        __api_log__ "ERROR" "VM $vmid does not exist"
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    local node
    node=$(__get_vm_node__ "$vmid")
    __api_log__ "DEBUG" "Setting config for VM $vmid on node: $node"

    if qm set "$vmid" --node "$node" "$@" 2>/dev/null; then
        __api_log__ "INFO" "Successfully set configuration for VM $vmid"
        return 0
    else
        __api_log__ "ERROR" "Failed to set configuration for VM $vmid"
        echo "Error: Failed to set configuration for VM $vmid" >&2
        return 1
    fi
}

# --- __vm_get_config__ -------------------------------------------------------
# @function __vm_get_config__
# @description Get VM configuration parameter value.
# @usage __vm_get_config__ <vmid> <param>
# @param 1 VM ID
# @param 2 Parameter name (e.g., memory, cores)
# @return Prints value to stdout, returns 1 on error
__vm_get_config__() {
    local vmid="$1"
    local param="$2"

    __api_log__ "DEBUG" "Getting config parameter '$param' for VM $vmid"

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid VMID: $vmid"
        return 1
    fi

    if ! __vm_exists__ "$vmid"; then
        __api_log__ "ERROR" "VM $vmid does not exist"
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    local node
    node=$(__get_vm_node__ "$vmid")

    local value
    value=$(qm config "$vmid" --node "$node" 2>/dev/null | grep "^${param}:" | cut -d' ' -f2-)
    __api_log__ "DEBUG" "VM $vmid config $param: ${value:-<not set>}"
    echo "$value"
}

###############################################################################
# CT Operations (Similar to VM operations)
###############################################################################

# --- __ct_exists__ -----------------------------------------------------------
# @function __ct_exists__
# @description Check if a CT exists.
# @usage __ct_exists__ <ctid>
# @param 1 CT ID
# @return 0 if exists, 1 if not
__ct_exists__() {
    local ctid="$1"

    __api_log__ "DEBUG" "Checking if CT $ctid exists"

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid CTID: $ctid"
        return 1
    fi

    if pct config "$ctid" &>/dev/null; then
        __api_log__ "DEBUG" "CT $ctid exists"
        return 0
    else
        __api_log__ "DEBUG" "CT $ctid does not exist"
        return 1
    fi
}

# --- __ct_get_status__ -------------------------------------------------------
# @function __ct_get_status__
# @description Get CT status.
# @usage __ct_get_status__ <ctid>
# @param 1 CT ID
# @return Prints status to stdout, returns 1 on error
__ct_get_status__() {
    local ctid="$1"

    __api_log__ "DEBUG" "Getting status for CT $ctid"

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid CTID: $ctid"
        return 1
    fi

    if ! __ct_exists__ "$ctid"; then
        __api_log__ "ERROR" "CT $ctid does not exist"
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    local status_output
    status_output=$(pct status "$ctid" 2>/dev/null | awk '/^status:/ {print $2}')
    __api_log__ "DEBUG" "CT $ctid status: ${status_output:-<none>}"
    echo "$status_output"
}

# --- __ct_is_running__ -------------------------------------------------------
# @function __ct_is_running__
# @description Check if CT is running.
# @usage __ct_is_running__ <ctid>
# @param 1 CT ID
# @return 0 if running, 1 if not
__ct_is_running__() {
    local ctid="$1"
    local status

    __api_log__ "DEBUG" "Checking if CT $ctid is running"

    status=$(__ct_get_status__ "$ctid" 2>/dev/null) || {
        __api_log__ "ERROR" "Failed to get status for CT $ctid"
        return 1
    }

    if [[ "$status" == "running" ]]; then
        __api_log__ "DEBUG" "CT $ctid is running"
        return 0
    else
        __api_log__ "DEBUG" "CT $ctid is not running (status: $status)"
        return 1
    fi
}

# --- __ct_start__ ------------------------------------------------------------
# @function __ct_start__
# @description Start a CT.
# @usage __ct_start__ <ctid>
# @param 1 CT ID
# @return 0 on success, 1 on error
__ct_start__() {
    local ctid="$1"

    __api_log__ "INFO" "Starting CT $ctid"

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid CTID: $ctid"
        return 1
    fi

    if ! __ct_exists__ "$ctid"; then
        __api_log__ "ERROR" "CT $ctid does not exist"
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    if __ct_is_running__ "$ctid"; then
        __api_log__ "INFO" "CT $ctid is already running"
        echo "CT $ctid is already running" >&2
        return 0
    fi

    if pct start "$ctid" 2>/dev/null; then
        __api_log__ "INFO" "Successfully started CT $ctid"
        return 0
    else
        __api_log__ "ERROR" "Failed to start CT $ctid"
        echo "Error: Failed to start CT $ctid" >&2
        return 1
    fi
}

# --- __ct_stop__ -------------------------------------------------------------
# @function __ct_stop__
# @description Stop a CT.
# @usage __ct_stop__ <ctid> [--force]
# @param 1 CT ID
# @param --force Force stop
# @return 0 on success, 1 on error
__ct_stop__() {
    local ctid="$1"
    shift

    local force=false

    __api_log__ "INFO" "Stopping CT $ctid"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                force=true
                __api_log__ "DEBUG" "Force stop enabled"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid CTID: $ctid"
        return 1
    fi

    if ! __ct_exists__ "$ctid"; then
        __api_log__ "ERROR" "CT $ctid does not exist"
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    if ! __ct_is_running__ "$ctid"; then
        __api_log__ "INFO" "CT $ctid is already stopped"
        echo "CT $ctid is already stopped" >&2
        return 0
    fi

    local cmd="pct stop \"$ctid\""
    [[ "$force" == true ]] && cmd+=" --force"

    __api_log__ "DEBUG" "Executing: $cmd"

    if eval "$cmd" 2>/dev/null; then
        __api_log__ "INFO" "Successfully stopped CT $ctid"
        return 0
    else
        __api_log__ "ERROR" "Failed to stop CT $ctid"
        echo "Error: Failed to stop CT $ctid" >&2
        return 1
    fi
}

# --- __ct_set_config__ -------------------------------------------------------
# @function __ct_set_config__
# @description Set CT configuration parameter.
# @usage __ct_set_config__ <ctid> -<param> <value> [-<param> <value> ...]
# @param 1 CT ID
# @param @ Configuration parameters (e.g., -memory 2048 -cores 4)
# @return 0 on success, 1 on error
__ct_set_config__() {
    local ctid="$1"
    shift

    __api_log__ "INFO" "Setting configuration for CT $ctid: $*"

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid CTID: $ctid"
        return 1
    fi

    if ! __ct_exists__ "$ctid"; then
        __api_log__ "ERROR" "CT $ctid does not exist"
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    if pct set "$ctid" "$@" 2>/dev/null; then
        __api_log__ "INFO" "Successfully set configuration for CT $ctid"
        return 0
    else
        __api_log__ "ERROR" "Failed to set configuration for CT $ctid"
        echo "Error: Failed to set configuration for CT $ctid" >&2
        return 1
    fi
}

# --- __ct_get_config__ -------------------------------------------------------
# @function __ct_get_config__
# @description Get CT configuration parameter value.
# @usage __ct_get_config__ <ctid> <param>
# @param 1 CT ID
# @param 2 Parameter name (e.g., memory, cores)
# @return Prints value to stdout, returns 1 on error
__ct_get_config__() {
    local ctid="$1"
    local param="$2"

    __api_log__ "DEBUG" "Getting config parameter '$param' for CT $ctid"

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid CTID: $ctid"
        return 1
    fi

    if ! __ct_exists__ "$ctid"; then
        __api_log__ "ERROR" "CT $ctid does not exist"
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    local value
    value=$(pct config "$ctid" 2>/dev/null | grep "^${param}:" | cut -d' ' -f2-)
    __api_log__ "DEBUG" "CT $ctid config $param: ${value:-<not set>}"
    echo "$value"
}

###############################################################################
# Iteration Helpers
###############################################################################

# --- __iterate_vms__ ---------------------------------------------------------
# @function __iterate_vms__
# @description Iterate through VM range and call callback for each.
# @usage __iterate_vms__ <start_id> <end_id> <callback> [callback_args...]
# @param 1 Start VM ID
# @param 2 End VM ID
# @param 3 Callback function name
# @param @ Additional arguments to pass to callback
# @return 0 on success, 1 if any callback fails
#
# Callback function receives: vmid [args...]
__iterate_vms__() {
    local start_id="$1"
    local end_id="$2"
    local callback="$3"
    shift 3

    __api_log__ "INFO" "Iterating VMs: range=$start_id-$end_id, callback=$callback"

    if ! __validate_vmid_range__ "$start_id" "$end_id"; then
        __api_log__ "ERROR" "Invalid VMID range"
        return 1
    fi

    local failed_count=0
    local success_count=0

    for ((vmid = start_id; vmid <= end_id; vmid++)); do
        if __vm_exists__ "$vmid"; then
            __api_log__ "DEBUG" "Calling $callback for VM $vmid"
            if "$callback" "$vmid" "$@"; then
                ((success_count += 1))
            else
                ((failed_count += 1))
            fi
        fi
    done

    __api_log__ "INFO" "Iteration complete: $success_count succeeded, $failed_count failed"
    # Return success only if no failures
    return "$failed_count"
}

# --- __iterate_cts__ ---------------------------------------------------------
# @function __iterate_cts__
# @description Iterate through CT range and call callback for each.
# @usage __iterate_cts__ <start_id> <end_id> <callback> [callback_args...]
# @param 1 Start CT ID
# @param 2 End CT ID
# @param 3 Callback function name
# @param @ Additional arguments to pass to callback
# @return 0 on success, 1 if any callback fails
#
# Callback function receives: ctid [args...]
__iterate_cts__() {
    local start_id="$1"
    local end_id="$2"
    local callback="$3"
    shift 3

    __api_log__ "INFO" "Iterating CTs: range=$start_id-$end_id, callback=$callback"

    if ! __validate_vmid_range__ "$start_id" "$end_id"; then
        __api_log__ "ERROR" "Invalid CTID range"
        return 1
    fi

    local failed_count=0
    local success_count=0

    for ((ctid = start_id; ctid <= end_id; ctid++)); do
        if __ct_exists__ "$ctid"; then
            __api_log__ "DEBUG" "Calling $callback for CT $ctid"
            if "$callback" "$ctid" "$@"; then
                ((success_count += 1))
            else
                ((failed_count += 1))
            fi
        fi
    done

    __api_log__ "INFO" "Iteration complete: $success_count succeeded, $failed_count failed"
    # Return success only if no failures
    return "$failed_count"
}

###############################################################################
# Example Usage (commented out)
###############################################################################
#
# # Start all VMs in range
# __iterate_vms__ 100 110 __vm_start__
#
# # Stop all CTs with force
# stop_ct_force() {
#   __ct_stop__ "$1" --force
# }
# __iterate_cts__ 200 210 stop_ct_force
#
# # Set memory for all VMs
# set_vm_memory() {
#   local vmid="$1"
#   local memory="$2"
#   __vm_set_config__ "$vmid" --memory "$memory"
# }
# __iterate_vms__ 100 110 set_vm_memory 2048
#

###############################################################################
# Additional VM Operations
###############################################################################

# --- __vm_shutdown__ ---------------------------------------------------------
# @function __vm_shutdown__
# @description Gracefully shutdown a VM (sends ACPI shutdown signal).
# @usage __vm_shutdown__ <vmid> [--timeout <seconds>]
# @param 1 VM ID
# @param --timeout Timeout in seconds (default: 60)
# @return 0 on success, 1 on error
__vm_shutdown__() {
    local vmid="$1"
    shift

    local timeout=60

    __api_log__ "INFO" "Shutting down VM $vmid"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --timeout)
                timeout="$2"
                __api_log__ "DEBUG" "Using timeout: $timeout seconds"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid VMID: $vmid"
        return 1
    fi

    if ! __vm_exists__ "$vmid"; then
        __api_log__ "ERROR" "VM $vmid does not exist"
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    if ! __vm_is_running__ "$vmid"; then
        __api_log__ "INFO" "VM $vmid is already stopped"
        echo "VM $vmid is already stopped" >&2
        return 0
    fi

    local node
    node=$(__get_vm_node__ "$vmid")
    __api_log__ "DEBUG" "Shutting down VM $vmid on node: $node"

    if qm shutdown "$vmid" --node "$node" --timeout "$timeout" 2>/dev/null; then
        __api_log__ "INFO" "Successfully shut down VM $vmid"
        return 0
    else
        __api_log__ "ERROR" "Failed to shutdown VM $vmid"
        echo "Error: Failed to shutdown VM $vmid" >&2
        return 1
    fi
}

# --- __vm_restart__ ----------------------------------------------------------
# @function __vm_restart__
# @description Restart a VM.
# @usage __vm_restart__ <vmid> [--timeout <seconds>]
# @param 1 VM ID
# @param --timeout Shutdown timeout before restart
# @return 0 on success, 1 on error
__vm_restart__() {
    local vmid="$1"
    shift

    __api_log__ "INFO" "Restarting VM $vmid"

    if ! __vm_shutdown__ "$vmid" "$@"; then
        __api_log__ "ERROR" "Failed to shutdown VM $vmid for restart"
        return 1
    fi

    # Wait a moment for clean shutdown
    __api_log__ "DEBUG" "Waiting for clean shutdown"
    sleep 2

    __vm_start__ "$vmid"
}

# --- __vm_suspend__ ----------------------------------------------------------
# @function __vm_suspend__
# @description Suspend a VM (save state to disk).
# @usage __vm_suspend__ <vmid>
# @param 1 VM ID
# @return 0 on success, 1 on error
__vm_suspend__() {
    local vmid="$1"

    __api_log__ "INFO" "Suspending VM $vmid"

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid VMID: $vmid"
        return 1
    fi

    if ! __vm_exists__ "$vmid"; then
        __api_log__ "ERROR" "VM $vmid does not exist"
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    local node
    node=$(__get_vm_node__ "$vmid")

    if qm suspend "$vmid" --node "$node" 2>/dev/null; then
        __api_log__ "INFO" "VM $vmid suspended successfully"
        return 0
    else
        __api_log__ "ERROR" "Failed to suspend VM $vmid"
        echo "Error: Failed to suspend VM $vmid" >&2
        return 1
    fi
}

# --- __vm_resume__ -----------------------------------------------------------
# @function __vm_resume__
# @description Resume a suspended VM.
# @usage __vm_resume__ <vmid>
# @param 1 VM ID
# @return 0 on success, 1 on error
__vm_resume__() {
    local vmid="$1"

    __api_log__ "INFO" "Resuming VM $vmid"

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid VMID: $vmid"
        return 1
    fi

    if ! __vm_exists__ "$vmid"; then
        __api_log__ "ERROR" "VM $vmid does not exist"
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    local node
    node=$(__get_vm_node__ "$vmid")

    if qm resume "$vmid" --node "$node" 2>/dev/null; then
        __api_log__ "INFO" "VM $vmid resumed successfully"
        return 0
    else
        __api_log__ "ERROR" "Failed to resume VM $vmid"
        echo "Error: Failed to resume VM $vmid" >&2
        return 1
    fi
}

# --- __vm_list_all__ ---------------------------------------------------------
# @function __vm_list_all__
# @description List all VMs in the cluster.
# @usage __vm_list_all__ [--running] [--stopped]
# @param --running Only list running VMs
# @param --stopped Only list stopped VMs
# @return Prints VM IDs to stdout, one per line
__vm_list_all__() {
    local filter=""

    __api_log__ "DEBUG" "Listing all VMs with filter: ${1:-<none>}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --running)
                filter="running"
                shift
                ;;
            --stopped)
                filter="stopped"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    local vm_list
    if [[ -n "$filter" ]]; then
        vm_list=$(qm list 2>/dev/null | awk -v status="$filter" 'NR>1 && $3==status {print $1}')
    else
        vm_list=$(qm list 2>/dev/null | awk 'NR>1 {print $1}')
    fi

    local count=$(echo "$vm_list" | grep -c .)
    __api_log__ "DEBUG" "Found $count VMs matching filter: ${filter:-all}"
    echo "$vm_list"
}

# --- __vm_wait_for_status__ --------------------------------------------------
# @function __vm_wait_for_status__
# @description Wait for VM to reach a specific status.
# @usage __vm_wait_for_status__ <vmid> <status> [--timeout <seconds>]
# @param 1 VM ID
# @param 2 Desired status (running, stopped, paused)
# @param --timeout Max seconds to wait (default: 60)
# @return 0 if status reached, 1 on timeout or error
__vm_wait_for_status__() {
    local vmid="$1"
    local desired_status="$2"
    shift 2

    __api_log__ "DEBUG" "Waiting for VM $vmid to reach status: $desired_status"

    local timeout=60
    local interval=2

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --timeout)
                timeout="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid VMID: $vmid"
        return 1
    fi

    if ! __vm_exists__ "$vmid"; then
        __api_log__ "ERROR" "VM $vmid does not exist"
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    local elapsed=0
    while ((elapsed < timeout)); do
        local current_status
        current_status=$(__vm_get_status__ "$vmid" 2>/dev/null)

        if [[ "$current_status" == "$desired_status" ]]; then
            __api_log__ "INFO" "VM $vmid reached status: $desired_status (elapsed: ${elapsed}s)"
            return 0
        fi

        sleep "$interval"
        ((elapsed += interval))
    done

    __api_log__ "ERROR" "Timeout waiting for VM $vmid to reach status $desired_status after ${timeout}s"
    echo "Error: Timeout waiting for VM $vmid to reach status $desired_status" >&2
    return 1
}

###############################################################################
# Additional CT Operations
###############################################################################

# --- __ct_shutdown__ ---------------------------------------------------------
# @function __ct_shutdown__
# @description Gracefully shutdown a CT.
# @usage __ct_shutdown__ <ctid> [--timeout <seconds>]
# @param 1 CT ID
# @param --timeout Timeout in seconds (default: 60)
# @return 0 on success, 1 on error
__ct_shutdown__() {
    local ctid="$1"
    shift

    __api_log__ "INFO" "Shutting down CT $ctid"

    local timeout=60

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --timeout)
                timeout="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid CTID: $ctid"
        return 1
    fi

    if ! __ct_exists__ "$ctid"; then
        __api_log__ "ERROR" "CT $ctid does not exist"
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    if ! __ct_is_running__ "$ctid"; then
        __api_log__ "INFO" "CT $ctid is already stopped"
        echo "CT $ctid is already stopped" >&2
        return 0
    fi

    if pct shutdown "$ctid" --timeout "$timeout" 2>/dev/null; then
        __api_log__ "INFO" "CT $ctid shutdown successfully"
        return 0
    else
        __api_log__ "ERROR" "Failed to shutdown CT $ctid"
        echo "Error: Failed to shutdown CT $ctid" >&2
        return 1
    fi
}

# --- __ct_restart__ ----------------------------------------------------------
# @function __ct_restart__
# @description Restart a CT.
# @usage __ct_restart__ <ctid>
# @param 1 CT ID
# @return 0 on success, 1 on error
__ct_restart__() {
    local ctid="$1"

    __api_log__ "INFO" "Restarting CT $ctid"

    if ! __ct_shutdown__ "$ctid"; then
        __api_log__ "ERROR" "Failed to shutdown CT $ctid for restart"
        return 1
    fi

    __api_log__ "DEBUG" "Waiting for clean shutdown"
    sleep 2

    __ct_start__ "$ctid"
}

# --- __ct_list_all__ ---------------------------------------------------------
# @function __ct_list_all__
# @description List all CTs.
# @usage __ct_list_all__ [--running] [--stopped]
# @param --running Only list running CTs
# @param --stopped Only list stopped CTs
# @return Prints CT IDs to stdout, one per line
__ct_list_all__() {
    local filter=""

    __api_log__ "DEBUG" "Listing all CTs with filter: ${1:-<none>}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --running)
                filter="running"
                shift
                ;;
            --stopped)
                filter="stopped"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    local ct_list
    if [[ -n "$filter" ]]; then
        ct_list=$(pct list 2>/dev/null | awk -v status="$filter" 'NR>1 && $2==status {print $1}')
    else
        ct_list=$(pct list 2>/dev/null | awk 'NR>1 {print $1}')
    fi

    local count=$(echo "$ct_list" | grep -c .)
    __api_log__ "DEBUG" "Found $count CTs matching filter: ${filter:-all}"
    echo "$ct_list"
}

# --- __ct_wait_for_status__ --------------------------------------------------
# @function __ct_wait_for_status__
# @description Wait for CT to reach a specific status.
# @usage __ct_wait_for_status__ <ctid> <status> [--timeout <seconds>]
# @param 1 CT ID
# @param 2 Desired status (running, stopped)
# @param --timeout Max seconds to wait (default: 60)
# @return 0 if status reached, 1 on timeout or error
__ct_wait_for_status__() {
    local ctid="$1"
    local desired_status="$2"
    shift 2

    __api_log__ "DEBUG" "Waiting for CT $ctid to reach status: $desired_status"

    local timeout=60
    local interval=2

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --timeout)
                timeout="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid CTID: $ctid"
        return 1
    fi

    if ! __ct_exists__ "$ctid"; then
        __api_log__ "ERROR" "CT $ctid does not exist"
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    local elapsed=0
    while ((elapsed < timeout)); do
        local current_status
        current_status=$(__ct_get_status__ "$ctid" 2>/dev/null)

        if [[ "$current_status" == "$desired_status" ]]; then
            __api_log__ "INFO" "CT $ctid reached status: $desired_status (elapsed: ${elapsed}s)"
            return 0
        fi

        sleep "$interval"
        ((elapsed += interval))
    done

    __api_log__ "ERROR" "Timeout waiting for CT $ctid to reach status $desired_status after ${timeout}s"
    echo "Error: Timeout waiting for CT $ctid to reach status $desired_status" >&2
    return 1
}

# --- __ct_exec__ -------------------------------------------------------------
# @function __ct_exec__
# @description Execute command inside a CT.
# @usage __ct_exec__ <ctid> <command>
# @param 1 CT ID
# @param 2 Command to execute
# @return Command exit code
__ct_exec__() {
    local ctid="$1"
    local command="$2"

    __api_log__ "DEBUG" "Executing command in CT $ctid: $command"

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid CTID: $ctid"
        return 1
    fi

    if ! __ct_exists__ "$ctid"; then
        __api_log__ "ERROR" "CT $ctid does not exist"
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    if ! __ct_is_running__ "$ctid"; then
        __api_log__ "ERROR" "CT $ctid is not running"
        echo "Error: CT $ctid is not running" >&2
        return 1
    fi

    pct exec "$ctid" -- bash -c "$command"
    local exit_code=$?
    __api_log__ "DEBUG" "Command execution completed with exit code: $exit_code"
    return $exit_code
}

###############################################################################
# Configuration Helpers
###############################################################################

# --- __get_vm_info__ ---------------------------------------------------------
# @function __get_vm_info__
# @description Get comprehensive VM information.
# @usage __get_vm_info__ <vmid>
# @param 1 VM ID
# @return Prints VM info in key=value format
__get_vm_info__() {
    local vmid="$1"

    __api_log__ "DEBUG" "Getting info for VM $vmid"

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid VMID: $vmid"
        return 1
    fi

    if ! __vm_exists__ "$vmid"; then
        __api_log__ "ERROR" "VM $vmid does not exist"
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    local node
    node=$(__get_vm_node__ "$vmid")

    local status
    status=$(__vm_get_status__ "$vmid")

    echo "vmid=$vmid"
    echo "node=$node"
    echo "status=$status"
    echo "memory=$(__vm_get_config__ "$vmid" "memory")"
    echo "cores=$(__vm_get_config__ "$vmid" "cores")"
    echo "sockets=$(__vm_get_config__ "$vmid" "sockets")"

    __api_log__ "DEBUG" "Retrieved info for VM $vmid: node=$node, status=$status"
}

# --- __get_ct_info__ ---------------------------------------------------------
# @function __get_ct_info__
# @description Get comprehensive CT information.
# @usage __get_ct_info__ <ctid>
# @param 1 CT ID
# @return Prints CT info in key=value format
__get_ct_info__() {
    local ctid="$1"

    __api_log__ "DEBUG" "Getting info for CT $ctid"

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid CTID: $ctid"
        return 1
    fi

    if ! __ct_exists__ "$ctid"; then
        __api_log__ "ERROR" "CT $ctid does not exist"
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    local status
    status=$(__ct_get_status__ "$ctid")

    echo "ctid=$ctid"
    echo "status=$status"
    echo "memory=$(__ct_get_config__ "$ctid" "memory")"
    echo "cores=$(__ct_get_config__ "$ctid" "cores")"
    echo "hostname=$(__ct_get_config__ "$ctid" "hostname")"

    __api_log__ "DEBUG" "Retrieved info for CT $ctid: status=$status"
}

###############################################################################
# Remote Execution Helpers
###############################################################################

# --- __node_exec__ -----------------------------------------------------------
# @function __node_exec__
# @description Execute a command on a specific node (local or remote via SSH).
#              Automatically handles local vs remote execution and cluster context.
# @usage __node_exec__ <node> <command>
# @param 1 Node name (from __get_vm_node__ or __resolve_node_name__)
# @param 2 Command to execute
# @return Command exit code, stdout/stderr passed through
# @example __node_exec__ "pve02" "qm destroy 100 --purge"
# @example __node_exec__ "$(__get_vm_node__ 100)" "qm stop 100"
__node_exec__() {
    local node="$1"
    local command="$2"

    __api_log__ "DEBUG" "Executing on node $node: $command"

    if [[ -z "$node" || -z "$command" ]]; then
        __api_log__ "ERROR" "Missing node or command parameter"
        echo "Error: __node_exec__ requires node and command parameters" >&2
        return 1
    fi

    local local_hostname
    local_hostname=$(hostname)

    # If target node is local, execute directly
    if [[ "$node" == "$local_hostname" ]]; then
        __api_log__ "DEBUG" "Executing locally on $node"
        eval "$command"
        return $?
    fi

    # Remote execution via SSH
    __api_log__ "DEBUG" "Executing remotely on $node via SSH"
    ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@${node}" "$command"
    return $?
}

# --- __vm_node_exec__ --------------------------------------------------------
# @function __vm_node_exec__
# @description Execute a command on the node where a VM is located.
#              Wrapper around __node_exec__ that automatically finds the VM's node.
# @usage __vm_node_exec__ <vmid> <command>
# @param 1 VM ID
# @param 2 Command to execute (can use {vmid} placeholder)
# @return Command exit code
# @example __vm_node_exec__ 100 "qm destroy {vmid} --purge"
# @example __vm_node_exec__ 100 "qm set {vmid} --protection 0"
__vm_node_exec__() {
    local vmid="$1"
    local command="$2"

    __api_log__ "DEBUG" "Executing command for VM $vmid: $command"

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid VMID: $vmid"
        return 1
    fi

    if ! __vm_exists__ "$vmid"; then
        __api_log__ "ERROR" "VM $vmid does not exist"
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    local node
    node=$(__get_vm_node__ "$vmid")

    if [[ -z "$node" ]]; then
        __api_log__ "ERROR" "Could not determine node for VM $vmid"
        echo "Error: Could not determine node for VM $vmid" >&2
        return 1
    fi

    # Replace {vmid} placeholder in command
    command="${command//\{vmid\}/$vmid}"

    __api_log__ "DEBUG" "Executing on node $node for VM $vmid"

    __node_exec__ "$node" "$command"
}

# --- __ct_node_exec__ --------------------------------------------------------
# @function __ct_node_exec__
# @description Execute a command on the node where a CT is located.
#              Wrapper around __node_exec__ that automatically finds the CT's node.
# @usage __ct_node_exec__ <ctid> <command>
# @param 1 CT ID
# @param 2 Command to execute (can use {ctid} placeholder)
# @return Command exit code
# @example __ct_node_exec__ 100 "pct destroy {ctid} --purge"
# @example __ct_node_exec__ 100 "pct set {ctid} --protection 0"
__ct_node_exec__() {
    local ctid="$1"
    local command="$2"

    __api_log__ "DEBUG" "Executing command for CT $ctid: $command"

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid CTID: $ctid"
        return 1
    fi

    if ! __ct_exists__ "$ctid"; then
        __api_log__ "ERROR" "CT $ctid does not exist"
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    local node
    node=$(__get_vm_node__ "$ctid") # Works for CTs too

    if [[ -z "$node" ]]; then
        __api_log__ "ERROR" "Could not determine node for CT $ctid"
        echo "Error: Could not determine node for CT $ctid" >&2
        return 1
    fi

    # Replace {ctid} placeholder in command
    command="${command//\{ctid\}/$ctid}"

    __api_log__ "DEBUG" "Executing on node $node for CT $ctid"
    __node_exec__ "$node" "$command"
}

# --- __pve_exec__ ------------------------------------------------------------
# @function __pve_exec__
# @description Generic Proxmox command executor on correct node.
#              Detects command type (qm/pct/pvesh) and routes to appropriate node.
# @usage __pve_exec__ <vmid_or_ctid> <command>
# @param 1 VM/CT ID
# @param 2 Full command (qm/pct/pvesh command)
# @return Command exit code
# @example __pve_exec__ 100 "qm destroy 100 --purge --skiplock"
# @example __pve_exec__ 200 "pct clone 200 201"
__pve_exec__() {
    local id="$1"
    local command="$2"

    __api_log__ "DEBUG" "Executing Proxmox command for ID $id: $command"

    if ! __validate_numeric__ "$id" "VM/CT ID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid VM/CT ID: $id"
        return 1
    fi

    # Determine if it's a VM or CT
    if __vm_exists__ "$id"; then
        __api_log__ "DEBUG" "ID $id is a VM, routing to __vm_node_exec__"
        __vm_node_exec__ "$id" "$command"
    elif __ct_exists__ "$id"; then
        __api_log__ "DEBUG" "ID $id is a CT, routing to __ct_node_exec__"
        __ct_node_exec__ "$id" "$command"
    else
        __api_log__ "ERROR" "VM/CT $id does not exist"
        echo "Error: VM/CT $id does not exist" >&2
        return 1
    fi
}

# --- __ct_set_cpu__ ----------------------------------------------------------
# @function __ct_set_cpu__
# @description Set CPU configuration for a container
# @usage __ct_set_cpu__ <ctid> <cores> [sockets]
# @param 1 Container ID
# @param 2 Number of CPU cores
# @param 3 Number of sockets (optional, default: 1)
# @return 0 on success, 1 on error
__ct_set_cpu__() {
    local ctid="$1"
    local cores="$2"
    local sockets="${3:-1}"

    __api_log__ "INFO" "Setting CPU for CT $ctid: cores=$cores, sockets=$sockets"

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid CTID: $ctid"
        return 1
    fi

    if pct set "$ctid" --cores "$cores" --sockets "$sockets" 2>/dev/null; then
        __api_log__ "INFO" "Successfully set CPU for CT $ctid"
        return 0
    else
        __api_log__ "ERROR" "Failed to set CPU for CT $ctid"
        return 1
    fi
}

# --- __ct_set_memory__ -------------------------------------------------------
# @function __ct_set_memory__
# @description Set memory configuration for a container
# @usage __ct_set_memory__ <ctid> <memory_mb> [swap_mb]
# @param 1 Container ID
# @param 2 Memory in MB
# @param 3 Swap in MB (optional)
# @return 0 on success, 1 on error
__ct_set_memory__() {
    local ctid="$1"
    local memory="$2"
    local swap="${3:-}"

    __api_log__ "INFO" "Setting memory for CT $ctid: memory=${memory}MB, swap=${swap}MB"

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid CTID: $ctid"
        return 1
    fi

    local cmd="pct set $ctid --memory $memory"
    [[ -n "$swap" ]] && cmd+=" --swap $swap"

    if eval "$cmd" 2>/dev/null; then
        __api_log__ "INFO" "Successfully set memory for CT $ctid"
        return 0
    else
        __api_log__ "ERROR" "Failed to set memory for CT $ctid"
        return 1
    fi
}

# --- __ct_set_onboot__ -------------------------------------------------------
# @function __ct_set_onboot__
# @description Set container to start at boot
# @usage __ct_set_onboot__ <ctid> <value>
# @param 1 Container ID
# @param 2 Value (0 or 1)
# @return 0 on success, 1 on error
__ct_set_onboot__() {
    local ctid="$1"
    local value="$2"

    __api_log__ "INFO" "Setting onboot for CT $ctid: $value"

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid CTID: $ctid"
        return 1
    fi

    if pct set "$ctid" --onboot "$value" 2>/dev/null; then
        __api_log__ "INFO" "Successfully set onboot for CT $ctid"
        return 0
    else
        __api_log__ "ERROR" "Failed to set onboot for CT $ctid"
        return 1
    fi
}

# --- __ct_unlock__ -----------------------------------------------------------
# @function __ct_unlock__
# @description Unlock a container
# @usage __ct_unlock__ <ctid>
# @param 1 Container ID
# @return 0 on success, 1 on error
__ct_unlock__() {
    local ctid="$1"

    __api_log__ "INFO" "Unlocking CT $ctid"

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid CTID: $ctid"
        return 1
    fi

    if pct unlock "$ctid" 2>/dev/null; then
        __api_log__ "INFO" "Successfully unlocked CT $ctid"
        return 0
    else
        __api_log__ "ERROR" "Failed to unlock CT $ctid"
        return 1
    fi
}

# --- __ct_delete__ -----------------------------------------------------------
# @function __ct_delete__
# @description Delete/destroy a container
# @usage __ct_delete__ <ctid>
# @param 1 Container ID
# @return 0 on success, 1 on error
__ct_delete__() {
    local ctid="$1"

    __api_log__ "INFO" "Deleting CT $ctid"

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid CTID: $ctid"
        return 1
    fi

    if pct destroy "$ctid" 2>/dev/null; then
        __api_log__ "INFO" "Successfully deleted CT $ctid"
        return 0
    else
        __api_log__ "ERROR" "Failed to delete CT $ctid"
        return 1
    fi
}

# --- __ct_set_protection__ ---------------------------------------------------
# @function __ct_set_protection__
# @description Set protection flag for a container
# @usage __ct_set_protection__ <ctid> <value>
# @param 1 Container ID
# @param 2 Value (0 or 1)
# @return 0 on success, 1 on error
__ct_set_protection__() {
    local ctid="$1"
    local value="$2"

    __api_log__ "INFO" "Setting protection for CT $ctid: $value"

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid CTID: $ctid"
        return 1
    fi

    if pct set "$ctid" --protection "$value" 2>/dev/null; then
        __api_log__ "INFO" "Successfully set protection for CT $ctid"
        return 0
    else
        __api_log__ "ERROR" "Failed to set protection for CT $ctid"
        return 1
    fi
}

# --- __vm_unlock__ -----------------------------------------------------------
# @function __vm_unlock__
# @description Unlock a VM
# @usage __vm_unlock__ <vmid>
# @param 1 VM ID
# @return 0 on success, 1 on error
__vm_unlock__() {
    local vmid="$1"

    __api_log__ "INFO" "Unlocking VM $vmid"

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid VMID: $vmid"
        return 1
    fi

    if qm unlock "$vmid" 2>/dev/null; then
        __api_log__ "INFO" "Successfully unlocked VM $vmid"
        return 0
    else
        __api_log__ "ERROR" "Failed to unlock VM $vmid"
        return 1
    fi
}

# --- __vm_delete__ -----------------------------------------------------------
# @function __vm_delete__
# @description Delete/destroy a VM
# @usage __vm_delete__ <vmid>
# @param 1 VM ID
# @return 0 on success, 1 on error
__vm_delete__() {
    local vmid="$1"

    __api_log__ "INFO" "Deleting VM $vmid"

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid VMID: $vmid"
        return 1
    fi

    if qm destroy "$vmid" 2>/dev/null; then
        __api_log__ "INFO" "Successfully deleted VM $vmid"
        return 0
    else
        __api_log__ "ERROR" "Failed to delete VM $vmid"
        return 1
    fi
}

# --- __vm_set_protection__ ---------------------------------------------------
# @function __vm_set_protection__
# @description Set protection flag for a VM
# @usage __vm_set_protection__ <vmid> <value>
# @param 1 VM ID
# @param 2 Value (0 or 1)
# @return 0 on success, 1 on error
__vm_set_protection__() {
    local vmid="$1"
    local value="$2"

    __api_log__ "INFO" "Setting protection for VM $vmid: $value"

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid VMID: $vmid"
        return 1
    fi

    local node
    node=$(__get_vm_node__ "$vmid")

    if qm set "$vmid" --node "$node" --protection "$value" 2>/dev/null; then
        __api_log__ "INFO" "Successfully set protection for VM $vmid"
        return 0
    else
        __api_log__ "ERROR" "Failed to set protection for VM $vmid"
        return 1
    fi
}

# --- __vm_reset__ ------------------------------------------------------------
# @function __vm_reset__
# @description Reset/reboot a VM
# @usage __vm_reset__ <vmid>
# @param 1 VM ID
# @return 0 on success, 1 on error
__vm_reset__() {
    local vmid="$1"

    __api_log__ "INFO" "Resetting VM $vmid"

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid VMID: $vmid"
        return 1
    fi

    if qm reset "$vmid" 2>/dev/null; then
        __api_log__ "INFO" "Successfully reset VM $vmid"
        return 0
    else
        __api_log__ "ERROR" "Failed to reset VM $vmid"
        return 1
    fi
}

# --- __ct_set_dns__ ----------------------------------------------------------
# @function __ct_set_dns__
# @description Set DNS servers for a container
# @usage __ct_set_dns__ <ctid> <dns_servers>
# @param 1 Container ID
# @param 2 DNS servers (space or comma separated)
# @return 0 on success, 1 on error
__ct_set_dns__() {
    local ctid="$1"
    local dns="$2"

    __api_log__ "INFO" "Setting DNS for CT $ctid: $dns"

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid CTID: $ctid"
        return 1
    fi

    if pct set "$ctid" --nameserver "$dns" 2>/dev/null; then
        __api_log__ "INFO" "Successfully set DNS for CT $ctid"
        return 0
    else
        __api_log__ "ERROR" "Failed to set DNS for CT $ctid"
        return 1
    fi
}

# --- __ct_set_network__ ------------------------------------------------------
# @function __ct_set_network__
# @description Set network configuration for a container
# @usage __ct_set_network__ <ctid> <net_config>
# @param 1 Container ID
# @param 2 Network config string (e.g., "name=eth0,bridge=vmbr0,ip=192.168.1.10/24,gw=192.168.1.1")
# @return 0 on success, 1 on error
__ct_set_network__() {
    local ctid="$1"
    local net_config="$2"

    __api_log__ "INFO" "Setting network for CT $ctid: $net_config"

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid CTID: $ctid"
        return 1
    fi

    if pct set "$ctid" --net0 "$net_config" 2>/dev/null; then
        __api_log__ "INFO" "Successfully set network for CT $ctid"
        return 0
    else
        __api_log__ "ERROR" "Failed to set network for CT $ctid"
        return 1
    fi
}

# --- __ct_change_password__ --------------------------------------------------
# @function __ct_change_password__
# @description Change password for a user in a container
# @usage __ct_change_password__ <ctid> <username> <password>
# @param 1 Container ID
# @param 2 Username
# @param 3 New password
# @return 0 on success, 1 on error
__ct_change_password__() {
    local ctid="$1"
    local username="$2"
    local password="$3"

    __api_log__ "INFO" "Changing password for user $username in CT $ctid"

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid CTID: $ctid"
        return 1
    fi

    if __ct_exec__ "$ctid" "echo '${username}:${password}' | chpasswd" 2>/dev/null; then
        __api_log__ "INFO" "Successfully changed password for user $username in CT $ctid"
        return 0
    else
        __api_log__ "ERROR" "Failed to change password for user $username in CT $ctid"
        return 1
    fi
}

# --- __ct_add_ssh_key__ ------------------------------------------------------
# @function __ct_add_ssh_key__
# @description Add SSH key to root's authorized_keys in a container
# @usage __ct_add_ssh_key__ <ctid> <ssh_key>
# @param 1 Container ID
# @param 2 SSH public key
# @return 0 on success, 1 on error
__ct_add_ssh_key__() {
    local ctid="$1"
    local ssh_key="$2"

    __api_log__ "INFO" "Adding SSH key to CT $ctid"

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid CTID: $ctid"
        return 1
    fi

    if __ct_exec__ "$ctid" "mkdir -p /root/.ssh && chmod 700 /root/.ssh && echo '$ssh_key' >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys" 2>/dev/null; then
        __api_log__ "INFO" "Successfully added SSH key to CT $ctid"
        return 0
    else
        __api_log__ "ERROR" "Failed to add SSH key to CT $ctid"
        return 1
    fi
}

# --- __ct_resize_disk__ ------------------------------------------------------
# @function __ct_resize_disk__
# @description Resize a container disk
# @usage __ct_resize_disk__ <ctid> <disk_id> <size>
# @param 1 Container ID
# @param 2 Disk identifier (e.g., "rootfs", "mp0")
# @param 3 New size (e.g., "+5G", "20G")
# @return 0 on success, 1 on error
__ct_resize_disk__() {
    local ctid="$1"
    local disk="$2"
    local size="$3"

    __api_log__ "INFO" "Resizing disk $disk for CT $ctid to $size"

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid CTID: $ctid"
        return 1
    fi

    if pct resize "$ctid" "$disk" "$size" 2>/dev/null; then
        __api_log__ "INFO" "Successfully resized disk $disk for CT $ctid"
        return 0
    else
        __api_log__ "ERROR" "Failed to resize disk $disk for CT $ctid"
        return 1
    fi
}

# --- __vm_resize_disk__ ------------------------------------------------------
# @function __vm_resize_disk__
# @description Resize a VM disk
# @usage __vm_resize_disk__ <vmid> <disk> <size>
# @param 1 VM ID
# @param 2 Disk identifier (e.g., "scsi0", "ide0")
# @param 3 Size increment (e.g., "+5G")
# @return 0 on success, 1 on error
__vm_resize_disk__() {
    local vmid="$1"
    local disk="$2"
    local size="$3"

    __api_log__ "INFO" "Resizing disk $disk for VM $vmid by $size"

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid VMID: $vmid"
        return 1
    fi

    if qm resize "$vmid" "$disk" "$size" 2>/dev/null; then
        __api_log__ "INFO" "Successfully resized disk $disk for VM $vmid"
        return 0
    else
        __api_log__ "ERROR" "Failed to resize disk $disk for VM $vmid"
        return 1
    fi
}

# --- __vm_backup__ -----------------------------------------------------------
# @function __vm_backup__
# @description Backup a VM
# @usage __vm_backup__ <vmid> <storage> <mode>
# @param 1 VM ID
# @param 2 Storage location for backup
# @param 3 Backup mode (snapshot, suspend, stop)
# @return 0 on success, 1 on error
__vm_backup__() {
    local vmid="$1"
    local storage="$2"
    local mode="$3"

    __api_log__ "INFO" "Backing up VM $vmid to $storage with mode $mode"

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid VMID: $vmid"
        return 1
    fi

    if vzdump "$vmid" --storage "$storage" --mode "$mode" 2>/dev/null; then
        __api_log__ "INFO" "Successfully backed up VM $vmid"
        return 0
    else
        __api_log__ "ERROR" "Failed to backup VM $vmid"
        return 1
    fi
}

# --- __ct_change_storage__ ---------------------------------------------------
# @function __ct_change_storage__
# @description Change storage configuration for container volumes
# @usage __ct_change_storage__ <ctid> <current_storage> <new_storage>
# @param 1 Container ID
# @param 2 Current storage
# @param 3 New storage
# @return 0 on success, 1 on error
# @note This is a complex operation that may require moving volumes
__ct_change_storage__() {
    local ctid="$1"
    local current_storage="$2"
    local new_storage="$3"

    __api_log__ "INFO" "Changing storage for CT $ctid from $current_storage to $new_storage"

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid CTID: $ctid"
        return 1
    fi

    # This is a placeholder - actual implementation would need to:
    # 1. Get all volumes from current storage
    # 2. Move each volume to new storage using pct move-volume
    # For now, log a warning
    __api_log__ "WARN" "Storage change for CT $ctid requires manual volume migration"
    echo "Warning: Storage change requires manual intervention" >&2
    return 1
}

# --- __ct_move_volume__ ------------------------------------------------------
# @function __ct_move_volume__
# @description Move a container volume to different storage
# @usage __ct_move_volume__ <ctid> <volume> <target_storage>
# @param 1 Container ID
# @param 2 Volume identifier (e.g., "rootfs", "mp0")
# @param 3 Target storage
# @return 0 on success, 1 on error
__ct_move_volume__() {
    local ctid="$1"
    local volume="$2"
    local target="$3"

    __api_log__ "INFO" "Moving volume $volume for CT $ctid to $target"

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid CTID: $ctid"
        return 1
    fi

    if pct move-volume "$ctid" "$volume" "$target" --delete 2>/dev/null; then
        __api_log__ "INFO" "Successfully moved volume $volume for CT $ctid to $target"
        return 0
    else
        __api_log__ "ERROR" "Failed to move volume $volume for CT $ctid to $target"
        return 1
    fi
}

# --- __ct_update_packages__ --------------------------------------------------
# @function __ct_update_packages__
# @description Update packages in a container
# @usage __ct_update_packages__ <ctid>
# @param 1 Container ID
# @return 0 on success, 1 on error
__ct_update_packages__() {
    local ctid="$1"

    __api_log__ "INFO" "Updating packages for CT $ctid"

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid CTID: $ctid"
        return 1
    fi

    # Try apt-get first (Debian/Ubuntu), then apk (Alpine), then dnf (Fedora)
    if __ct_exec__ "$ctid" "which apt-get >/dev/null 2>&1 && apt-get update && apt-get upgrade -y" 2>/dev/null; then
        __api_log__ "INFO" "Successfully updated packages (apt) for CT $ctid"
        return 0
    elif __ct_exec__ "$ctid" "which apk >/dev/null 2>&1 && apk update && apk upgrade" 2>/dev/null; then
        __api_log__ "INFO" "Successfully updated packages (apk) for CT $ctid"
        return 0
    elif __ct_exec__ "$ctid" "which dnf >/dev/null 2>&1 && dnf upgrade -y" 2>/dev/null; then
        __api_log__ "INFO" "Successfully updated packages (dnf) for CT $ctid"
        return 0
    else
        __api_log__ "ERROR" "Failed to update packages for CT $ctid"
        return 1
    fi
}

# --- __ct_add_ip_to_note__ ---------------------------------------------------
# @function __ct_add_ip_to_note__
# @description Add container IP address to its notes/description
# @usage __ct_add_ip_to_note__ <ctid>
# @param 1 Container ID
# @return 0 on success, 1 on error
__ct_add_ip_to_note__() {
    local ctid="$1"

    __api_log__ "INFO" "Adding IP to note for CT $ctid"

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid CTID: $ctid"
        return 1
    fi

    local ip
    ip=$(__ct_get_config__ "$ctid" "net0" | grep -oP 'ip=\K[^/,]+' || echo "")

    if [[ -z "$ip" ]]; then
        __api_log__ "WARN" "No IP found for CT $ctid"
        return 1
    fi

    local current_note
    current_note=$(__ct_get_config__ "$ctid" "description" 2>/dev/null || echo "")
    local new_note="IP: $ip"

    if [[ -n "$current_note" ]]; then
        new_note="${current_note}
${new_note}"
    fi

    if pct set "$ctid" --description "$new_note" 2>/dev/null; then
        __api_log__ "INFO" "Successfully added IP to note for CT $ctid"
        return 0
    else
        __api_log__ "ERROR" "Failed to add IP to note for CT $ctid"
        return 1
    fi
}

# --- __vm_add_ip_to_note__ ---------------------------------------------------
# @function __vm_add_ip_to_note__
# @description Add VM IP address to its notes/description
# @usage __vm_add_ip_to_note__ <vmid>
# @param 1 VM ID
# @return 0 on success, 1 on error
__vm_add_ip_to_note__() {
    local vmid="$1"

    __api_log__ "INFO" "Adding IP to note for VM $vmid"

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        __api_log__ "ERROR" "Invalid VMID: $vmid"
        return 1
    fi

    local ip
    ip=$(qm guest cmd "$vmid" network-get-interfaces 2>/dev/null | jq -r '.[].["ip-addresses"][]? | select(.["ip-address-type"] == "ipv4") | .["ip-address"]' | grep -v "^127\." | head -1 || echo "")

    if [[ -z "$ip" ]]; then
        __api_log__ "WARN" "No IP found for VM $vmid (guest agent may not be running)"
        return 1
    fi

    local node
    node=$(__get_vm_node__ "$vmid")

    local current_note
    current_note=$(__vm_get_config__ "$vmid" "description" 2>/dev/null || echo "")
    local new_note="IP: $ip"

    if [[ -n "$current_note" ]]; then
        new_note="$current_note\n$new_note"
    fi

    if qm set "$vmid" --node "$node" --description "$new_note" 2>/dev/null; then
        __api_log__ "INFO" "Successfully added IP to note for VM $vmid"
        return 0
    else
        __api_log__ "ERROR" "Failed to add IP to note for VM $vmid"
        return 1
    fi
}

###############################################################################
# Script notes:
###############################################################################
# Last checked: YYYY-MM-DD
#
# Changes:
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# -
#
# Known issues:
# -
#

