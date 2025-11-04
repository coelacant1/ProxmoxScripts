#!/bin/bash
#
# ProxmoxAPI.sh
#
# Wrapper functions for common Proxmox operations with built-in error handling,
# validation, and cluster-awareness. Reduces code duplication and provides
# consistent patterns for VM/CT operations.
#
# Usage:
#   source "${UTILITYPATH}/ProxmoxAPI.sh"
#
# Features:
#   - Cluster-aware operations (automatic node detection)
#   - Built-in error handling and validation
#   - Consistent return codes and error messages
#   - Testable and mockable functions
#   - State management helpers
#
# Function Index:
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
#

set -euo pipefail

# Source dependencies
source "${UTILITYPATH}/ArgumentParser.sh"
source "${UTILITYPATH}/Queries.sh"

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

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        return 1
    fi

    # Use __get_vm_node__ to check existence
    local node
    node=$(__get_vm_node__ "$vmid" 2>/dev/null)

    [[ -n "$node" ]]
}

# --- __vm_get_status__ -------------------------------------------------------
# @function __vm_get_status__
# @description Get VM status (running, stopped, paused, etc).
# @usage __vm_get_status__ <vmid>
# @param 1 VM ID
# @return Prints status to stdout, returns 1 on error
__vm_get_status__() {
    local vmid="$1"

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        return 1
    fi

    if ! __vm_exists__ "$vmid"; then
        echo "Error: VM $vmid does not exist" >&2
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

    status=$(__vm_get_status__ "$vmid" 2>/dev/null) || return 1
    [[ "$status" == "running" ]]
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

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        return 1
    fi

    if ! __vm_exists__ "$vmid"; then
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    # Check if already running
    if __vm_is_running__ "$vmid"; then
        echo "VM $vmid is already running" >&2
        return 0
    fi

    local node
    node=$(__get_vm_node__ "$vmid")

    if qm start "$vmid" --node "$node" "$@" 2>/dev/null; then
        return 0
    else
        echo "Error: Failed to start VM $vmid on node $node" >&2
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

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --timeout)
                timeout="$2"
                shift 2
                ;;
            --force)
                force=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        return 1
    fi

    if ! __vm_exists__ "$vmid"; then
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    # Check if already stopped
    if ! __vm_is_running__ "$vmid"; then
        echo "VM $vmid is already stopped" >&2
        return 0
    fi

    local node
    node=$(__get_vm_node__ "$vmid")

    local cmd="qm stop \"$vmid\" --node \"$node\""
    [[ -n "$timeout" ]] && cmd+=" --timeout \"$timeout\""
    [[ "$force" == true ]] && cmd+=" --force"

    if eval "$cmd" 2>/dev/null; then
        return 0
    else
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

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        return 1
    fi

    if ! __vm_exists__ "$vmid"; then
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    local node
    node=$(__get_vm_node__ "$vmid")

    if qm set "$vmid" --node "$node" "$@" 2>/dev/null; then
        return 0
    else
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

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        return 1
    fi

    if ! __vm_exists__ "$vmid"; then
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    local node
    node=$(__get_vm_node__ "$vmid")

    qm config "$vmid" --node "$node" 2>/dev/null | grep "^${param}:" | cut -d' ' -f2-
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

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        return 1
    fi

    pct config "$ctid" &>/dev/null
}

# --- __ct_get_status__ -------------------------------------------------------
# @function __ct_get_status__
# @description Get CT status.
# @usage __ct_get_status__ <ctid>
# @param 1 CT ID
# @return Prints status to stdout, returns 1 on error
__ct_get_status__() {
    local ctid="$1"

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        return 1
    fi

    if ! __ct_exists__ "$ctid"; then
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    pct status "$ctid" 2>/dev/null | awk '/^status:/ {print $2}'
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

    status=$(__ct_get_status__ "$ctid" 2>/dev/null) || return 1
    [[ "$status" == "running" ]]
}

# --- __ct_start__ ------------------------------------------------------------
# @function __ct_start__
# @description Start a CT.
# @usage __ct_start__ <ctid>
# @param 1 CT ID
# @return 0 on success, 1 on error
__ct_start__() {
    local ctid="$1"

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        return 1
    fi

    if ! __ct_exists__ "$ctid"; then
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    if __ct_is_running__ "$ctid"; then
        echo "CT $ctid is already running" >&2
        return 0
    fi

    if pct start "$ctid" 2>/dev/null; then
        return 0
    else
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

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                force=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        return 1
    fi

    if ! __ct_exists__ "$ctid"; then
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    if ! __ct_is_running__ "$ctid"; then
        echo "CT $ctid is already stopped" >&2
        return 0
    fi

    local cmd="pct stop \"$ctid\""
    [[ "$force" == true ]] && cmd+=" --force"

    if eval "$cmd" 2>/dev/null; then
        return 0
    else
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

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        return 1
    fi

    if ! __ct_exists__ "$ctid"; then
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    if pct set "$ctid" "$@" 2>/dev/null; then
        return 0
    else
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

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        return 1
    fi

    if ! __ct_exists__ "$ctid"; then
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    pct config "$ctid" 2>/dev/null | grep "^${param}:" | cut -d' ' -f2-
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

    if ! __validate_vmid_range__ "$start_id" "$end_id"; then
        return 1
    fi

    local failed_count=0
    local success_count=0

    for ((vmid=start_id; vmid<=end_id; vmid++)); do
        if __vm_exists__ "$vmid"; then
            if "$callback" "$vmid" "$@"; then
                ((success_count++))
            else
                ((failed_count++))
            fi
        fi
    done

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

    if ! __validate_vmid_range__ "$start_id" "$end_id"; then
        return 1
    fi

    local failed_count=0
    local success_count=0

    for ((ctid=start_id; ctid<=end_id; ctid++)); do
        if __ct_exists__ "$ctid"; then
            if "$callback" "$ctid" "$@"; then
                ((success_count++))
            else
                ((failed_count++))
            fi
        fi
    done

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
        return 1
    fi

    if ! __vm_exists__ "$vmid"; then
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    if ! __vm_is_running__ "$vmid"; then
        echo "VM $vmid is already stopped" >&2
        return 0
    fi

    local node
    node=$(__get_vm_node__ "$vmid")

    if qm shutdown "$vmid" --node "$node" --timeout "$timeout" 2>/dev/null; then
        return 0
    else
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

    if ! __vm_shutdown__ "$vmid" "$@"; then
        return 1
    fi

    # Wait a moment for clean shutdown
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

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        return 1
    fi

    if ! __vm_exists__ "$vmid"; then
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    local node
    node=$(__get_vm_node__ "$vmid")

    if qm suspend "$vmid" --node "$node" 2>/dev/null; then
        return 0
    else
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

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        return 1
    fi

    if ! __vm_exists__ "$vmid"; then
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    local node
    node=$(__get_vm_node__ "$vmid")

    if qm resume "$vmid" --node "$node" 2>/dev/null; then
        return 0
    else
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

    if [[ -n "$filter" ]]; then
        qm list 2>/dev/null | awk -v status="$filter" 'NR>1 && $3==status {print $1}'
    else
        qm list 2>/dev/null | awk 'NR>1 {print $1}'
    fi
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
        return 1
    fi

    if ! __vm_exists__ "$vmid"; then
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    local elapsed=0
    while (( elapsed < timeout )); do
        local current_status
        current_status=$(__vm_get_status__ "$vmid" 2>/dev/null)

        if [[ "$current_status" == "$desired_status" ]]; then
            return 0
        fi

        sleep "$interval"
        ((elapsed += interval))
    done

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
        return 1
    fi

    if ! __ct_exists__ "$ctid"; then
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    if ! __ct_is_running__ "$ctid"; then
        echo "CT $ctid is already stopped" >&2
        return 0
    fi

    if pct shutdown "$ctid" --timeout "$timeout" 2>/dev/null; then
        return 0
    else
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

    if ! __ct_shutdown__ "$ctid"; then
        return 1
    fi

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

    if [[ -n "$filter" ]]; then
        pct list 2>/dev/null | awk -v status="$filter" 'NR>1 && $2==status {print $1}'
    else
        pct list 2>/dev/null | awk 'NR>1 {print $1}'
    fi
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
        return 1
    fi

    if ! __ct_exists__ "$ctid"; then
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    local elapsed=0
    while (( elapsed < timeout )); do
        local current_status
        current_status=$(__ct_get_status__ "$ctid" 2>/dev/null)

        if [[ "$current_status" == "$desired_status" ]]; then
            return 0
        fi

        sleep "$interval"
        ((elapsed += interval))
    done

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

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        return 1
    fi

    if ! __ct_exists__ "$ctid"; then
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    if ! __ct_is_running__ "$ctid"; then
        echo "Error: CT $ctid is not running" >&2
        return 1
    fi

    pct exec "$ctid" -- bash -c "$command"
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

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        return 1
    fi

    if ! __vm_exists__ "$vmid"; then
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
}

# --- __get_ct_info__ ---------------------------------------------------------
# @function __get_ct_info__
# @description Get comprehensive CT information.
# @usage __get_ct_info__ <ctid>
# @param 1 CT ID
# @return Prints CT info in key=value format
__get_ct_info__() {
    local ctid="$1"

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        return 1
    fi

    if ! __ct_exists__ "$ctid"; then
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

    if [[ -z "$node" || -z "$command" ]]; then
        echo "Error: __node_exec__ requires node and command parameters" >&2
        return 1
    fi

    local local_hostname
    local_hostname=$(hostname)

    # If target node is local, execute directly
    if [[ "$node" == "$local_hostname" ]]; then
        eval "$command"
        return $?
    fi

    # Remote execution via SSH
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

    if ! __validate_numeric__ "$vmid" "VMID" 2>/dev/null; then
        return 1
    fi

    if ! __vm_exists__ "$vmid"; then
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    local node
    node=$(__get_vm_node__ "$vmid")

    if [[ -z "$node" ]]; then
        echo "Error: Could not determine node for VM $vmid" >&2
        return 1
    fi

    # Replace {vmid} placeholder in command
    command="${command//\{vmid\}/$vmid}"

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

    if ! __validate_numeric__ "$ctid" "CTID" 2>/dev/null; then
        return 1
    fi

    if ! __ct_exists__ "$ctid"; then
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    local node
    node=$(__get_vm_node__ "$ctid")  # Works for CTs too

    if [[ -z "$node" ]]; then
        echo "Error: Could not determine node for CT $ctid" >&2
        return 1
    fi

    # Replace {ctid} placeholder in command
    command="${command//\{ctid\}/$ctid}"

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

    if ! __validate_numeric__ "$id" "VM/CT ID" 2>/dev/null; then
        return 1
    fi

    # Determine if it's a VM or CT
    if __vm_exists__ "$id"; then
        __vm_node_exec__ "$id" "$command"
    elif __ct_exists__ "$id"; then
        __ct_node_exec__ "$id" "$command"
    else
        echo "Error: VM/CT $id does not exist" >&2
        return 1
    fi
}
