#!/bin/bash
#
# RemoteExecutor.sh
#
# Handles all remote script execution logic including SSH, file transfer,
# and result collection.
#

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

# Execute workflow on single remote node
# Args: node_name node_ip node_pass script_path script_relative script_dir_relative param_line
# Returns: 0 on success, 1 on failure
__execute_on_remote_node__() {
    local node_name="$1"
    local node_ip="$2"
    local node_pass="$3"
    local script_path="$4"
    local script_relative="$5"
    local script_dir_relative="$6"
    local param_line="$7"
    
    echo "----------------------------------------"
    echo "Target: $node_name ($node_ip)"
    echo "----------------------------------------"
    echo
    
    # Setup environment
    CURRENT_MESSAGE="Setting up remote environment..."
    __info__ "$CURRENT_MESSAGE"
    __log_info__ "Cleaning and creating remote directory structure on $node_name" "REMOTE"
    
    local ssh_output
    ssh_output=$(sshpass -p "$node_pass" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@$node_ip \
        "rm -rf $REMOTE_TEMP_DIR && mkdir -p $REMOTE_TEMP_DIR/{Utilities,Host,LXC,Storage,VirtualMachines,Networking,Cluster,Security,HighAvailability,Firewall,Resources,RemoteManagement}" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        __stop_spin__
        echo "❌ Failed to connect to $node_name"
        __log_error__ "Failed to connect/create directories on $node_name: $ssh_output" "REMOTE"
        return 1
    fi
    __ok__ "Remote environment ready"
    __log_info__ "Remote directories created on $node_name" "REMOTE"
    
    # Transfer utilities
    CURRENT_MESSAGE="Transferring utilities..."
    __update__ "$CURRENT_MESSAGE"
    __log_info__ "Transferring utilities to $node_name" "REMOTE"
    
    if ! sshpass -p "$node_pass" scp -q -o StrictHostKeyChecking=no -r Utilities/*.sh root@$node_ip:$REMOTE_TEMP_DIR/Utilities/ 2>/dev/null; then
        __stop_spin__
        echo "❌ Failed to transfer utilities"
        __log_error__ "Failed to transfer utilities to $node_name" "REMOTE"
        return 1
    fi
    __ok__ "Utilities transferred"
    __log_info__ "Utilities transferred successfully" "REMOTE"
    
    # Transfer script
    CURRENT_MESSAGE="Transferring script..."
    __update__ "$CURRENT_MESSAGE"
    __log_info__ "Transferring $script_relative to $node_name:$REMOTE_TEMP_DIR/$script_dir_relative/" "REMOTE"
    
    if ! sshpass -p "$node_pass" scp -q -o StrictHostKeyChecking=no "$script_path" root@$node_ip:$REMOTE_TEMP_DIR/$script_dir_relative/ 2>/dev/null; then
        __stop_spin__
        echo "❌ Failed to transfer script"
        __log_error__ "Failed to transfer $script_path to $node_name" "REMOTE"
        return 1
    fi
    __ok__ "Script transferred"
    __log_info__ "Script transferred successfully" "REMOTE"
    
    # Execute script
    CURRENT_MESSAGE="Executing script..."
    __update__ "$CURRENT_MESSAGE"
    __log_info__ "Executing $script_relative on remote with args: $param_line" "REMOTE"
    
    local remote_log="/tmp/proxmox_remote_execution_$$.log"
    local ssh_exit_code=0
    
    if [[ -n "$param_line" ]]; then
        sshpass -p "$node_pass" ssh -o StrictHostKeyChecking=no root@$node_ip \
            "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin NON_INTERACTIVE=1 DEBIAN_FRONTEND=noninteractive UTILITYPATH='$REMOTE_TEMP_DIR/Utilities' LOG_FILE='$remote_log' LOG_LEVEL=$REMOTE_LOG_LEVEL LOG_CONSOLE=0 && cd $REMOTE_TEMP_DIR && echo '=== Remote Execution Start ===' > $remote_log 2>&1 && echo 'Script: bash $script_relative' >> $remote_log 2>&1 && echo 'Arguments: $param_line' >> $remote_log 2>&1 && echo 'Working directory: '\$(pwd) >> $remote_log 2>&1 && echo 'UTILITYPATH: '\$UTILITYPATH >> $remote_log 2>&1 && echo 'LOG_FILE: '\$LOG_FILE >> $remote_log 2>&1 && echo 'LOG_LEVEL: '\$LOG_LEVEL >> $remote_log 2>&1 && echo '===================================' >> $remote_log 2>&1 && eval bash $script_relative $param_line >> $remote_log 2>&1; echo \$? > ${remote_log}.exit"
    else
        sshpass -p "$node_pass" ssh -o StrictHostKeyChecking=no root@$node_ip \
            "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin NON_INTERACTIVE=1 DEBIAN_FRONTEND=noninteractive UTILITYPATH='$REMOTE_TEMP_DIR/Utilities' LOG_FILE='$remote_log' LOG_LEVEL=$REMOTE_LOG_LEVEL LOG_CONSOLE=0 && cd $REMOTE_TEMP_DIR && bash $script_relative > $remote_log 2>&1; echo \$? > ${remote_log}.exit"
    fi
    
    __ok__ "Script execution complete"
    
    # Retrieve exit code
    local temp_exit_file="/tmp/remote_exit_$$"
    if sshpass -p "$node_pass" scp -q -o StrictHostKeyChecking=no root@$node_ip:${remote_log}.exit "$temp_exit_file" 2>/dev/null; then
        ssh_exit_code=$(cat "$temp_exit_file")
        rm -f "$temp_exit_file"
    else
        ssh_exit_code=1
    fi
    
    __log_info__ "Script execution completed with exit code: $ssh_exit_code" "REMOTE"
    
    # Retrieve and display remote log
    local local_remote_log="/tmp/remote_${node_name}_$$.log"
    if sshpass -p "$node_pass" scp -q -o StrictHostKeyChecking=no root@$node_ip:$remote_log "$local_remote_log" 2>/dev/null; then
        __log_info__ "Retrieved remote execution log from $node_name" "REMOTE"
        echo
        echo "--- Output from $node_name ---"
        cat "$local_remote_log"
        echo "--- End output ---"
        echo
        echo "Log saved to: $local_remote_log"
        cat "$local_remote_log" >> "$LOG_FILE"
    else
        __log_warn__ "Could not retrieve remote log from $node_name" "REMOTE"
    fi
    
    # Cleanup
    CURRENT_MESSAGE="Cleaning up..."
    __update__ "$CURRENT_MESSAGE"
    __log_info__ "Cleaning up remote directory: $REMOTE_TEMP_DIR" "REMOTE"
    sshpass -p "$node_pass" ssh -o StrictHostKeyChecking=no root@$node_ip \
        "rm -rf $REMOTE_TEMP_DIR $remote_log ${remote_log}.exit" 2>/dev/null || __log_warn__ "Cleanup failed (non-critical)" "REMOTE"
    __ok__ "Cleanup complete"
    
    echo
    if [[ $ssh_exit_code -eq 0 ]]; then
        echo "$node_name completed successfully"
        __log_info__ "$node_name execution successful" "REMOTE"
        return 0
    else
        echo "$node_name failed (exit code: $ssh_exit_code)"
        __log_error__ "$node_name execution failed with exit code: $ssh_exit_code" "REMOTE"
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
    
    # Execute on each target
    for target in "${REMOTE_TARGETS[@]}"; do
        # Parse target safely
        local node_name=""
        local node_ip=""
        IFS=':' read -r node_name node_ip <<< "$target" || {
            echo "Failed to parse target: $target"
            ((fail_count++))
            continue
        }
        
        # Get password safely
        local node_pass=""
        if [[ -v NODE_PASSWORDS[$node_name] ]]; then
            node_pass="${NODE_PASSWORDS[$node_name]}"
        else
            echo "No password configured for $node_name"
            ((fail_count++))
            continue
        fi
        
        # Execute on this node
        if __execute_on_remote_node__ "$node_name" "$node_ip" "$node_pass" "$script_path" "$script_relative" "$script_dir_relative" "$param_line"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done
    
    echo
    echo "========================================" 
    echo "Summary: $success_count successful, $fail_count failed"
    echo "========================================"
    
    LAST_SCRIPT="$display_path_result"
    LAST_OUTPUT="Remote execution on ${#REMOTE_TARGETS[@]} node(s): $success_count OK, $fail_count FAIL"
}
