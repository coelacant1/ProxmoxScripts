#!/bin/bash
#
# GUI.sh
#
# Interactive menu-driven interface for navigating and executing ProxmoxScripts.
# Supports both local execution and remote execution across multiple nodes.
#
# Usage:
#   GUI.sh
#   GUI.sh -c
#   GUI.sh --clear-logs
#   GUI.sh -d
#   GUI.sh --debug
#   GUI.sh -q
#   GUI.sh --quiet
#   GUI.sh -h
#
# Options:
#   -c, --clear-logs    Clear all logs before starting
#   -d, --debug         Remote scripts show DEBUG level output (very verbose)
#   -v, --verbose       Remote scripts show INFO level output (default)
#   -q, --quiet         Remote scripts show only ERROR level output
#   -h, --help          Show help message
#
# Log Levels:
#   DEBUG   - All messages including trace and debug information
#   INFO    - Informational messages, warnings, and errors (default)
#   WARN    - Warnings and errors only
#   ERROR   - Errors only
#
# Note: All output is always saved to log files regardless of display level
#
# Requirements:
#   - UTILITYPATH must be set (automatically done when running from repository root)
#   - For remote execution: sshpass, jq, nodes.json file
#
# Function Index:
#   - error_handler
#   - show_ascii_art
#   - show_top_comments
#   - show_script_usage
#   - display_path
#   - run_script
#   - run_script_local
#   - run_script_remote
#   - select_execution_mode
#   - configure_single_remote
#   - configure_multi_remote
#   - manage_nodes_menu
#   - navigate
#
#

set -euo pipefail

###############################################################################
# ARGUMENT PARSING
###############################################################################

# Parse command-line arguments
CLEAR_LOGS=false
REMOTE_LOG_LEVEL="INFO"
for arg in "$@"; do
    case $arg in
        -c|--clear-logs)
            CLEAR_LOGS=true
            shift
            ;;
        -d|--debug)
            REMOTE_LOG_LEVEL="DEBUG"
            shift
            ;;
        -v|--verbose)
            REMOTE_LOG_LEVEL="INFO"
            shift
            ;;
        -q|--quiet)
            REMOTE_LOG_LEVEL="ERROR"
            shift
            ;;
        --manual)
            shift
            if [[ -z "${1:-}" ]]; then
                echo "Error: --manual requires manual name" >&2
                echo "Examples:" >&2
                echo "  ./GUI.sh --manual getting-started" >&2
                echo "  ./GUI.sh --manual gui-overview" >&2
                exit 1
            fi
            # Source early to use manual viewer
            UTILITYPATH="./Utilities"
            source "${UTILITYPATH}/ManualViewer.sh"
            __show_manual__ "$1"
            exit 0
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -c, --clear-logs    Clear all logs before starting"
            echo "  -d, --debug         Remote scripts show DEBUG level output (very verbose)"
            echo "  -v, --verbose       Remote scripts show INFO level output (default)"
            echo "  -q, --quiet         Remote scripts show only ERROR level output"
            echo "  --manual <name>     Show specific manual"
            echo "  -h, --help          Show this help message"
            echo ""
            echo "Log Levels:"
            echo "  DEBUG   - All messages including trace and debug information"
            echo "  INFO    - Informational messages, warnings, and errors (default)"
            echo "  WARN    - Warnings and errors only"
            echo "  ERROR   - Errors only"
            echo ""
            echo "Manuals:"
            echo "  --manual getting-started    Quick start guide"
            echo "  --manual gui-overview       Complete GUI documentation"
            echo "  --manual execution-modes    Execution mode details"
            echo "  --manual node-management    Node configuration guide"
            echo "  --manual troubleshooting    Common issues & solutions"
            echo ""
            echo "  Or press 'h' or '?' from any menu for interactive manual browser"
            echo ""
            echo "Note: All output is always saved to log files regardless of level"
            exit 0
            ;;
        *)
            # Ignore unknown args for now
            ;;
    esac
done

# Clear logs if requested
if [[ "$CLEAR_LOGS" == "true" ]]; then
    echo "🗑️  Clearing logs..."
    rm -f /tmp/gui_execution.log /tmp/gui_debug.log /tmp/proxmox_scripts.log
    echo "Logs cleared"
    sleep 1
fi

###############################################################################
# ERROR HANDLING
###############################################################################

# Global error handler
error_handler() {
    __show_error__ "${1:-${LINENO}}" "${2:-$BASH_COMMAND}" "${3:-$?}" "GUI.sh"
    echo "Press Enter to continue or Ctrl+C to exit..."
    read -r
}

# Set trap for ERR
trap 'error_handler ${LINENO} "$BASH_COMMAND" $?' ERR

###############################################################################
# CONFIG
###############################################################################

BASE_DIR="$(pwd)"       # We assume the script is run from the unzipped directory
DISPLAY_PREFIX="cc_pve" # How we display the "root" in the UI
HELP_FLAG="--help"      # If your scripts support a help flag, we pass this
LAST_SCRIPT=""          # The last script run
LAST_OUTPUT=""          # Truncated output of the last script
SHOW_HEADER="false"

# Configuration managed by ConfigManager.sh utility

###############################################################################
# IMPORT UTILITY FUNCTIONS FOR SCRIPTS AND COLOR GRADIENT LIBRARY
###############################################################################

UTILITYPATH="./Utilities"
source "${UTILITYPATH}/Colors.sh"
source "${UTILITYPATH}/Communication.sh"
source "${UTILITYPATH}/Logger.sh"
source "${UTILITYPATH}/ManualViewer.sh"
source "${UTILITYPATH}/Display.sh"
source "${UTILITYPATH}/ConfigManager.sh"
source "${UTILITYPATH}/RemoteExecutor.sh"

# Initialize configuration
__init_config__

# Configure logging for GUI
export LOG_FILE="/tmp/gui_execution.log"
export LOG_LEVEL="DEBUG"
export LOG_CONSOLE=0  # Don't spam console, just log to file

###############################################################################
# HEADER MANAGEMENT
###############################################################################

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h)
            SHOW_HEADER="true"
            shift
            ;;
        *)
            echo "Error: Unknown argument '$1'"
            exit 1
            ;;
    esac
done

###############################################################################
# ASCII ART HEADER (uses Display.sh utility)
###############################################################################

show_ascii_art() {
    if [[ "$SHOW_HEADER" == "true" ]]; then
        __show_ascii_art__ auto
    else
        __show_ascii_art__ basic
    fi

    echo
    __line_rgb__ "EXECUTION: $EXECUTION_MODE_DISPLAY" 255 200 0
    __line_rgb__ "TARGET: $TARGET_DISPLAY" 0 255 200
    if [[ "$EXECUTION_MODE" != "local" ]]; then
        local log_level_color
        case "$REMOTE_LOG_LEVEL" in
            DEBUG)   log_level_color="100 100 255" ;;
            INFO)    log_level_color="0 255 0" ;;
            WARN)    log_level_color="255 200 0" ;;
            ERROR)   log_level_color="255 100 100" ;;
            *)       log_level_color="150 150 150" ;;
        esac
        __line_rgb__ "LOG LEVEL: $REMOTE_LOG_LEVEL" $log_level_color
    fi
    echo
}

###############################################################################
# UTILITY FUNCTIONS
###############################################################################

show_top_comments() {
    local script_path="$1"
    clear
    show_ascii_art

    __show_script_info__ "$script_path" "$(display_path "$script_path")"

    __pause__
}

show_script_usage() {
    local script_path="$1"
    __line_rgb__ "=== Showing usage for: $(display_path "$script_path") ===" 200 200 0
    if [[ -x "$script_path" ]]; then
        "$script_path" "$HELP_FLAG" 2>&1 || true
    else
        bash "$script_path" "$HELP_FLAG" 2>&1 || true
    fi
    echo
    __pause__
}

display_path() {
    __display_path__ "$1" "$BASE_DIR" "$DISPLAY_PREFIX"
}

###############################################################################
# EXECUTION MODE SELECTION
###############################################################################
select_execution_mode() {
    while true; do
        clear
        show_ascii_art

        echo "Select execution mode:"
        echo "----------------------------------------"
        __line_rgb__ "1) Local Execution (this system)" 0 200 200
        __line_rgb__ "2) Single Remote Node" 0 200 200
        __line_rgb__ "3) Multiple Remote Nodes" 0 200 200
        echo
        echo "----------------------------------------"
        echo
        echo "Type 'm' to manage nodes"
        echo "Type 'h' or '?' for help"
        echo "Type 'e' to exit"
        echo
        echo "----------------------------------------"
        read -rp "Choice: " mode_choice
        
        case "$mode_choice" in
            1)
                __set_execution_mode__ "local"
                __clear_remote_targets__
                return 0
                ;;
            2)
                if configure_single_remote; then
                    return 0
                fi
                ;;
            3)
                if configure_multi_remote; then
                    return 0
                fi
                ;;
            m)
                manage_nodes_menu
                ;;
            h|\?)
                __manual_menu__
                ;;
            e|E)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo "Invalid choice!"
                sleep 1
                ;;
        esac
    done
}

configure_single_remote() {
    while true; do
        clear
        show_ascii_art
        echo "Available nodes from nodes.json:"
        echo "----------------------------------------"
        
        local node_count
        node_count=$(__count_available_nodes__)
        
        if [[ $node_count -eq 0 ]]; then
            echo "No nodes found in nodes.json"
            echo
            read -rp "Enter node IP manually: " manual_ip
            read -rp "Enter node name: " manual_name
            read -rsp "Enter password: " manual_pass
            echo
            
            __clear_remote_targets__
            __add_remote_target__ "$manual_name" "$manual_ip" "$manual_pass"
            __set_execution_mode__ "single-remote"
            return 0
        fi
        
        local i=1
        declare -A node_menu=()
        while IFS= read -r node_name; do
            local node_ip
            node_ip=$(__get_node_ip__ "$node_name")
            __line_rgb__ "  $i) $node_name ($node_ip)" 0 200 200
            node_menu[$i]="$node_name:$node_ip"
            ((i++))
        done < <(__get_available_nodes__)
        
        echo
        echo "----------------------------------------"
        echo
        echo "Type 'm' to enter manually"
        echo "Type 'h' or '?' for help"
        echo "Type 'b' to go back"
        echo
        echo "----------------------------------------"
        read -rp "Enter choice: " node_choice
        
        if [[ "$node_choice" == "b" ]]; then
            return 1
        elif [[ "$node_choice" == "h" ]] || [[ "$node_choice" == "?" ]]; then
            __manual_menu__
            continue  # Redisplay menu after manual
        elif [[ "$node_choice" == "m" ]]; then
            read -rp "Enter node IP: " manual_ip
            read -rp "Enter node name: " manual_name
            read -rsp "Enter password: " manual_pass
            echo
            
            __clear_remote_targets__
            __add_remote_target__ "$manual_name" "$manual_ip" "$manual_pass"
            __set_execution_mode__ "single-remote"
            return 0
        elif [[ -n "$node_choice" && -n "${node_menu[$node_choice]:-}" ]]; then
            IFS=':' read -r selected_name selected_ip <<< "${node_menu[$node_choice]}"
            read -rsp "Enter password for $selected_name: " node_pass
            echo
            
            __clear_remote_targets__
            __add_remote_target__ "$selected_name" "$selected_ip" "$node_pass"
            __set_execution_mode__ "single-remote"
            return 0
        else
            echo "Invalid choice!"
            sleep 1
        fi
    done
}

configure_multi_remote() {
    while true; do
        clear
        show_ascii_art
        echo "Available nodes from nodes.json:"
        echo
        
        local node_count
        node_count=$(__count_available_nodes__)
        
        if [[ $node_count -eq 0 ]]; then
            echo "No nodes configured. Add nodes first (option 'm')."
            sleep 2
            return 1
        fi
        
        local i=1
        declare -A node_menu=()
        while IFS= read -r node_name; do
            local node_ip
            node_ip=$(__get_node_ip__ "$node_name")
            echo "  $i) $node_name ($node_ip)"
            node_menu[$i]="$node_name:$node_ip"
            ((i++))
        done < <(__get_available_nodes__)
        
        echo
        echo "Enter node numbers (comma-separated, e.g., 1,3,5) or:"
        echo "  'all' - select all nodes"
        echo "  'h' or '?' - show help"
        echo "  'b' - go back"
        echo
        read -rp "Nodes: " node_selection
        
        if [[ "$node_selection" == "b" ]]; then
            return 1
        elif [[ "$node_selection" == "h" ]] || [[ "$node_selection" == "?" ]]; then
            __manual_menu__
            continue  # Redisplay menu after manual
        fi
        
        __clear_remote_targets__
        if [[ "$node_selection" == "all" ]]; then
            while IFS= read -r node_name; do
                local node_ip
                node_ip=$(__get_node_ip__ "$node_name")
                REMOTE_TARGETS+=("$node_name:$node_ip")
            done < <(__get_available_nodes__)
        else
            IFS=',' read -ra selected_nodes <<< "$node_selection"
            for num in "${selected_nodes[@]}"; do
                num=$(echo "$num" | xargs)
                if [[ -n "$num" && -n "${node_menu[$num]:-}" ]]; then
                    REMOTE_TARGETS+=("${node_menu[$num]}")
                fi
            done
        fi
        
        if [[ ${#REMOTE_TARGETS[@]} -eq 0 ]]; then
            echo "No valid nodes selected!"
            sleep 2
            continue  # Redisplay menu
        fi
        
        echo
        echo "Selected ${#REMOTE_TARGETS[@]} node(s)"
        echo
        read -rp "Same password for all nodes? [y/N]: " same_pass
        
        if [[ "$same_pass" =~ ^[Yy]$ ]]; then
            read -rsp "Enter password for all nodes: " shared_pass
            echo
            for target in "${REMOTE_TARGETS[@]}"; do
                IFS=':' read -r node_name node_ip <<< "$target"
                NODE_PASSWORDS["$node_name"]="$shared_pass"
            done
        else
            for target in "${REMOTE_TARGETS[@]}"; do
                IFS=':' read -r node_name node_ip <<< "$target"
                read -rsp "Enter password for $node_name ($node_ip): " node_pass
                echo
                NODE_PASSWORDS["$node_name"]="$node_pass"
            done
        fi
        
        __set_execution_mode__ "multi-remote"
        return 0
    done
}

manage_nodes_menu() {
    while true; do
        clear
        show_ascii_art
        echo "Node Management:"
        echo "----------------------------------------"
        __line_rgb__ "1) List nodes" 0 200 200
        __line_rgb__ "2) Add node" 0 200 200
        __line_rgb__ "3) Remove node" 0 200 200
        echo 
        echo "----------------------------------------"
        echo
        echo "Type 'h' or '?' for help"
        echo "Type 'b' to go back"
        echo
        echo "----------------------------------------"
        read -rp "Choice: " mgmt_choice
        
        case "$mgmt_choice" in
            1)
                echo
                echo "Configured nodes:"
                if [[ ${#AVAILABLE_NODES[@]} -eq 0 ]]; then
                    echo "  (none)"
                else
                    for node_name in "${!AVAILABLE_NODES[@]}"; do
                        echo "  - $node_name: ${AVAILABLE_NODES[$node_name]}"
                    done
                fi
                echo
                read -rp "Press Enter to continue..."
                ;;
            2)
                echo
                read -rp "Node name: " new_name
                read -rp "Node IP: " new_ip
                
                if command -v jq &>/dev/null; then
                    jq --arg name "$new_name" --arg ip "$new_ip" \
                        '.nodes += [{"name": $name, "ip": $ip}]' \
                        "$NODES_FILE" > "${NODES_FILE}.tmp" && \
                        mv "${NODES_FILE}.tmp" "$NODES_FILE"
                    AVAILABLE_NODES["$new_name"]="$new_ip"
                    echo "Added $new_name"
                else
                    echo "jq not installed"
                fi
                sleep 2
                ;;
            3)
                echo
                echo "Available nodes:"
                local i=1
                declare -A remove_menu=()
                for node_name in "${!AVAILABLE_NODES[@]}"; do
                    echo "  $i) $node_name"
                    remove_menu[$i]="$node_name"
                    ((i++))
                done
                echo
                read -rp "Remove node number: " remove_num
                
                if [[ -n "${remove_menu[$remove_num]}" ]]; then
                    remove_name="${remove_menu[$remove_num]}"
                    if command -v jq &>/dev/null; then
                        jq --arg name "$remove_name" \
                            '.nodes = [.nodes[] | select(.name != $name)]' \
                            "$NODES_FILE" > "${NODES_FILE}.tmp" && \
                            mv "${NODES_FILE}.tmp" "$NODES_FILE"
                        unset AVAILABLE_NODES["$remove_name"]
                        echo "Removed $remove_name"
                    else
                        echo "jq not installed"
                    fi
                fi
                sleep 2
                ;;
            h|\?)
                __manual_menu__
                ;;
            b)
                return 0
                ;;
        esac
    done
}

###############################################################################
# SCRIPT RUNNER
###############################################################################
run_script() {
    local script_path="$1"
    
    if [[ "$EXECUTION_MODE" == "local" ]]; then
        run_script_local "$script_path"
    else
        run_script_remote "$script_path"
    fi
}

run_script_local() {
    local script_path="$1"

    clear
    show_ascii_art

    __display_script_info__ "$script_path" "$(display_path "$script_path")"

    __line_rgb__ "=== Enter parameters for $(display_path "$script_path") (type 'c' to cancel or leave empty to run no-args):" 200 200 0
    printf "\033[38;2;150;150;150mTip: Use arrow keys to navigate, Home/End to jump, Ctrl+U to clear all and Ctrl+K to clear to end\033[0m\n"
    read -e -r param_line

    if [ "$param_line" = "c" ]; then
        return
    fi

    echo
    __line_rgb__ "=== Running: $(display_path "$script_path") $param_line ===" 200 200 0

    IFS=' ' read -r -a param_array <<<"$param_line"
    param_line=$(echo "$param_line" | tr -d '\r')

    mkdir -p .log
    touch .log/out.log

    export UTILITYPATH="$(realpath ./Utilities)"

    escaped_args=()
    for arg in "${param_array[@]}"; do
        escaped_args+=("$(printf '%q' "$arg")")
    done
    cmd_string="$(printf '%s ' "${escaped_args[@]}")"
    cmd_string="bash ${script_path} ${cmd_string}"

    script -q -c "$cmd_string" .log/out.log

    declare -a output_lines
    # Strip ANSI escape sequences including clear screen codes
    mapfile -t output_lines < <(sed '/^Script started on /d; /^Script done on /d' .log/out.log | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b\[?[0-9]*[hl]//g; s/\x1b\[[0-9;]*m//g')
    rm .log/out.log

    LAST_SCRIPT="$(display_path "$script_path")"

    local total_lines="${#output_lines[@]}"
    if ((total_lines <= 12)); then
        LAST_OUTPUT="$(printf '%s\n' "${output_lines[@]}")"
    else
        local truncated_output=""
        for ((i = 0; i < 3; i++)); do
            truncated_output+="${output_lines[$i]}"
            truncated_output+=$'\n'
        done
        truncated_output+="...\n"
        local start_index=$((total_lines - 9))
        for ((i = start_index; i < total_lines; i++)); do
            truncated_output+="${output_lines[$i]}"
            truncated_output+=$'\n'
        done
        LAST_OUTPUT="$truncated_output"
    fi

    echo
    __line_rgb__ "Press Enter to continue." 0 255 0
    read -r
}

run_script_remote() {
    local script_path="$1"
    
    clear
    show_ascii_art
    
    local display_path_result
    display_path_result=$(display_path "$script_path") || {
        echo "Error: Failed to get display path"
        return 1
    }
    
    set +e
    __display_script_info__ "$script_path" "$display_path_result"
    set -e
    
    # Prompt for parameters
    local param_line=""
    if ! __prompt_for_params__ "$display_path_result"; then
        return
    fi
    
    echo
    echo "Selected script: $(display_path "$script_path")"
    if [[ -n "$param_line" ]]; then
        echo "Parameters: $param_line"
    fi
    echo
    
    # Get relative script path and directory
    local script_relative="${script_path#$BASE_DIR/}"
    local script_dir_relative
    script_dir_relative=$(dirname "$script_relative")
    
    # Execute on remote target(s)
    __execute_remote_script__ "$script_path" "$display_path_result" "$script_relative" "$script_dir_relative" "$param_line"
    
    echo
    __line_rgb__ "Press Enter to continue." 0 255 0
    read -r
}

###############################################################################
# DIRECTORY NAVIGATOR
###############################################################################
navigate() {
    local current_dir="$1"

    while true; do
        clear
        show_ascii_art
        echo -n "CURRENT DIRECTORY: "
        __line_rgb__ "./$(display_path "$current_dir")" 0 255 0
        echo
        echo "Folders and scripts:"
        echo "----------------------------------------"

        mapfile -t dirs < <(find "$current_dir" -mindepth 1 -maxdepth 1 -type d ! -name ".*" | sort)
        mapfile -t scripts < <(find "$current_dir" -mindepth 1 -maxdepth 1 -type f -name "*.sh" ! -name ".*" | sort)

        local index=1
        declare -A menu_map=()

        # List directories
        for d in "${dirs[@]}"; do
            local dname="$(basename "$d")"
            __line_rgb__ "$index) $dname/" 0 200 200
            menu_map[$index]="$d"
            ((index++))
        done

        # List scripts
        for s in "${scripts[@]}"; do
            local sname
            sname="$(basename "$s")"
            __line_rgb__ "$index) $sname" 100 200 100
            menu_map[$index]="$s"
            ((index++))
        done

        echo
        echo "----------------------------------------"
        echo
        echo "Type 'h<number>' to show script comments."
        echo "Type 'b' to go up one directory."
        echo "Type 'l' to change log level (remote execution only)."
        echo "Type 'h' or '?' for manuals and help."
        echo "Type 'e' to exit."
        echo
        echo "----------------------------------------"

        if [ -n "$LAST_OUTPUT" ]; then
            echo "Last Script Called: $LAST_SCRIPT"
            echo "Output (truncated if large):"
            echo "$LAST_OUTPUT"
            echo
            echo "----------------------------------------"
        fi


        echo -n "Enter choice: "

        IFS= read -r choice

        # 'b' => go up
        if [[ "$choice" == "b" ]]; then
            if [ "$current_dir" = "$BASE_DIR" ]; then
                __line_rgb__ "Exiting..." 255 0 0
                exit 0
            else
                echo "Going up..."
                return
            fi
        fi

        # 'e' => exit
        if [[ "$choice" == "e" ]]; then
            __line_rgb__ "Exiting..." 255 0 0
            exit 0
        fi

        # 'h' or '?' => show manual system
        if [[ "$choice" == "h" ]] || [[ "$choice" == "?" ]]; then
            __manual_menu__
            continue
        fi

        # 'l' => change log level (remote execution only)
        if [[ "$choice" == "l" ]]; then
            if [[ "$EXECUTION_MODE" == "local" ]]; then
                echo
                __line_rgb__ "Log level setting only applies to remote execution" 255 200 0
                echo "Press Enter to continue..."
                read -r
            else
                clear
                show_ascii_art
                echo "Current log level: $REMOTE_LOG_LEVEL"
                echo
                echo "Select log level for remote script execution:"
                echo "----------------------------------------"
                __line_rgb__ "1) DEBUG   - All messages including trace and debug (very verbose)" 100 100 255
                __line_rgb__ "2) INFO    - Informational messages, warnings, and errors (default)" 0 255 0
                __line_rgb__ "3) WARN    - Warnings and errors only" 255 200 0
                __line_rgb__ "4) ERROR   - Errors only (quietest)" 255 100 100
                echo
                echo "Note: All output is always saved to log files regardless of level"
                echo
                echo -n "Enter choice (1-4): "
                read -r log_choice
                
                case "$log_choice" in
                    1) REMOTE_LOG_LEVEL="DEBUG" ;;
                    2) REMOTE_LOG_LEVEL="INFO" ;;
                    3) REMOTE_LOG_LEVEL="WARN" ;;
                    4) REMOTE_LOG_LEVEL="ERROR" ;;
                    *)
                        echo "Invalid choice. Log level unchanged."
                        sleep 1
                        ;;
                esac
                
                if [[ "$log_choice" =~ ^[1-4]$ ]]; then
                    __line_rgb__ "Log level set to: $REMOTE_LOG_LEVEL" 0 255 0
                    sleep 1
                fi
            fi
            continue
        fi

        # 'hN' => show top comments
        if [[ "$choice" =~ ^h[0-9]+$ ]]; then
            local num="${choice#h}"
            if [ -n "${menu_map[$num]}" ]; then
                local selected_path="${menu_map[$num]}"
                if [ -d "$selected_path" ]; then
                    echo "Can't show top comments for a directory. Press Enter to continue."
                    read -r
                else
                    show_top_comments "$selected_path"
                fi
            else
                echo "Invalid selection. Press Enter to continue."
                read -r
            fi
            continue
        fi

        # Numeric => either a directory or a script
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [ -z "${menu_map[$choice]}" ]; then
                echo "Invalid numeric choice. Press Enter to continue."
                read -r
                continue
            fi
            local selected_item="${menu_map[$choice]}"

            if [ -d "$selected_item" ]; then
                navigate "$selected_item"
            else
                run_script "$selected_item"
            fi
            continue
        fi

        echo "Invalid input. Press Enter to continue."
        read -r
    done
}

###############################################################################
# MAIN
###############################################################################

./MakeScriptsExecutable.sh

# Select execution mode before starting navigation
select_execution_mode

navigate "$BASE_DIR"
