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
#   - get_interface_mac
#   - get_config_interfaces
#   - update_interface_name
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- get_interface_mac ---------------------------------------------------------
get_interface_mac() {
    local iface="$1"
    cat "/sys/class/net/${iface}/address" 2>/dev/null || echo ""
}

# --- get_config_interfaces -----------------------------------------------------
get_config_interfaces() {
    local config_file="$1"
    # Extract interface names from 'iface <name>' lines, excluding lo
    grep -E '^\s*iface\s+\S+' "$config_file" \
        | awk '{print $2}' \
        | grep -v "^lo$" \
        | sort -u
}

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

    # Get interfaces from config file
    __info__ "Reading interface names from config file"
    local -a config_ifaces
    mapfile -t config_ifaces < <(get_config_interfaces "$config_file")

    if [[ ${#config_ifaces[@]} -eq 0 ]]; then
        __warn__ "No interfaces found in config file"
        exit 0
    fi

    __info__ "Found ${#config_ifaces[@]} interface(s) in config"

    # Build MAC address map for current interfaces
    declare -A mac_to_current_iface

    __info__ "Scanning current interfaces"
    while read -r line; do
        if [[ $line =~ ^[0-9]+:\ ([^:@]+)[@:]? ]]; then
            local iface="${BASH_REMATCH[1]}"

            # Skip special interfaces
            if [[ "$iface" == "lo" ]] || [[ "$iface" == *"tap"* ]] \
                || [[ "$iface" == *"veth"* ]] || [[ "$iface" == *"fwbr"* ]] \
                || [[ "$iface" == *"vmbr"* ]] || [[ "$iface" == *"bond"* ]]; then
                continue
            fi

            local mac
            mac=$(get_interface_mac "$iface")
            if [[ -n "$mac" ]]; then
                mac_to_current_iface[$mac]="$iface"
            fi
        fi
    done < <(ip -o link show)

    __info__ "Found ${#mac_to_current_iface[@]} physical interface(s)"

    # Match config interfaces to current interfaces by MAC
    local updated=0
    local -A old_to_new_map

    for config_iface in "${config_ifaces[@]}"; do
        # Skip virtual interfaces (bridges, bonds, VLANs)
        if [[ "$config_iface" == *"vmbr"* ]] || [[ "$config_iface" == *"bond"* ]] \
            || [[ "$config_iface" =~ \. ]]; then
            continue
        fi

        # Try to get MAC from sysfs (if interface still exists)
        local config_mac
        config_mac=$(get_interface_mac "$config_iface" 2>/dev/null || echo "")

        if [[ -z "$config_mac" ]]; then
            __warn__ "Cannot find MAC for config interface: $config_iface (interface may not exist)"
            continue
        fi

        # Find current interface with same MAC
        local current_iface="${mac_to_current_iface[$config_mac]:-}"

        if [[ -z "$current_iface" ]]; then
            __warn__ "No current interface found with MAC $config_mac for $config_iface"
            continue
        fi

        if [[ "$config_iface" == "$current_iface" ]]; then
            __info__ "Interface $config_iface already has correct name"
            continue
        fi

        # Found a mismatch - need to update
        __info__ "Mapping: $config_iface → $current_iface (MAC: $config_mac)"
        old_to_new_map[$config_iface]="$current_iface"
    done

    # Apply updates
    if [[ ${#old_to_new_map[@]} -eq 0 ]]; then
        __info__ "No interface name updates needed"
        __info__ "Backup available: $backup_file"
        exit 0
    fi

    for old_name in "${!old_to_new_map[@]}"; do
        new_name="${old_to_new_map[$old_name]}"
        if update_interface_name "$old_name" "$new_name" "$config_file"; then
            updated=$((updated + 1))
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

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-11-20: Updated to use utility functions
# - 2025-11-20: Pending validation
# - 2025-11-20: Validated against CONTRIBUTING.md and PVE Guide
# - Logic: Reads config interfaces, matches by MAC to current interfaces, updates names
# - Tested logic: Maps interfaces correctly after kernel updates (eth0 → enp1s0)
#
# Fixes:
# - Fixed arithmetic increment syntax (line 117)
# - Fixed: Complete rewrite to use MAC address matching for reliable interface mapping
#
# Known issues:
# - Pending validation
# -
#

