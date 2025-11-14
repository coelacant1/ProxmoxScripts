#!/bin/bash
#
# RemoteExecution.sh
#
# Provides utilities for executing ProxmoxScripts remotely on nodes and VMs/CTs.
# Sets up proper environment variables and handles output streaming.
#
# Usage:
#   source "${UTILITYPATH}/RemoteExecution.sh"
#   setup_remote_node "node1" "192.168.1.100"
#   execute_script_on_node "192.168.1.100" "Host/QuickDiagnostic.sh"
#
# Examples:
#   # Execute script on remote node
#   source Utilities/RemoteExecution.sh
#   setup_remote_node "pve1" "192.168.1.100"
#   execute_script_on_node "192.168.1.100" "Host/QuickDiagnostic.sh"
#   cleanup_remote_node "192.168.1.100"
#
# Function Index:
#   - setup_remote_node
#   - execute_script_on_node
#   - cleanup_remote_node
#

set -euo pipefail

# Source Logger for structured logging
if [[ -n "${UTILITYPATH:-}" && -f "${UTILITYPATH}/Logger.sh" ]]; then
    # shellcheck source=Utilities/Logger.sh
    source "${UTILITYPATH}/Logger.sh"
fi

# Safe logging wrapper
__remoteexec_log__() {
    local level="$1"
    local message="$2"
    if declare -f __log__ >/dev/null 2>&1; then
        __log__ "$level" "$message" "REMOTEEXEC"
    fi
}

# Source required utilities
source "${UTILITYPATH}/SSH.sh"
source "${UTILITYPATH}/Communication.sh"

# Global for tracking remote temp directory
REMOTE_TEMP_DIR="/tmp/ProxmoxScripts_$$"

# --- setup_remote_node -------------------------------------------------------
# @function setup_remote_node
# @description Sets up the ProxmoxScripts environment on a remote node
# @usage setup_remote_node <node_name> <node_ip>
# @param node_name Friendly name for the node
# @param node_ip IP address or hostname of the node
# @return 0 on success, 1 on failure
setup_remote_node() {
    local node_name="$1"
    local node_ip="$2"
    
    __remoteexec_log__ "INFO" "Setting up remote environment on $node_name ($node_ip)"
    __info__ "Setting up remote environment on $node_name ($node_ip)"
    
    __remoteexec_log__ "DEBUG" "Creating remote directory structure: $REMOTE_TEMP_DIR"
    # Create temporary directory structure
    ssh "root@$node_ip" "mkdir -p $REMOTE_TEMP_DIR/{Utilities,Host,LXC,Storage,VirtualMachines}" 2>/dev/null || {
        __remoteexec_log__ "ERROR" "Failed to create remote directory on $node_ip"
        __err__ "Failed to create remote directory"
        return 1
    }
    __remoteexec_log__ "DEBUG" "Remote directory structure created successfully"
    
    # Transfer utilities (essential for all scripts)
    __remoteexec_log__ "INFO" "Transferring utilities to $node_ip"
    __info__ "Transferring utilities..."
    rsync -az --quiet \
        Utilities/*.sh \
        "root@$node_ip:$REMOTE_TEMP_DIR/Utilities/" || {
        __remoteexec_log__ "ERROR" "Failed to transfer utilities to $node_ip"
        __err__ "Failed to transfer utilities"
        return 1
    }
    __remoteexec_log__ "DEBUG" "Utilities transferred successfully"
    
    __remoteexec_log__ "INFO" "Remote environment ready on $node_name"
    __ok__ "Remote environment ready on $node_name"
    return 0
}

# --- execute_script_on_node --------------------------------------------------
# @function execute_script_on_node
# @description Executes a script on a remote node with NON_INTERACTIVE=1
# @usage execute_script_on_node <node_ip> <script_path> [args...]
# @param node_ip IP address or hostname of the node
# @param script_path Path to the script (relative to repo root)
# @param args Additional arguments to pass to the script
# @return Exit code from remote execution
execute_script_on_node() {
    local node_ip="$1"
    local script_path="$2"
    shift 2
    local args=("$@")
    
    local script_name=$(basename "$script_path")
    local script_dir=$(dirname "$script_path")
    
    __remoteexec_log__ "INFO" "Executing $script_name on $node_ip with args: ${args[*]:-<none>}"
    __info__ "Executing $script_name on $node_ip"
    
    # Transfer the specific script
    __remoteexec_log__ "DEBUG" "Transferring script: $script_path"
    rsync -az --quiet \
        "$script_path" \
        "root@$node_ip:$REMOTE_TEMP_DIR/$script_dir/" || {
        __remoteexec_log__ "ERROR" "Failed to transfer script $script_path to $node_ip"
        __err__ "Failed to transfer script"
        return 1
    }
    __remoteexec_log__ "DEBUG" "Script transferred successfully"
    
    # Build command with --non-interactive flag
    local cmd="bash $REMOTE_TEMP_DIR/$script_path --non-interactive"
    for arg in "${args[@]}"; do
        cmd+=" $(printf '%q' "$arg")"
    done
    __remoteexec_log__ "DEBUG" "Remote command: $cmd"
    
    # Execute with proper environment and streaming output
    __remoteexec_log__ "INFO" "Starting remote execution with NON_INTERACTIVE=1"
    ssh -T "root@$node_ip" << EOF | stdbuf -oL cat
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export NON_INTERACTIVE=1
export DEBIAN_FRONTEND=noninteractive
export UTILITYPATH="$REMOTE_TEMP_DIR/Utilities"
$cmd
exit_code=\$?
exit \$exit_code
EOF
    
    local exit_code=${PIPESTATUS[0]}
    __remoteexec_log__ "DEBUG" "Remote execution completed with exit code: $exit_code"
    
    if [[ $exit_code -eq 0 ]]; then
        __remoteexec_log__ "INFO" "Script completed successfully on $node_ip"
        __ok__ "Script completed successfully"
    else
        __remoteexec_log__ "ERROR" "Script failed on $node_ip (exit code: $exit_code)"
        __err__ "Script failed (exit code: $exit_code)"
    fi
    
    return $exit_code
}

# --- cleanup_remote_node -----------------------------------------------------
# @function cleanup_remote_node
# @description Cleans up the temporary directory on remote node
# @usage cleanup_remote_node <node_ip>
# @param node_ip IP address or hostname of the node
cleanup_remote_node() {
    local node_ip="$1"
    
    __remoteexec_log__ "INFO" "Cleaning up remote environment on $node_ip"
    __info__ "Cleaning up remote environment on $node_ip"
    
    __remoteexec_log__ "DEBUG" "Removing remote directory: $REMOTE_TEMP_DIR"
    ssh "root@$node_ip" "rm -rf $REMOTE_TEMP_DIR" 2>/dev/null || {
        __remoteexec_log__ "WARN" "Could not clean up $REMOTE_TEMP_DIR on $node_ip"
        __warn__ "Could not clean up $REMOTE_TEMP_DIR on $node_ip"
        return 1
    }
    
    __remoteexec_log__ "INFO" "Cleanup complete on $node_ip"
    __ok__ "Cleanup complete"
    return 0
}

# Example usage in script:
# source Utilities/RemoteExecution.sh
# setup_remote_node "pve1" "192.168.1.100"
# execute_script_on_node "192.168.1.100" "Host/QuickDiagnostic.sh"
# cleanup_remote_node "192.168.1.100"
