#!/bin/bash
#
# FindLinkedClone.sh
#
# Finds child VMs/containers cloned from a base VM or container ID.
#
# Usage:
#   FindLinkedClone.sh <base_vmid>
#
# Arguments:
#   base_vmid - Base VM or container ID
#
# Examples:
#   FindLinkedClone.sh 1005
#   FindLinkedClone.sh 100
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Queries.sh
source "${UTILITYPATH}/Queries.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    __check_cluster_membership__

    if [[ $# -lt 1 ]]; then
        __err__ "Missing required argument"
        echo "Usage: $0 <base_vmid>"
        exit 64
    fi

    local base_vmid="$1"

    __info__ "Finding linked clones for base ID: $base_vmid"

    # Determine if QEMU or LXC
    shopt -s nullglob
    local -a qemu_configs=(/etc/pve/nodes/*/qemu-server/"${base_vmid}".conf)
    local -a lxc_configs=(/etc/pve/nodes/*/lxc/"${base_vmid}".conf)
    shopt -u nullglob

    local vm_type=""
    local cfg_dir=""

    if [[ ${#qemu_configs[@]} -gt 0 ]]; then
        vm_type="QEMU"
        cfg_dir="qemu-server"
    elif [[ ${#lxc_configs[@]} -gt 0 ]]; then
        vm_type="LXC"
        cfg_dir="lxc"
    else
        __err__ "Base VM/CT not found: $base_vmid"
        exit 1
    fi

    __ok__ "Detected base $vm_type with ID: $base_vmid"

    # Collect all config files
    __info__ "Scanning cluster for $vm_type configurations"

    shopt -s nullglob
    local -a conf_files=()
    local -a nodes=(/etc/pve/nodes/*)

    for node_path in "${nodes[@]}"; do
        if [[ -d "${node_path}/${cfg_dir}" ]]; then
            for conf_file in "${node_path}/${cfg_dir}"/*.conf; do
                if [[ -e "$conf_file" ]]; then
                    conf_files+=("$conf_file")
                fi
            done
        fi
    done
    shopt -u nullglob

    __ok__ "Found ${#conf_files[@]} configuration file(s)"

    # Scan for children
    __info__ "Searching for linked clones"

    local -a children=()
    local scanned=0

    for conf_file in "${conf_files[@]}"; do
        local vmid
        vmid="$(basename "$conf_file" .conf)"
        ((scanned++))

        # Skip base VM itself
        if [[ "$vmid" == "$base_vmid" ]]; then
            continue
        fi

        # Look for base reference
        if grep -q "base-${base_vmid}-" "${conf_file}" 2>/dev/null; then
            children+=("$vmid")
            __ok__ "Found child: $vmid"
        fi
    done

    echo
    __info__ "Scan Summary:"
    __info__ "  Configurations scanned: $scanned"
    __info__ "  Linked clones found: ${#children[@]}"

    if [[ ${#children[@]} -eq 0 ]]; then
        __warn__ "No linked clones found for base $base_vmid"
        exit 0
    fi

    echo
    __ok__ "Linked Clones of $base_vmid:"
    for child_id in "${children[@]}"; do
        echo "  - $child_id"
    done
}

main "$@"

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
