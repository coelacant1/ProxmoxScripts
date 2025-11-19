#!/bin/bash
#
# CreateOSDs.sh
#
# Creates Ceph OSDs on all unused block devices across all nodes in the Proxmox cluster.
# Automatically detects and provisions /dev/sd*, /dev/nvme*, /dev/hd* devices.
#
# Usage:
#   CreateOSDs.sh
#
# Requirements:
#   - Passwordless SSH or valid SSH keys for root on all nodes
#   - Functioning Proxmox cluster (pvecm available)
#   - Ceph installed and configured on each node
#   - Unused devices are not mounted or in LVM pvs
#
# Function Index:
#   - create_osds
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Cluster.sh
source "${UTILITYPATH}/Cluster.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- create_osds -------------------------------------------------------------
# Iterates over block devices and creates Ceph OSDs on unused devices.
# Checks if devices are valid, not mounted, and not in pvs before creating.
create_osds() {
    __info__ "Checking for devices on node: $(hostname)"

    local created=0
    local skipped=0
    local failed=0

    for device in /dev/sd* /dev/nvme* /dev/hd*; do
        [ -e "$device" ] || continue

        if [ ! -b "$device" ]; then
            __update__ "Skipping $device (not a valid block device)"
            ((skipped += 1))
            continue
        fi

        # Check if device is mounted or in pvs
        if lsblk -no MOUNTPOINT "$device" 2>/dev/null | grep -q '^$' && ! pvs 2>/dev/null | grep -q "$device"; then
            __update__ "Creating OSD for $device..."
            if ceph-volume lvm create --data "$device" 2>/dev/null; then
                __ok__ "Created OSD for $device"
                ((created += 1))
            else
                __warn__ "Failed to create OSD for $device"
                ((failed += 1))
            fi
        else
            __update__ "Skipping $device (in use - mounted or in pvs)"
            ((skipped += 1))
        fi
    done

    __info__ "Node $(hostname): Created: $created, Skipped: $skipped, Failed: $failed"
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    __check_cluster_membership__

    __info__ "Starting OSD creation on all cluster nodes"

    local remote_nodes
    readarray -t remote_nodes < <(__get_remote_node_ips__)

    if [ "${#remote_nodes[@]}" -eq 0 ]; then
        __err__ "No remote nodes found in the cluster"
    fi

    local total_nodes="${#remote_nodes[@]}"
    local current=0

    for node_ip in "${remote_nodes[@]}"; do
        ((current += 1))
        __update__ "Processing node $current/$total_nodes: $node_ip"

        if ssh root@"$node_ip" "$(typeset -f create_osds); create_osds" 2>/dev/null; then
            __ok__ "Completed OSD creation on $node_ip"
        else
            __warn__ "Issues encountered on $node_ip"
        fi
    done

    __ok__ "Ceph OSD creation process completed on all nodes"
}

main

# Testing status:
#   - Pending validation
