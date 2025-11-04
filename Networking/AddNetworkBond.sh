#!/bin/bash
#
# AddNetworkBond.sh
#
# Configures network bonding and VLAN bridging in Proxmox network interfaces.
#
# Usage:
#   AddNetworkBond.sh <bond_base> <vlan_id>
#
# Arguments:
#   bond_base - Base bond name (e.g., bond0)
#   vlan_id - VLAN ID to configure
#
# Examples:
#   AddNetworkBond.sh bond0 10
#   AddNetworkBond.sh bond1 20
#
# Function Index:
#   - insert_sorted_config
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- insert_sorted_config ----------------------------------------------------
insert_sorted_config() {
    local insert_name="$1"
    local insert_config="$2"
    local config_type="$3"
    local config_file="$4"

    local pattern="iface ${config_type}[0-9]+"
    local config_block
    config_block=$(awk "/^auto $pattern/,/^\$/" RS= "$config_file")

    if echo "$config_block" | grep -q "^auto $insert_name\$"; then
        __warn__ "$insert_name already exists in configuration"
        return 1
    fi

    local sorted_block
    sorted_block=$(echo -e "$config_block\nauto $insert_name\n$insert_config" | sort -V)

    awk -v pat="^auto $pattern\$" -v sorted="$sorted_block" '
      /^auto '"$config_type"'[0-9]+/,/^$/ {
        if (!p) {
          print sorted
          p=1
        }
        next
      }
      { print }
    ' RS= ORS='\n\n' "$config_file" > "${config_file}.tmp"

    mv "${config_file}.tmp" "$config_file"
    return 0
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __install_or_prompt__ "ifenslave"

    if [[ $# -lt 2 ]]; then
        __err__ "Missing required arguments"
        echo "Usage: $0 <bond_base> <vlan_id>"
        exit 64
    fi

    local bond_base="$1"
    local vlan_id="$2"
    local bond_name="${bond_base}.${vlan_id}"
    local vmbr_name="vmbr${vlan_id}"
    local config_file="/etc/network/interfaces"

    if [[ ! -f "$config_file" ]]; then
        __err__ "Network interfaces file not found: $config_file"
        exit 1
    fi

    __info__ "Configuring network bond"
    __info__ "  Bond: $bond_name"
    __info__ "  VLAN ID: $vlan_id"
    __info__ "  Bridge: $vmbr_name"

    # Backup config file
    local backup_file="${config_file}.bak-$(date +%Y%m%d%H%M%S)"
    if cp "$config_file" "$backup_file" 2>&1; then
        __ok__ "Backed up to: $backup_file"
    else
        __err__ "Failed to create backup"
        exit 1
    fi

    # Create configuration blocks
    local bond_config
    bond_config="auto $bond_name
iface $bond_name inet manual
    vlan-raw-device $bond_base"

    local vmbr_config
    vmbr_config="auto $vmbr_name
iface $vmbr_name inet manual
    bridge_ports $bond_name
    bridge_stp off
    bridge_fd 0"

    # Insert configurations
    __update__ "Adding bond configuration"
    if insert_sorted_config "$bond_name" "$bond_config" "$bond_base" "$config_file"; then
        __ok__ "Bond configuration added"
    fi

    __update__ "Adding bridge configuration"
    if insert_sorted_config "$vmbr_name" "$vmbr_config" "vmbr" "$config_file"; then
        __ok__ "Bridge configuration added"
    fi

    echo
    __ok__ "Network bond configuration completed!"
    __warn__ "Network restart required to apply changes"
    __info__ "Commands:"
    __info__ "  systemctl restart networking"
    __info__ "  OR ifreload -a"
    __info__ "Review configuration: $config_file"

    __prompt_keep_installed_packages__
}

main "$@"

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
