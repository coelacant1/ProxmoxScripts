#!/bin/bash
#
# ExportProxmoxResources.sh
#
# Exports VM and LXC configuration details to CSV file.
#
# Usage:
#   ExportProxmoxResources.sh [lxc|vm|both]
#
# Arguments:
#   type - Resource type (lxc, vm, both - default: both)
#
# Examples:
#   ExportProxmoxResources.sh lxc
#   ExportProxmoxResources.sh vm
#   ExportProxmoxResources.sh both
#
# Function Index:
#   - parse_config_files
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

__parse_args__ "type:string:both" "$@"

# Validate type argument
if [[ "$TYPE" != "lxc" && "$TYPE" != "vm" && "$TYPE" != "both" ]]; then
    __err__ "Invalid resource type: $TYPE (must be: lxc, vm, or both)"
    exit 64
fi

# --- parse_config_files ------------------------------------------------------
parse_config_files() {
    local node_name="$1"
    local resource_type="$2"
    local output_file="$3"

    # Parse QEMU VMs
    if [[ "$resource_type" == "both" || "$resource_type" == "vm" ]]; then
        local config_dir="/etc/pve/nodes/$node_name/qemu-server"

        if [[ -d "$config_dir" ]]; then
            for config_file in "$config_dir"/*.conf; do
                [[ -f "$config_file" ]] || continue

                local vmid
                vmid="$(basename "$config_file" .conf)"
                local vm_name
                vm_name="$(grep -Po '^name: \K.*' "$config_file" || echo "N/A")"
                local cpu_cores
                cpu_cores="$(grep -Po '^cores: \K.*' "$config_file" || echo "0")"
                local memory_mb
                memory_mb="$(grep -Po '^memory: \K.*' "$config_file" || echo "0")"

                local disk_gb
                disk_gb="$(grep -Po 'size=\K[0-9]+[A-Z]?' "$config_file" | awk '
                  {
                    if ($1 ~ /G$/) sum += substr($1, 1, length($1)-1)
                    else if ($1 ~ /M$/) sum += substr($1, 1, length($1)-1) / 1024
                    else if ($1 ~ /K$/) sum += substr($1, 1, length($1)-1) / (1024 * 1024)
                    else sum += $1 / (1024 * 1024 * 1024)
                  }
                  END {print sum}
                ' || echo "0")"

                echo "$node_name,$vmid,$vm_name,$cpu_cores,$((memory_mb)),$disk_gb" >>"$output_file"
            done
        fi
    fi

    # Parse LXC containers
    if [[ "$resource_type" == "both" || "$resource_type" == "lxc" ]]; then
        local config_dir="/etc/pve/nodes/$node_name/lxc"

        if [[ -d "$config_dir" ]]; then
            for config_file in "$config_dir"/*.conf; do
                [[ -f "$config_file" ]] || continue

                local vmid
                vmid="$(basename "$config_file" .conf)"
                local vm_name
                vm_name="$(grep -Po '^hostname: \K.*' "$config_file" || echo "N/A")"
                local cpu_cores
                cpu_cores="$(grep -Po '^cores: \K.*' "$config_file" || echo "0")"
                local memory_mb
                memory_mb="$(grep -Po '^memory: \K.*' "$config_file" || echo "0")"

                local disk_gb
                disk_gb="$(grep -Po 'size=\K[0-9]+[A-Z]?' "$config_file" | awk '
                  {
                    if ($1 ~ /G$/) sum += substr($1, 1, length($1)-1)
                    else if ($1 ~ /M$/) sum += substr($1, 1, length($1)-1) / 1024
                    else if ($1 ~ /K$/) sum += substr($1, 1, length($1)-1) / (1024 * 1024)
                    else sum += $1 / (1024 * 1024 * 1024)
                  }
                  END {print sum}
                ' || echo "0")"

                echo "$node_name,$vmid,$vm_name,$cpu_cores,$((memory_mb)),$disk_gb" >>"$output_file"
            done
        fi
    fi
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    local output_file="cluster_resources.csv"

    __info__ "Exporting Proxmox resources"
    __info__ "  Type: $TYPE"
    __info__ "  Output: $output_file"

    # Initialize CSV
    echo "Node,VMID,Name,CPU,Memory(MB),Disk(GB)" >"$output_file"

    # Get nodes
    local -a nodes
    mapfile -t nodes < <(ls /etc/pve/nodes 2>/dev/null || true)

    if [[ ${#nodes[@]} -eq 0 ]]; then
        __err__ "No nodes found in /etc/pve/nodes"
        exit 1
    fi

    __info__ "Processing ${#nodes[@]} node(s)"

    local processed=0
    for node in "${nodes[@]}"; do
        __update__ "Processing node: $node"
        parse_config_files "$node" "$TYPE" "$output_file"
        ((processed += 1))
    done

    local total_lines
    total_lines=$(($(wc -l <"$output_file") - 1))

    echo
    __ok__ "Export completed!"
    __info__ "  Nodes processed: $processed"
    __info__ "  Resources exported: $total_lines"
    __info__ "  Output file: $output_file"
}

main "$@"

# Testing status:
#   - Updated to use utility functions
#   - Updated to use ArgumentParser.sh
#   - Pending validation
