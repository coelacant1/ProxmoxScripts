#!/bin/bash
#
# RemoteExecutor.sh
#
# Handles all remote script execution logic including SSH, file transfer,
# and result collection. Supports both password-based (sshpass) and
# SSH key-based authentication.
#
# This utility is sourced by GUI.sh for remote node execution. It expects:
# - REMOTE_TEMP_DIR: Remote temporary directory path
# - REMOTE_TARGETS: Array of target nodes (name:ip format)
# - NODE_PASSWORDS: Associative array of node passwords
# - NODE_USERNAMES: Associative array of node usernames
# - REMOTE_LOG_LEVEL: Log level for remote execution
#
# Function Index:
#   - __remote_cleanup__
#   - __prompt_for_params__
#   - __test_remote_connection__
#   - __ssh_exec__
#   - __scp_exec__
#   - __scp_exec_recursive__
#   - __scp_download__
#   - __execute_on_remote_node__
#   - __execute_remote_script__
#

# Conditionally source utilities if available
if [[ -f "${UTILITYPATH}/Communication.sh" ]]; then
    # shellcheck source=Utilities/Communication.sh
    source "${UTILITYPATH}/Communication.sh"
fi

if [[ -f "${UTILITYPATH}/Colors.sh" ]]; then
    # shellcheck source=Utilities/Colors.sh
    source "${UTILITYPATH}/Colors.sh"
fi

if [[ -f "${UTILITYPATH}/Logger.sh" ]]; then
    # shellcheck source=Utilities/Logger.sh
    source "${UTILITYPATH}/Logger.sh"
fi

# Global flag for interrupt
REMOTE_INTERRUPTED=0

# Authentication mode: "password" or "key"
# Can be set globally or per-node
USE_SSH_KEYS="${USE_SSH_KEYS:-false}"

# Cleanup function for Ctrl+C interrupt
__remote_cleanup__() {
    # Set flag to break out of loop
    REMOTE_INTERRUPTED=1

    echo
    echo
    __warn__ "Interrupted by user (Ctrl+C)"

    # Stop any running spinner
    __stop_spin__ 2>/dev/null || true

    # Kill any background SSH processes (more aggressive)
    killall -9 sshpass 2>/dev/null || true
    killall -9 ssh 2>/dev/null || true
    pkill -9 -P $$ sshpass 2>/dev/null || true
    pkill -9 -P $$ ssh 2>/dev/null || true
    pkill -9 -P $$ scp 2>/dev/null || true

    # Give processes a moment to die
    sleep 0.2

    # Cleanup temp files
    rm -f /tmp/remote_exec_*.tar.gz 2>/dev/null || true

    echo
    echo "Cleanup complete"
}

# Prompt for script parameters with readline support
# Args: display_path_result
# Sets: param_line (global)
# Returns: 0 on success, 1 if cancelled
__prompt_for_params__() {
    local display_path_result="$1"

    __line_rgb__ "=== Enter parameters for $display_path_result (type 'c' to cancel or leave empty):" 200 200 0
    printf "\033[38;2;150;150;150mTip: Use arrow keys to navigate, Home/End to jump, Ctrl+U to clear all and Ctrl+K to clear to end\033[0m\n"

    param_line=""
    read -e -r param_line || true

    if [ "$param_line" = "c" ]; then
        return 1
    fi
    return 0
}

# --- __test_remote_connection__ ----------------------------------------------
# @function __test_remote_connection__
# @description Test SSH connection to remote node with given credentials
# @usage __test_remote_connection__ <ip> <password> <username> <port>
# @param 1 Node IP address
# @param 2 Password (empty if using SSH keys)
# @param 3 Username
# @param 4 Port number
# @return 0 if connection successful, 1 otherwise
__test_remote_connection__() {
    local node_ip="$1"
    local node_pass="$2"
    local username="$3"
    local port="$4"

    # Try simple echo command to test connection
    if __ssh_exec__ "$node_ip" "$node_pass" "$username" "$port" "echo test" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Helper: Execute SSH command with appropriate auth method
# Args: node_ip node_pass username port command
# Returns: output of ssh command
__ssh_exec__() {
    local node_ip="$1"
    local node_pass="$2"
    local username="$3"
    local port="$4"
    shift 4
    local command="$*"

    if [[ "$USE_SSH_KEYS" == "true" ]] || [[ -z "$node_pass" ]]; then
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p "$port" "${username}@${node_ip}" "$command"
    else
        sshpass -p "$node_pass" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p "$port" "${username}@${node_ip}" "$command"
    fi
}

# Helper: Execute SCP with appropriate auth method
# Args: node_ip node_pass username port source destination
# Returns: exit code of scp
__scp_exec__() {
    local node_ip="$1"
    local node_pass="$2"
    local username="$3"
    local port="$4"
    local source="$5"
    local destination="$6"

    if [[ "$USE_SSH_KEYS" == "true" ]] || [[ -z "$node_pass" ]]; then
        scp -q -o StrictHostKeyChecking=no -P "$port" "$source" "${username}@$node_ip:$destination"
    else
        sshpass -p "$node_pass" scp -q -o StrictHostKeyChecking=no -P "$port" "$source" "${username}@$node_ip:$destination"
    fi
}

# Helper: Execute SCP recursive with appropriate auth method
# Args: node_ip node_pass username port source destination
# Returns: exit code of scp
__scp_exec_recursive__() {
    local node_ip="$1"
    local node_pass="$2"
    local username="$3"
    local port="$4"
    local source="$5"
    local destination="$6"

    if [[ "$USE_SSH_KEYS" == "true" ]] || [[ -z "$node_pass" ]]; then
        scp -q -r -o StrictHostKeyChecking=no -P "$port" "$source" "${username}@$node_ip:$destination"
    else
        sshpass -p "$node_pass" scp -q -r -o StrictHostKeyChecking=no -P "$port" "$source" "${username}@$node_ip:$destination"
    fi
}

# Helper: Download file from remote with appropriate auth method
# Args: node_ip node_pass username port remote_path local_path
# Returns: exit code of scp
__scp_download__() {
    local node_ip="$1"
    local node_pass="$2"
    local username="$3"
    local port="$4"
    local remote_path="$5"
    local local_path="$6"

    if [[ "$USE_SSH_KEYS" == "true" ]] || [[ -z "$node_pass" ]]; then
        scp -q -o StrictHostKeyChecking=no -P "$port" "${username}@$node_ip:$remote_path" "$local_path"
    else
        sshpass -p "$node_pass" scp -q -o StrictHostKeyChecking=no -P "$port" "${username}@$node_ip:$remote_path" "$local_path"
    fi
}

# Execute workflow on single remote node
# Args: node_name node_ip node_pass username port script_path script_relative script_dir_relative param_line
# Returns: 0 on success, 1 on failure
__execute_on_remote_node__() {
    local node_name="$1"
    local node_ip="$2"
    local node_pass="$3"
    local username="$4"
    local port="$5"
    local script_path="$6"
    local script_relative="$7"
    local script_dir_relative="$8"
    local param_line="$9"

    echo "----------------------------------------"
    echo "Target: $node_name ($node_ip:$port)"
    echo "----------------------------------------"
    echo

    # Setup environment
    __info__ "Setting up remote environment..."
    __log_info__ "Cleaning and creating remote directory structure on $node_name" "REMOTE"

    local ssh_output
    if ! ssh_output=$(__ssh_exec__ "$node_ip" "$node_pass" "$username" "$port" \
        "rm -rf $REMOTE_TEMP_DIR && mkdir -p $REMOTE_TEMP_DIR/{Utilities,Host,LXC,Storage,VirtualMachines,Networking,Cluster,Security,HighAvailability,Firewall,Resources,RemoteManagement}" 2>&1); then
        # Check if interrupted
        if [[ $REMOTE_INTERRUPTED -eq 1 ]]; then
            return 1
        fi
        __err__ "Failed to connect to $node_name"
        __log_error__ "Failed to connect/create directories on $node_name: $ssh_output" "REMOTE"
        return 1
    fi

    # Check if interrupted
    if [[ $REMOTE_INTERRUPTED -eq 1 ]]; then
        return 1
    fi
    __ok__ "Remote environment ready"
    __log_info__ "Remote directories created on $node_name" "REMOTE"

    # Check if interrupted
    if [[ $REMOTE_INTERRUPTED -eq 1 ]]; then
        return 1
    fi

    # Transfer utilities and script
    __info__ "Transferring files..."
    __log_info__ "Transferring utilities and script to $node_name" "REMOTE"

    # Create tarball for faster transfer (use timestamp to avoid collision in same GUI session)
    local temp_tar="/tmp/remote_exec_$$_$(date +%s%N).tar.gz"
    tar -czf "$temp_tar" -C . Utilities "$script_dir_relative/$(basename "$script_path")" 2>/dev/null || {
        # Fallback to individual transfers if tar fails
        __update__ "Tar failed, using individual transfers..."

        # Check if interrupted
        if [[ $REMOTE_INTERRUPTED -eq 1 ]]; then
            return 1
        fi

        if ! __scp_exec_recursive__ "$node_ip" "$node_pass" "$username" "$port" "Utilities/*.sh" "$REMOTE_TEMP_DIR/Utilities/" 2>/dev/null; then
            # Check if interrupted or actual failure
            if [[ $REMOTE_INTERRUPTED -eq 1 ]]; then
                return 1
            fi
            __err__ "Failed to transfer utilities"
            __log_error__ "Failed to transfer utilities to $node_name" "REMOTE"
            return 1
        fi

        # Check if interrupted
        if [[ $REMOTE_INTERRUPTED -eq 1 ]]; then
            return 1
        fi

        if ! __scp_exec__ "$node_ip" "$node_pass" "$username" "$port" "$script_path" "$REMOTE_TEMP_DIR/$script_dir_relative/" 2>/dev/null; then
            # Check if interrupted or actual failure
            if [[ $REMOTE_INTERRUPTED -eq 1 ]]; then
                return 1
            fi
            __err__ "Failed to transfer script"
            __log_error__ "Failed to transfer $script_path to $node_name" "REMOTE"
            return 1
        fi
        __ok__ "Files transferred (individual)"
        __log_info__ "Files transferred successfully (individual)" "REMOTE"
    }

    # Check if interrupted
    if [[ $REMOTE_INTERRUPTED -eq 1 ]]; then
        rm -f "$temp_tar"
        return 1
    fi

    # If tar succeeded, transfer and extract
    if [[ -f "$temp_tar" ]]; then
        if __scp_exec__ "$node_ip" "$node_pass" "$username" "$port" "$temp_tar" "/tmp/" 2>/dev/null; then
            # Check if interrupted
            if [[ $REMOTE_INTERRUPTED -eq 1 ]]; then
                rm -f "$temp_tar"
                return 1
            fi

            __ssh_exec__ "$node_ip" "$node_pass" "$username" "$port" \
                "tar -xzf /tmp/$(basename "$temp_tar") -C $REMOTE_TEMP_DIR && rm /tmp/$(basename "$temp_tar")" 2>/dev/null
            __ok__ "Files transferred (tarball)"
            __log_info__ "Files transferred successfully (tarball)" "REMOTE"
        else
            # Check if interrupted or actual failure
            if [[ $REMOTE_INTERRUPTED -eq 1 ]]; then
                rm -f "$temp_tar"
                return 1
            fi
            __err__ "Failed to transfer tarball"
            __log_error__ "Failed to transfer tarball to $node_name" "REMOTE"
            rm -f "$temp_tar"
            return 1
        fi
        rm -f "$temp_tar"
    fi

    # Check if interrupted
    if [[ $REMOTE_INTERRUPTED -eq 1 ]]; then
        return 1
    fi

    # Execute script remotely
    __info__ "Executing script..."
    __log_info__ "Executing $script_relative on remote with args: $param_line" "REMOTE"
    __log_debug__ "REMOTE_LOG_LEVEL in RemoteExecutor: $REMOTE_LOG_LEVEL" "REMOTE"

    # Use timestamp-based unique ID instead of PID to avoid log collision across multiple executions
    local exec_id="$$_$(date +%s%N)"
    local remote_log="/tmp/proxmox_remote_execution_${exec_id}.log"
    local remote_debug_log="/tmp/proxmox_remote_debug_${exec_id}.log"
    local ssh_exit_code=0

    # Execute script and capture output to log file
    if [[ -n "$param_line" ]]; then
        __ssh_exec__ "$node_ip" "$node_pass" "$username" "$port" \
            "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin NON_INTERACTIVE=1 DEBIAN_FRONTEND=noninteractive UTILITYPATH='$REMOTE_TEMP_DIR/Utilities' LOG_FILE='$remote_debug_log' LOG_LEVEL=$REMOTE_LOG_LEVEL LOG_CONSOLE=0 && cd $REMOTE_TEMP_DIR && { echo '=== Remote Execution Start ==='; echo 'Script: bash $script_relative'; echo 'Arguments: $param_line'; echo 'Working directory: '\$(pwd); echo 'UTILITYPATH: '\$UTILITYPATH; echo 'LOG_FILE: '\$LOG_FILE; echo 'LOG_LEVEL: '\$LOG_LEVEL; echo 'LOG_LEVEL (actual): $REMOTE_LOG_LEVEL'; echo '==================================='; eval bash $script_relative $param_line; echo \$? > ${remote_log}.exit; } >> $remote_log 2>&1"
        ssh_exit_code=$?
    else
        __ssh_exec__ "$node_ip" "$node_pass" "$username" "$port" \
            "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin NON_INTERACTIVE=1 DEBIAN_FRONTEND=noninteractive UTILITYPATH='$REMOTE_TEMP_DIR/Utilities' LOG_FILE='$remote_debug_log' LOG_LEVEL=$REMOTE_LOG_LEVEL LOG_CONSOLE=0 && cd $REMOTE_TEMP_DIR && { echo '=== Remote Execution Start ==='; echo 'Script: bash $script_relative'; echo 'Working directory: '\$(pwd); echo 'UTILITYPATH: '\$UTILITYPATH; echo 'LOG_FILE: '\$LOG_FILE; echo 'LOG_LEVEL: '\$LOG_LEVEL; echo 'LOG_LEVEL (actual): $REMOTE_LOG_LEVEL'; echo '==================================='; bash $script_relative; echo \$? > ${remote_log}.exit; } >> $remote_log 2>&1"
        ssh_exit_code=$?
    fi

    # Get final exit code from file if available
    local temp_exit_file="/tmp/remote_exit_${exec_id}"
    if __scp_download__ "$node_ip" "$node_pass" "$username" "$port" "${remote_log}.exit" "$temp_exit_file" 2>/dev/null; then
        local script_exit_code=$(cat "$temp_exit_file" 2>/dev/null)
        if [[ -n "$script_exit_code" ]] && [[ "$script_exit_code" =~ ^[0-9]+$ ]]; then
            ssh_exit_code=$script_exit_code
        fi
        rm -f "$temp_exit_file"
    fi

    __ok__ "Script execution complete"

    __log_info__ "Script execution completed with exit code: $ssh_exit_code" "REMOTE"

    # Download final log file and debug logs
    local local_remote_log="/tmp/remote_${node_name}_${exec_id}.log"
    local local_debug_log="/tmp/remote_${node_name}_${exec_id}.debug.log"

    # Ensure we have the final version of the log
    __scp_download__ "$node_ip" "$node_pass" "$username" "$port" "$remote_log" "$local_remote_log" 2>/dev/null || true
    
    # Retrieve debug log if it exists
    if __scp_download__ "$node_ip" "$node_pass" "$username" "$port" "$remote_debug_log" "$local_debug_log" 2>/dev/null; then
        __log_info__ "Retrieved debug log from $node_name" "REMOTE"

        # Show debug log if it has content (not shown live)
        if [[ -s "$local_debug_log" ]]; then
            echo
            echo "--- Debug Log from $node_name (LOG_LEVEL=$REMOTE_LOG_LEVEL) ---"
            cat "$local_debug_log"
            echo "--- End debug log ---"
            echo
        fi

        # Append debug log to main log file
        cat "$local_debug_log" >>"$LOG_FILE" 2>/dev/null || true
        echo "Debug log saved to: $local_debug_log"
    else
        __log_debug__ "No debug log available from $node_name" "REMOTE"
    fi

    echo "Output log saved to: $local_remote_log"
    if [[ -f "$local_remote_log" ]]; then
        cat "$local_remote_log" >>"$LOG_FILE"
    fi

    # Cleanup
    CURRENT_MESSAGE="Cleaning up..."
    __update__ "$CURRENT_MESSAGE"
    __log_info__ "Cleaning up remote directory: $REMOTE_TEMP_DIR" "REMOTE"
    __ssh_exec__ "$node_ip" "$node_pass" "$username" "$port" \
        "rm -rf $REMOTE_TEMP_DIR $remote_log $remote_debug_log ${remote_log}.exit" 2>/dev/null || __log_warn__ "Cleanup failed (non-critical)" "REMOTE"
    __ok__ "Cleanup complete"

    echo
    if [[ $ssh_exit_code -eq 0 ]]; then
        echo "$node_name completed successfully"
        __log_info__ "$node_name execution successful" "REMOTE"
    else
        echo "$node_name failed (exit code: $ssh_exit_code)"
        __log_error__ "$node_name execution failed with exit code: $ssh_exit_code" "REMOTE"
    fi

    # Ensure exit code is numeric before returning
    if [[ "$ssh_exit_code" =~ ^[0-9]+$ ]]; then
        return "$ssh_exit_code"
    else
        __log_error__ "Invalid exit code: '$ssh_exit_code', returning 1" "REMOTE"
        return 1
    fi
}

# Execute script on remote target(s)
# Args: script_path display_path_result script_relative script_dir_relative param_line
# Returns: Sets LAST_SCRIPT and LAST_OUTPUT globals
__execute_remote_script__() {
    local script_path="$1"
    local display_path_result="$2"
    local script_relative="$3"
    local script_dir_relative="$4"
    local param_line="$5"

    local success_count=0
    local fail_count=0

    # Reset interrupt flag
    REMOTE_INTERRUPTED=0

    # Set trap for Ctrl+C
    trap '__remote_cleanup__' INT

    # Temporarily disable errexit to ensure loop continues
    local old_opts=$-
    set +e

    # Execute on each target
    for target in "${REMOTE_TARGETS[@]}"; do
        # Check if interrupted
        if [[ $REMOTE_INTERRUPTED -eq 1 ]]; then
            echo
            echo "Remaining nodes skipped due to interrupt"
            break
        fi

        # Parse target safely
        local node_name=""
        local node_ip=""
        IFS=':' read -r node_name node_ip <<<"$target" || {
            echo "Failed to parse target: $target"
            ((fail_count += 1))
            continue
        }

        # Get password safely
        local node_pass=""
        if [[ -v NODE_PASSWORDS[$node_name] ]]; then
            node_pass="${NODE_PASSWORDS[$node_name]}"
        else
            echo "No password configured for $node_name"
            ((fail_count += 1))
            continue
        fi

        # Get username safely
        local node_username="${NODE_USERNAMES[$node_name]:-$DEFAULT_USERNAME}"

        # Get port safely
        local node_port="${NODE_PORTS[$node_name]:-$DEFAULT_PORT}"

        # Execute on this node (always continue to next node regardless of result)
        if __execute_on_remote_node__ "$node_name" "$node_ip" "$node_pass" "$node_username" "$node_port" "$script_path" "$script_relative" "$script_dir_relative" "$param_line"; then
            ((success_count += 1))
        else
            ((fail_count += 1))
        fi

        # Check again after execution in case interrupt happened during execution
        if [[ $REMOTE_INTERRUPTED -eq 1 ]]; then
            echo
            echo "Remaining nodes skipped due to interrupt"
            break
        fi
    done

    # Restore errexit if it was set
    [[ $old_opts =~ e ]] && set -e

    # Remove trap
    trap - INT

    # Reset flag
    REMOTE_INTERRUPTED=0

    echo
    echo "========================================"
    echo "Summary: $success_count successful, $fail_count failed"
    echo "========================================"

    # Export for use by GUI.sh
    export LAST_SCRIPT="$display_path_result"
    export LAST_OUTPUT="Remote execution on ${#REMOTE_TARGETS[@]} node(s): $success_count OK, $fail_count FAIL"
}

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2026-01-08
#
# Changes:
# - 2026-01-08: Fixed log filename collision issue when GUI.sh runs multiple executions
# - 2026-01-08: Added __test_remote_connection__ for password validation
# - 2025-12-18: Added SSH port configuration support for proxy/jump host setups
# - 2025-11-24: Validated against CONTRIBUTING.md and fixed ShellCheck issues
# - 2025-11-24: Added conditional sourcing of utility dependencies
# - 2025-11-24: Fixed variable quoting issues (SC2086)
# - 2025-11-24: Changed exit code check to direct command check (SC2181)
# - 2025-11-24: Exported LAST_SCRIPT and LAST_OUTPUT for GUI.sh use
# - 2025-11-24: Replaced direct sshpass call with __ssh_exec__ wrapper
#
# Fixes:
# - 2025-11-24: Fixed unquoted node_ip variables causing globbing risks
# - 2025-11-24: Fixed indirect exit code check with direct command check
# - 2025-11-24: Fixed return value quoting
#
# Known issues:
# -
#

