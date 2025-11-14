#!/bin/bash
#
# ConfigManager.sh
#
# Manages GUI configuration including execution modes, nodes, and settings.
# Centralizes all configuration-related functionality.
#

# Global configuration variables
declare -g EXECUTION_MODE="local"
declare -g EXECUTION_MODE_DISPLAY="Local System"
declare -g TARGET_DISPLAY="This System"
declare -ga REMOTE_TARGETS=()
declare -gA NODE_PASSWORDS=()
declare -gA AVAILABLE_NODES=()
declare -g NODES_FILE="nodes.json"
declare -g REMOTE_TEMP_DIR="/tmp/ProxmoxScripts_gui"
declare -g REMOTE_LOG_LEVEL="INFO"

# Initialize configuration from nodes.json
__init_config__() {
    # Create nodes.json from template if it doesn't exist
    if [[ ! -f "$NODES_FILE" ]] && [[ -f "${NODES_FILE}.template" ]]; then
        cp "${NODES_FILE}.template" "$NODES_FILE"
    fi
    
    if [[ -f "$NODES_FILE" ]] && command -v jq &>/dev/null; then
        while IFS= read -r line; do
            local node_name node_ip
            node_name=$(echo "$line" | jq -r '.name')
            node_ip=$(echo "$line" | jq -r '.ip')
            AVAILABLE_NODES["$node_name"]="$node_ip"
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

# Set remote log level
# Args: level (DEBUG|INFO|WARN|ERROR)
__set_remote_log_level__() {
    REMOTE_LOG_LEVEL="$1"
}

# Get remote log level
__get_remote_log_level__() {
    echo "$REMOTE_LOG_LEVEL"
}
