#!/bin/bash
#
# BulkAddFirewallLXCVM.sh
#
# Adds a datacenter firewall security group to VMs/containers and enables firewall.
# Automatically detects resource type and configures appropriate interfaces.
#
# Usage:
#   BulkAddFirewallLXCVM.sh <start_vmid> <end_vmid> <security_group>
#
# Arguments:
#   start_vmid     - Starting VM/CT ID
#   end_vmid       - Ending VM/CT ID
#   security_group - Datacenter security group name
#
# Examples:
#   BulkAddFirewallLXCVM.sh 100 110 MySecurityGroup
#
# Function Index:
#   - enable_firewall_lxc
#   - enable_firewall_vm
#   - configure_resource_firewall
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
__parse_args__ "start_vmid:vmid end_vmid:vmid security_group:string" "$@"

# --- enable_firewall_lxc -----------------------------------------------------
enable_firewall_lxc() {
    local vmid="$1"
    local config_lines
    config_lines=$(pct config "$vmid" 2>/dev/null)

    while read -r line; do
        if [[ "$line" =~ ^net([0-9]+):.*gw= ]]; then
            local nic_index="${BASH_REMATCH[1]}"
            local net_line
            net_line=$(echo "$line" | sed -E 's/^net[0-9]+: //')

            if [[ "$net_line" =~ firewall= ]]; then
                net_line=$(echo "$net_line" | sed -E 's/,?firewall=[^,]*/,firewall=1/g')
            else
                net_line="${net_line},firewall=1"
            fi

            pct set "$vmid" -net"${nic_index}" "$net_line" &>/dev/null
        fi
    done <<< "$config_lines"

    pct set "$vmid" --features "firewall=1" &>/dev/null
}

# --- enable_firewall_vm ------------------------------------------------------
enable_firewall_vm() {
    local vmid="$1"
    local net_line
    net_line=$(qm config "$vmid" 2>/dev/null | grep '^net0:' | sed -E 's/^net0: //')

    if [[ -n "$net_line" ]]; then
        if [[ "$net_line" =~ firewall= ]]; then
            net_line=$(echo "$net_line" | sed -E 's/,?firewall=[^,]*/,firewall=1/g')
        else
            net_line="${net_line},firewall=1"
        fi
        qm set "$vmid" --net0 "$net_line" &>/dev/null
    fi
}

# --- configure_resource_firewall ---------------------------------------------
configure_resource_firewall() {
    local vmid="$1"

    if pct config "$vmid" &>/dev/null || qm config "$vmid" &>/dev/null; then
        cat <<EOF >"/etc/pve/firewall/${vmid}.fw"
[OPTIONS]
enable: 1

[RULES]
GROUP ${SECURITY_GROUP}
EOF
        return 0
    else
        return 1
    fi
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __info__ "Configuring firewall for VMs/CTs ${START_VMID} to ${END_VMID}"
    __info__ "Security group: ${SECURITY_GROUP}"

    local success=0
    local failed=0

    for (( vmid=START_VMID; vmid<=END_VMID; vmid++ )); do
        __update__ "Processing ${vmid}"

        if pct status "$vmid" &>/dev/null; then
            # LXC container
            if enable_firewall_lxc "$vmid" && configure_resource_firewall "$vmid"; then
                __ok__ "CT ${vmid} configured"
                ((success++))
            else
                __warn__ "Failed to configure CT ${vmid}"
                ((failed++))
            fi
        elif qm config "$vmid" &>/dev/null; then
            # VM
            if enable_firewall_vm "$vmid" && configure_resource_firewall "$vmid"; then
                __ok__ "VM ${vmid} configured"
                ((success++))
            else
                __warn__ "Failed to configure VM ${vmid}"
                ((failed++))
            fi
        else
            __update__ "Skipped ${vmid} (not found)"
        fi
    done

    echo
    __info__ "Firewall Configuration Summary:"
    __info__ "  Configured: ${success}"
    [[ $failed -gt 0 ]] && __warn__ "  Failed: ${failed}" || __info__ "  Failed: ${failed}"

    [[ $failed -gt 0 ]] && exit 1
    __ok__ "Firewall configuration completed!"
}

main

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
