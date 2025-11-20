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
declare -gA NODE_SSH_KEYS=() # Track SSH key status
declare -g NODES_FILE="nodes.json"
declare -g REMOTE_TEMP_DIR="/tmp/ProxmoxScripts_gui"
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
        while IFS= read -r line; do
            local node_name node_ip ssh_keys
            node_name=$(echo "$line" | jq -r '.name')
            node_ip=$(echo "$line" | jq -r '.ip')
            ssh_keys=$(echo "$line" | jq -r 'if has("ssh_keys") then (.ssh_keys | tostring) else "unknown" end')
            AVAILABLE_NODES["$node_name"]="$node_ip"
            NODE_SSH_KEYS["$node_name"]="$ssh_keys"
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
# Args: node_name node_ip password
__add_remote_target__() {
    local node_name="$1"
    local node_ip="$2"
    local password="$3"

    REMOTE_TARGETS+=("$node_name:$node_ip")
    NODE_PASSWORDS["$node_name"]="$password"
}

# Clear all remote targets
__clear_remote_targets__() {
    REMOTE_TARGETS=()
    NODE_PASSWORDS=()
}

# Get node IP by name
# Args: node_name
# Returns: IP address or empty string
__get_node_ip__() {
    local node_name="$1"
    echo "${AVAILABLE_NODES[$node_name]:-}"
}

# Check if node exists
# Args: node_name
# Returns: 0 if exists, 1 if not
__node_exists__() {
    local node_name="$1"
    [[ -v AVAILABLE_NODES[$node_name] ]]
}

# Get all available node names
__get_available_nodes__() {
    printf '%s\n' "${!AVAILABLE_NODES[@]}"
}

# Count available nodes
__count_available_nodes__() {
    echo "${#AVAILABLE_NODES[@]}"
}

# Check if node has SSH keys configured (from cache or test)
# Args: node_ip node_name
# Returns: "true" if keys work, "false" if not, "unknown" if not tested
__has_ssh_keys__() {
    local node_ip="$1"
    local node_name="${2:-}"

    # Check cache first if node_name provided
    if [[ -n "$node_name" ]] && [[ "${NODE_SSH_KEYS[$node_name]:-unknown}" != "unknown" ]]; then
        echo "${NODE_SSH_KEYS[$node_name]}"
        return 0
    fi

    # Test SSH connection
    if ssh -o BatchMode=yes -o ConnectTimeout=2 root@$node_ip echo "test" &>/dev/null 2>&1; then
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
    local temp_file=$(mktemp)
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
        echo -n "  Checking $node_name ($node_ip)... "

        local has_keys=$(__has_ssh_keys__ "$node_ip" "$node_name")

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

