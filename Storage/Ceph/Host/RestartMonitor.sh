#!/bin/bash
#
# RestartMonitor.sh
#
# This script restarts all Ceph Monitor (ceph-mon) daemons running on the
# local Proxmox/Ceph host. It automatically discovers active
# `ceph-mon@<id>.service` units and restarts them safely with systemd.
#
# Usage:
#   ./RestartMonitor.sh restart     # (default) Restart MON daemons
#   ./RestartMonitor.sh status      # Show MON daemon status only
#
# Function Index:
#   - _find_mon_units
#   - restartMon
#   - statusMon
#

###############################################################################
# Prerequisites
###############################################################################
source "${UTILITYPATH}/Prompts.sh"

__check_root__
__check_proxmox__

###############################################################################
# Helper: discover active MON units on this host
###############################################################################
function _find_mon_units() {
    systemctl list-units --type=service --state=active \
        | awk '/ceph-mon@/ {print $1}'
}

###############################################################################
# Restart every ceph-mon unit found
###############################################################################
function restartMon() {
    local units=($(_find_mon_units))
    if [[ ${#units[@]} -eq 0 ]]; then
        echo "No active ceph-mon units found on this host."
        exit 0
    fi

    echo "Restarting Ceph Monitor daemons..."
    for unit in "${units[@]}"; do
        echo "  → Restarting $unit"
        systemctl restart "$unit"
    done
    echo "All ceph-mon daemons have been restarted."
}

###############################################################################
# Display status for every ceph-mon unit
###############################################################################
function statusMon() {
    local units=($(_find_mon_units))
    if [[ ${#units[@]} -eq 0 ]]; then
        echo "No active ceph-mon units found on this host."
        exit 0
    fi

    systemctl status "${units[@]}"
}

###############################################################################
# Main
###############################################################################
case "${1:-restart}" in
    restart)
        restartMon
        ;;
    status)
        statusMon
        ;;
    *)
        echo "Error: Unsupported command '${1}'. Use 'restart' or 'status'."
        exit 2
        ;;
esac
