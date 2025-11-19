#!/bin/bash
#
# FilesystemTrimAll.sh
#
# A script to run TRIM on all relevant filesystems for LXC containers and QEMU VMs
# (via qm) that have the guest agent enabled. This can be done for the current host
# or all hosts in the Proxmox cluster.
#
# Usage:
#   FilesystemTrimAll.sh [all|host]
#
# Description:
#   - If "host" is specified (or no argument is given), the script will run TRIM
#     on this Proxmox node only.
#   - If "all" is specified, the script will attempt to run TRIM on all nodes in
#     the cluster, via SSH.
#   - For QEMU VMs, only those which have the guest agent enabled will be trimmed.
#   - LXC containers do not require the guest agent; if pct fstrim is available,
#     they will be trimmed.
#
# Examples:
#   # Runs TRIM on the current node only (default behavior).
#   FilesystemTrimAll.sh
#
#   # Same as above, explicitly specifying "host".
#   FilesystemTrimAll.sh host
#
#   # Attempts to run TRIM on every node in the cluster.
#   FilesystemTrimAll.sh all
#
# Function Index:
#   - trim_qemu_vm
#   - trim_lxc_ct
#   - trim_on_node
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Cluster.sh
source "${UTILITYPATH}/Cluster.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

###############################################################################
# Preliminary Checks
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Function Definitions
###############################################################################
trim_qemu_vm() {
    local nodeName="$1"
    local vmId="$2"

    # Check if the guest agent is enabled
    if ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$nodeName" \
        "qm config \"$vmId\" 2>/dev/null | grep -Eq '^agent:.*(enable=1|=1)'"; then
        echo "[Node: \"$nodeName\"] Trimming QEMU VM ID: \"$vmId\""
        ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$nodeName" \
            "qm guest exec \"$vmId\" -- fstrim -a || echo 'Warning: fstrim command failed on VM \"$vmId\".'"
    else
        echo "[Node: \"$nodeName\"] Skipping QEMU VM ID: \"$vmId\" (guest agent not enabled)."
    fi
}

trim_lxc_ct() {
    local nodeName="$1"
    local ctId="$2"

    echo "[Node: \"$nodeName\"] Trimming LXC CT ID: \"$ctId\""
    ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$nodeName" \
        "pct fstrim \"$ctId\" || echo 'Warning: pct fstrim command failed on CT \"$ctId\".'"
}

trim_on_node() {
    local nodeName="$1"

    echo "---- [Node: \"$nodeName\"] Gathering QEMU VMs... ----"
    local vmIds=()
    readarray -t vmIds < <(__get_server_vms__ "$nodeName")

    if [[ -z "${vmIds[*]}" ]]; then
        echo "[Node: \"$nodeName\"] No QEMU VMs found."
    else
        for vmId in "${vmIds[@]}"; do
            trim_qemu_vm "$nodeName" "$vmId"
        done
    fi

    echo "---- [Node: \"$nodeName\"] Gathering LXC containers... ----"
    local ctIds=()
    readarray -t ctIds < <(__get_server_lxc__ "$nodeName")

    if [[ -z "${ctIds[*]}" ]]; then
        echo "[Node: \"$nodeName\"] No LXC containers found."
    else
        for ctId in "${ctIds[@]}"; do
            trim_lxc_ct "$nodeName" "$ctId"
        done
    fi
}

###############################################################################
# Main Script Logic
###############################################################################
MODE="$1"
if [[ -z "$MODE" ]]; then
    MODE="host"
fi

case "$MODE" in
    host)
        echo "Operating on current node only..."
        localNode="$(hostname)"

        echo "---- [Node: \"$localNode\"] Gathering QEMU VMs... ----"
        declare vmIds=()
        readarray -t vmIds < <(__get_server_vms__ "$localNode")

        if [[ -z "${vmIds[*]}" ]]; then
            echo "[Node: \"$localNode\"] No QEMU VMs found."
        else
            for vmId in "${vmIds[@]}"; do
                if qm config "$vmId" 2>/dev/null | grep -Eq '^agent:.*(enable=1|=1)'; then
                    echo "[Node: \"$localNode\"] Trimming QEMU VM ID: \"$vmId\""
                    qm guest exec "$vmId" -- fstrim -a \
                        || echo "Warning: fstrim command failed on VM \"$vmId\"."
                else
                    echo "[Node: \"$localNode\"] Skipping QEMU VM ID: \"$vmId\" (guest agent not enabled)."
                fi
            done
        fi

        echo "---- [Node: \"$localNode\"] Gathering LXC containers... ----"
        declare ctIds=()
        readarray -t ctIds < <(__get_server_lxc__ "$localNode")

        if [[ -z "${ctIds[*]}" ]]; then
            echo "[Node: \"$localNode\"] No LXC containers found."
        else
            for ctId in "${ctIds[@]}"; do
                echo "[Node: \"$localNode\"] Trimming LXC CT ID: \"$ctId\""
                pct fstrim "$ctId" \
                    || echo "Warning: pct fstrim command failed on CT \"$ctId\"."
            done
        fi
        ;;

    all)
        echo "Operating on all nodes in the cluster..."
        declare nodeList
        nodeList=$(pvesh get /cluster/resources --type node 2>/dev/null | grep '"name"' | awk -F'"' '{print $4}')

        if [[ -z "$nodeList" ]]; then
            echo "No cluster nodes found or failed to retrieve node list."
            exit 1
        fi

        for node in $nodeList; do
            echo "========================================================================"
            echo "Proceeding with Node: \"$node\""
            echo "========================================================================"
            trim_on_node "$node"
        done
        ;;

    *)
        echo "Usage: \"$0\" [all|host]"
        echo "Error: Invalid argument \"$MODE\""
        exit 1
        ;;
esac

echo "Done. All relevant TRIM operations have been attempted."

###############################################################################
# Testing status
###############################################################################
# Tested single-node
# Tested multi-node
