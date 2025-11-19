#!/bin/bash
#
# NodeSelection.sh
#
# Utilities for selecting and configuring remote nodes for execution
#
# Functions:
#   __select_nodes__          - Select nodes (single or multiple) with unified interface
#   __get_node_password__     - Prompt for node password(s)
#   __load_available_nodes__  - Load nodes from nodes.json
#   __display_node_menu__     - Display node selection menu
#
# Function Index:
#   - __load_available_nodes__
#   - __display_node_menu__
#   - __get_node_passwords__
#   - __select_nodes__
#

# Load available nodes from nodes.json
# Sets: AVAILABLE_NODES associative array (name => ip)
# Returns: 0 if nodes loaded, 1 if not
__load_available_nodes__() {
    local nodes_file="${1:-nodes.json}"

    declare -gA AVAILABLE_NODES=()

    if [[ ! -f "$nodes_file" ]]; then
        return 1
    fi

    if ! command -v jq &>/dev/null; then
        return 1
    fi

    while IFS= read -r line; do
        local node_name node_ip
        node_name=$(echo "$line" | jq -r '.name')
        node_ip=$(echo "$line" | jq -r '.ip')
        AVAILABLE_NODES["$node_name"]="$node_ip"
    done < <(jq -c '.nodes[]' "$nodes_file" 2>/dev/null || true)

    [[ ${#AVAILABLE_NODES[@]} -gt 0 ]]
}

# Display node selection menu
# Args: none (uses AVAILABLE_NODES global)
# Returns: menu associative array via stdout
__display_node_menu__() {
    local i=1
    declare -A node_menu=()

    for node_name in "${!AVAILABLE_NODES[@]}"; do
        local node_ip="${AVAILABLE_NODES[$node_name]}"
        __line_rgb__ "  $i) $node_name ($node_ip)" 0 200 200
        node_menu[$i]="$node_name:$node_ip"
        ((i += 1))
    done

    # Export the menu for caller to use
    declare -p node_menu
}

# Get password for node(s)
# Args: mode (single|multi) node_list_array
# Sets: NODE_PASSWORDS associative array (name => password)
__get_node_passwords__() {
    local mode="$1"
    shift
    local nodes=("$@")

    declare -gA NODE_PASSWORDS=()

    if [[ "$mode" == "single" ]]; then
        local node_name="${nodes[0]}"
        read -rsp "Enter password for $node_name: " node_pass
        echo
        NODE_PASSWORDS["$node_name"]="$node_pass"
    else
        # Multi-node
        read -rp "Same password for all nodes? [y/N]: " same_pass

        if [[ "$same_pass" =~ ^[Yy]$ ]]; then
            read -rsp "Enter password for all nodes: " shared_pass
            echo
            for node in "${nodes[@]}"; do
                NODE_PASSWORDS["$node"]="$shared_pass"
            done
        else
            for node in "${nodes[@]}"; do
                read -rsp "Enter password for $node: " node_pass
                echo
                NODE_PASSWORDS["$node"]="$node_pass"
            done
        fi
    fi
}

# Unified node selection interface
# Args: mode (single|multi)
# Sets: SELECTED_NODES array and NODE_PASSWORDS associative array
# Returns: 0 on success, 1 on cancel/error
__select_nodes__() {
    local mode="$1" # single or multi

    declare -gA SELECTED_NODES=()

    if [[ ${#AVAILABLE_NODES[@]} -eq 0 ]]; then
        # No nodes in JSON, prompt for manual entry
        echo "No nodes found in nodes.json"
        echo
        read -rp "Enter node IP manually: " manual_ip
        read -rp "Enter node name: " manual_name

        SELECTED_NODES["$manual_name"]="$manual_ip"
        __get_node_passwords__ "single" "$manual_name"
        return 0
    fi

    # Display available nodes
    eval "$(__display_node_menu__)"

    echo
    echo "----------------------------------------"
    echo

    if [[ "$mode" == "single" ]]; then
        echo "Type 'm' to enter manually"
        echo "Type 'b' to go back"
        echo
        read -rp "Enter choice: " node_choice

        if [[ "$node_choice" == "b" ]]; then
            return 1
        elif [[ "$node_choice" == "m" ]]; then
            read -rp "Enter node IP: " manual_ip
            read -rp "Enter node name: " manual_name
            SELECTED_NODES["$manual_name"]="$manual_ip"
            __get_node_passwords__ "single" "$manual_name"
            return 0
        elif [[ -n "$node_choice" && -n "${node_menu[$node_choice]:-}" ]]; then
            IFS=':' read -r selected_name selected_ip <<<"${node_menu[$node_choice]}"
            SELECTED_NODES["$selected_name"]="$selected_ip"
            __get_node_passwords__ "single" "$selected_name"
            return 0
        else
            echo "Invalid choice!"
            sleep 1
            return 1
        fi
    else
        # Multi-node mode
        echo "Enter node numbers (comma-separated, e.g., 1,3,5) or:"
        echo "  'all' - select all nodes"
        echo "  'b' - go back"
        echo
        read -rp "Nodes: " node_selection

        if [[ "$node_selection" == "b" ]]; then
            return 1
        fi

        declare -a selected_node_names=()

        if [[ "$node_selection" == "all" ]]; then
            for node_name in "${!AVAILABLE_NODES[@]}"; do
                node_ip="${AVAILABLE_NODES[$node_name]}"
                SELECTED_NODES["$node_name"]="$node_ip"
                selected_node_names+=("$node_name")
            done
        else
            IFS=',' read -ra selected_nums <<<"$node_selection"
            for num in "${selected_nums[@]}"; do
                num=$(echo "$num" | xargs)
                if [[ -n "$num" && -n "${node_menu[$num]:-}" ]]; then
                    IFS=':' read -r node_name node_ip <<<"${node_menu[$num]}"
                    SELECTED_NODES["$node_name"]="$node_ip"
                    selected_node_names+=("$node_name")
                fi
            done
        fi

        if [[ ${#SELECTED_NODES[@]} -eq 0 ]]; then
            echo "No valid nodes selected!"
            sleep 2
            return 1
        fi

        echo
        echo "Selected ${#SELECTED_NODES[@]} node(s)"
        echo

        __get_node_passwords__ "multi" "${selected_node_names[@]}"
        return 0
    fi
}
