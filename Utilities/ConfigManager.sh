#!/bin/bash
#
# ConfigManager.sh
#
# Manages GUI configuration including execution modes, nodes, and settings.
# Centralizes all configuration-related functionality.
#
# Function Index:
#   - __init_config__
#   - __set_execution_mode__
#   - __add_remote_target__
#   - __clear_remote_targets__
#   - __get_node_ip__
#   - __get_node_username__
#   - __get_node_port__
#   - __node_exists__
#   - __get_available_nodes__
#   - __count_available_nodes__
#   - __has_ssh_keys__
#   - __update_node_ssh_keys__
#   - __scan_ssh_keys__
#   - __set_remote_log_level__
#   - __get_remote_log_level__
#

# Global configuration variables
declare -g EXECUTION_MODE="local"
declare -g EXECUTION_MODE_DISPLAY="Local System"
declare -g TARGET_DISPLAY="This System"
declare -ga REMOTE_TARGETS=()
declare -gA NODE_PASSWORDS=()
declare -gA AVAILABLE_NODES=()
declare -ga NODE_ORDER=()  # Preserve order from nodes.json
declare -gA NODE_USERNAMES=() # Track username for each node
declare -gA NODE_PORTS=() # Track SSH port for each node
declare -gA NODE_SSH_KEYS=() # Track SSH key status
declare -g NODES_FILE="nodes.json"
declare -g REMOTE_TEMP_DIR="/tmp/ProxmoxScripts_gui"
declare -g DEFAULT_USERNAME="root" # Default username for nodes
declare -g DEFAULT_PORT="22" # Default SSH port
# Only set default if not already set (e.g., from command-line flags)
if [[ -z "${REMOTE_LOG_LEVEL:-}" ]]; then
    declare -g REMOTE_LOG_LEVEL="INFO"
fi

# Initialize configuration from nodes.json
__init_config__() {
    # Create nodes.json from template if it doesn't exist
    if [[ ! -f "$NODES_FILE" ]] && [[ -f "${NODES_FILE}.template" ]]; then
        if ! cp "${NODES_FILE}.template" "$NODES_FILE"; then
            echo "Error: Failed to create $NODES_FILE from template" >&2
            return 1
        fi
    fi

    if [[ -f "$NODES_FILE" ]] && command -v jq &>/dev/null; then
        # Reset order array
        NODE_ORDER=()
        
        while IFS= read -r line; do
            local node_name node_ip ssh_keys node_username node_port
            node_name=$(echo "$line" | jq -r '.name')
            node_ip=$(echo "$line" | jq -r '.ip')
            ssh_keys=$(echo "$line" | jq -r 'if has("ssh_keys") then (.ssh_keys | tostring) else "unknown" end')
            node_username=$(echo "$line" | jq -r 'if has("username") then .username else "'"$DEFAULT_USERNAME"'" end')
            node_port=$(echo "$line" | jq -r 'if has("port") then (.port | tostring) else "'"$DEFAULT_PORT"'" end')
            AVAILABLE_NODES["$node_name"]="$node_ip"
            NODE_SSH_KEYS["$node_name"]="$ssh_keys"
            NODE_USERNAMES["$node_name"]="$node_username"
            NODE_PORTS["$node_name"]="$node_port"
            NODE_ORDER+=("$node_name")  # Preserve order from JSON
        done < <(jq -c '.nodes[]' "$NODES_FILE" 2>/dev/null || true)
    fi
}

# Set execution mode
# Args: mode (local|single-remote|multi-remote)
__set_execution_mode__() {
    local mode="$1"
    EXECUTION_MODE="$mode"

    case "$mode" in
        local)
            EXECUTION_MODE_DISPLAY="Local System"
            TARGET_DISPLAY="This System"
            ;;
        single-remote)
            EXECUTION_MODE_DISPLAY="Single Remote"
            if [[ ${#REMOTE_TARGETS[@]} -gt 0 ]]; then
                local target="${REMOTE_TARGETS[0]}"
                local node_name="${target%%:*}"
                local node_ip="${target##*:}"
                TARGET_DISPLAY="$node_name ($node_ip)"
            else
                TARGET_DISPLAY="Not configured"
            fi
            ;;
        multi-remote)
            EXECUTION_MODE_DISPLAY="Multiple Remote"
            TARGET_DISPLAY="${#REMOTE_TARGETS[@]} nodes"
            ;;
    esac
}

# Add remote target
# Args: node_name node_ip password [username]
__add_remote_target__() {
    local node_name="$1"
    local node_ip="$2"
    local password="$3"
    local username="${4:-$DEFAULT_USERNAME}"

    REMOTE_TARGETS+=("$node_name:$node_ip")
    NODE_PASSWORDS["$node_name"]="$password"
    NODE_USERNAMES["$node_name"]="$username"
}

# Clear all remote targets
__clear_remote_targets__() {
    REMOTE_TARGETS=()
    NODE_PASSWORDS=()
    NODE_USERNAMES=()
}

# Get node IP by name
# Args: node_name
# Returns: IP address or empty string
__get_node_ip__() {
    local node_name="$1"
    echo "${AVAILABLE_NODES[$node_name]:-}"
}

# Get node username by name
# Args: node_name
# Returns: username or default username
__get_node_username__() {
    local node_name="$1"
    echo "${NODE_USERNAMES[$node_name]:-$DEFAULT_USERNAME}"
}

# Get node port by name
# Args: node_name
# Returns: port number or default port (22)
__get_node_port__() {
    local node_name="$1"
    echo "${NODE_PORTS[$node_name]:-$DEFAULT_PORT}"
}

# Check if node exists
# Args: node_name
# Returns: 0 if exists, 1 if not
__node_exists__() {
    local node_name="$1"
    [[ -v AVAILABLE_NODES[$node_name] ]]
}

# Get all available node names (in order from nodes.json)
__get_available_nodes__() {
    printf '%s\n' "${NODE_ORDER[@]}"
}

# Count available nodes
__count_available_nodes__() {
    echo "${#AVAILABLE_NODES[@]}"
}

# Check if node has SSH keys configured (from cache or test)
# Args: node_ip username node_name [port]
# Returns: "true" if keys work, "false" if not, "unknown" if not tested
__has_ssh_keys__() {
    local node_ip="$1"
    local username="${2:-$DEFAULT_USERNAME}"
    local node_name="${3:-}"
    local port="${4:-$DEFAULT_PORT}"

    # Check cache first if node_name provided
    if [[ -n "$node_name" ]] && [[ "${NODE_SSH_KEYS[$node_name]:-unknown}" != "unknown" ]]; then
        echo "${NODE_SSH_KEYS[$node_name]}"
        return 0
    fi

    # Test SSH connection
    if ssh -o BatchMode=yes -o ConnectTimeout=2 -p "$port" "${username}@${node_ip}" echo "test" &>/dev/null 2>&1; then
        # Update cache if node_name provided
        if [[ -n "$node_name" ]]; then
            NODE_SSH_KEYS["$node_name"]="true"
        fi
        echo "true"
    else
        # Update cache if node_name provided
        if [[ -n "$node_name" ]]; then
            NODE_SSH_KEYS["$node_name"]="false"
        fi
        echo "false"
    fi
}

# Update SSH key status in nodes.json
# Args: node_name ssh_keys_status
__update_node_ssh_keys__() {
    local node_name="$1"
    local ssh_keys_status="$2"

    if [[ ! -f "$NODES_FILE" ]] || ! command -v jq &>/dev/null; then
        return 1
    fi

    # Update the JSON file
    local temp_file
    temp_file=$(mktemp)
    jq --arg name "$node_name" --argjson ssh_keys "$ssh_keys_status" \
        '(.nodes[] | select(.name == $name) | .ssh_keys) = $ssh_keys' \
        "$NODES_FILE" >"$temp_file" && mv "$temp_file" "$NODES_FILE"

    # Update in-memory cache
    NODE_SSH_KEYS["$node_name"]="$ssh_keys_status"
}

# Scan all nodes and update SSH key status
__scan_ssh_keys__() {
    echo "Scanning nodes for SSH key authentication..."
    local updated=0

    for node_name in "${!AVAILABLE_NODES[@]}"; do
        local node_ip="${AVAILABLE_NODES[$node_name]}"
        local node_username="${NODE_USERNAMES[$node_name]:-$DEFAULT_USERNAME}"
        local node_port="${NODE_PORTS[$node_name]:-$DEFAULT_PORT}"
        echo -n "  Checking $node_name ($node_username@$node_ip:$node_port)... "

        local has_keys
        has_keys=$(__has_ssh_keys__ "$node_ip" "$node_username" "$node_name" "$node_port")

        if [[ "$has_keys" == "true" ]]; then
            echo "[SSH]"
            __update_node_ssh_keys__ "$node_name" "true"
        else
            echo "password"
            __update_node_ssh_keys__ "$node_name" "false"
        fi
        ((updated += 1))
    done

    echo
    echo "Scanned $updated nodes. SSH key status updated in nodes.json"
}

# Set remote log level
# Args: level (DEBUG|INFO|WARN|ERROR)
__set_remote_log_level__() {
    REMOTE_LOG_LEVEL="$1"
}

# Get remote log level
__get_remote_log_level__() {
    echo "$REMOTE_LOG_LEVEL"
}

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2026-01-08
#
# Changes:
# - 2026-01-08: Added NODE_ORDER array to preserve node order from nodes.json
# - 2025-12-18: Added SSH port configuration support for proxy/jump host setups
# - 2025-11-24: Validated against CONTRIBUTING.md, fixed ShellCheck warnings
# - Initial version: Configuration management for GUI execution modes
#
# Fixes:
# - 2025-11-24: Fixed variable declaration/assignment separation (SC2155)
# - 2025-11-24: Fixed unquoted variable in SSH command (SC2086)
#
# Known issues:
# -
#

