#!/bin/bash
#
# BulkPrintVMIDMacAddresses.sh
#
# Prints MAC addresses for all VMs and containers across cluster in CSV format.
#
# Usage:
#   BulkPrintVMIDMacAddresses.sh
#
# Examples:
#   BulkPrintVMIDMacAddresses.sh
#   BulkPrintVMIDMacAddresses.sh > mac_addresses.csv
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Queries.sh
source "${UTILITYPATH}/Queries.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    __check_cluster_membership__

    # Print CSV header
    echo "Nodename,CTID/VMID,Type,MacAddress"

    local total_entries=0

    # Loop over each node directory
    for node_dir in /etc/pve/nodes/*; do
        if [[ ! -d "$node_dir" ]]; then
            continue
        fi

        local node_name
        node_name=$(basename "$node_dir")

        # Process QEMU VMs
        local qemu_dir="${node_dir}/qemu-server"
        if [[ -d "$qemu_dir" ]]; then
            for config_file in "$qemu_dir"/*.conf; do
                if [[ ! -f "$config_file" ]]; then
                    continue
                fi

                local vm_id
                vm_id=$(basename "$config_file" .conf)

                local macs
                macs=$(grep -E '^net[0-9]+:' "$config_file" \
                    | grep -Eo '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' \
                    | tr '\n' ' ' \
                    | sed 's/ *$//')

                [[ -z "$macs" ]] && macs="None"
                echo "$node_name,$vm_id,VM,$macs"
                ((total_entries++))
            done
        fi

        # Process LXC containers
        local lxc_dir="${node_dir}/lxc"
        if [[ -d "$lxc_dir" ]]; then
            for config_file in "$lxc_dir"/*.conf; do
                if [[ ! -f "$config_file" ]]; then
                    continue
                fi

                local ct_id
                ct_id=$(basename "$config_file" .conf)

                local macs
                macs=$(grep -E '^net[0-9]+:' "$config_file" \
                    | grep -Eo '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' \
                    | tr '\n' ' ' \
                    | sed 's/ *$//')

                [[ -z "$macs" ]] && macs="None"
                echo "$node_name,$ct_id,CT,$macs"
                ((total_entries++))
            done
        fi
    done

    __info__ "Total entries: $total_entries" >&2
}

main

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
