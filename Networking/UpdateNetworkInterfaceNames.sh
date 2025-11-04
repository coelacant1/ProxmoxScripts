#!/bin/bash
#
# UpdateNetworkInterfaceNames.sh
#
# Updates /etc/network/interfaces to match current interface names from 'ip a'.
#
# Usage:
#   UpdateNetworkInterfaceNames.sh
#
# Examples:
#   UpdateNetworkInterfaceNames.sh
#
# Function Index:
#   - update_interface_name
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- update_interface_name ---------------------------------------------------
update_interface_name() {
    local old_name="$1"
    local new_name="$2"
    local config_file="$3"

    if grep -q "\b${old_name}\b" "$config_file"; then
        sed -i "s/\b${old_name}\b/${new_name}/g" "$config_file"
        __ok__ "Updated: $old_name => $new_name"
        return 0
    else
        __info__ "Skipped: $old_name not found"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    local config_file="/etc/network/interfaces"
    local backup_file="${config_file}.bak-$(date +%Y%m%d%H%M%S)"

    if [[ ! -f "$config_file" ]]; then
        __err__ "Network interfaces file not found: $config_file"
        exit 1
    fi

    __info__ "Updating network interface names"

    # Create backup
    if cp "$config_file" "$backup_file" 2>&1; then
        __ok__ "Backed up to: $backup_file"
    else
        __err__ "Failed to create backup"
        exit 1
    fi

    # Scan interfaces
    __info__ "Scanning current interfaces"

    declare -A interface_map
    declare -A base_name_count

    while read -r ip_line; do
        if [[ $ip_line =~ ^[0-9]+:\ ([^:]+): ]]; then
            local interface="${BASH_REMATCH[1]}"

            # Skip special interfaces
            if [[ "$interface" == "lo" ]] || [[ "$interface" == *"tap"* ]] || \
               [[ "$interface" == *"veth"* ]] || [[ "$interface" == *"fwbr"* ]]; then
                continue
            fi

            # Derive base name
            local base_name
            base_name=$(echo "$interface" | sed -E 's/^en?p[0-9]//; s/[0-9]+$//')

            if [[ -n "$base_name" ]]; then
                if [[ -z "${interface_map[$base_name]:-}" ]]; then
                    interface_map[$base_name]="$interface"
                    base_name_count[$base_name]=1
                else
                    local count="${base_name_count[$base_name]}"
                    base_name_count[$base_name]=$((count + 1))
                    __warn__ "Multiple interfaces for base: $base_name"
                fi
            fi
        fi
    done < <(ip a)

    if [[ ${#interface_map[@]} -eq 0 ]]; then
        __warn__ "No usable network interfaces found"
        exit 0
    fi

    __info__ "Found ${#interface_map[@]} interface mapping(s)"

    # Update interface names
    local updated=0
    for base_name in "${!interface_map[@]}"; do
        local old_name="$base_name"
        local new_name="${interface_map[$base_name]}"

        if [[ "$old_name" == "$new_name" ]]; then
            continue
        fi

        if update_interface_name "$old_name" "$new_name" "$config_file"; then
            ((updated++))
        fi
    done

    echo
    if [[ $updated -gt 0 ]]; then
        __ok__ "Updated $updated interface name(s)"
        __warn__ "Network restart required to apply changes"
        __info__ "Commands:"
        __info__ "  systemctl restart networking"
        __info__ "  OR ifreload -a"
    else
        __info__ "No interface names needed updating"
    fi

    __info__ "Review configuration: $config_file"
    __info__ "Backup available: $backup_file"
}

main

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
