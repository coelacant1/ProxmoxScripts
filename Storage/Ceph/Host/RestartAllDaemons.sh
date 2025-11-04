#!/bin/bash
#
# RestartAllDaemons.sh
#
# This script restarts all local Ceph services on the current Proxmox/Ceph host,
# including:
#   - ceph-mon (Monitor)
#   - ceph-mds (Metadata Server)
#   - ceph-mgr (Manager)
#   - ceph-osd (Object Storage Daemons)
#
# Usage:
#   RestartAllDaemons.sh restart   # (default) Restart all detected Ceph daemons
#   RestartAllDaemons.sh status    # Show status for all Ceph daemons
#
# Function Index:
#   - _find_units
#   - restartUnits
#   - statusUnits
#

set -euo pipefail

###############################################################################
# Prerequisites
###############################################################################
trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

source "${UTILITYPATH}/Prompts.sh"

__check_root__
__check_proxmox__

###############################################################################
# Discover systemd units by type (mon, mgr, mds, osd)
###############################################################################
function _find_units() {
    local type="$1"
    systemctl list-units --type=service --state=active | awk "/ceph-${type}@/ {print \$1}"
}

###############################################################################
# Restart all units of a specific type
###############################################################################
function restartUnits() {
    local type="$1"
    local units=($(_find_units "$type"))
    if [[ ${#units[@]} -eq 0 ]]; then
        echo "No active ceph-${type} units found on this host."
        return
    fi

    echo "Restarting ceph-${type} daemons..."
    for unit in "${units[@]}"; do
        echo "  -> Restarting $unit"
        systemctl restart "$unit"
    done
}

###############################################################################
# Show status of all units of a specific type
###############################################################################
function statusUnits() {
    local type="$1"
    local units=($(_find_units "$type"))
    if [[ ${#units[@]} -eq 0 ]]; then
        echo "No active ceph-${type} units found on this host."
        return
    fi

    systemctl status "${units[@]}"
}

###############################################################################
# Main Logic
###############################################################################
command="${1:-restart}"
types=("mon" "mds" "mgr" "osd")

case "$command" in
    restart)
        for type in "${types[@]}"; do
            restartUnits "$type"
        done
        echo "All detected Ceph daemons have been restarted."
        ;;
    status)
        for type in "${types[@]}"; do
            statusUnits "$type"
        done
        ;;
    *)
        echo "Error: Unsupported command '${command}'. Use 'restart' or 'status'."
        exit 2
        ;;
esac
