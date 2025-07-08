#!/bin/bash
#
# RestartOSDs.sh
#
# This script restarts every Ceph OSD (Object Storage Daemon) running on the
# **local** Proxmox/Ceph host.  It detects active `ceph-osd@<id>.service`
# units with systemd and restarts them safely.
#
# Usage:
#   ./RestartOSDs.sh restart     # (default) Restart all OSD daemons
#   ./RestartOSDs.sh status      # Show OSD daemon status only
#
# Function Index:
#   - _find_osd_units
#   - restartOsd
#   - statusOsd
#

###############################################################################
# Prerequisites
###############################################################################
source "${UTILITYPATH}/Prompts.sh"

__check_root__
__check_proxmox__

###############################################################################
# Helper: discover active OSD units on this host
###############################################################################
function _find_osd_units() {
    systemctl list-units --type=service --state=active \
        | awk '/ceph-osd@/ {print $1}'
}

###############################################################################
# Restart every ceph-osd unit found
###############################################################################
function restartOsd() {
    local units=($(_find_osd_units))
    if [[ ${#units[@]} -eq 0 ]]; then
        echo "No active ceph-osd units found on this host."
        exit 0
    fi

    echo "Restarting Ceph OSD daemons..."
    for unit in "${units[@]}"; do
        echo "  → Restarting $unit"
        systemctl restart "$unit"
    done
    echo "All ceph-osd daemons have been restarted."
}

###############################################################################
# Display status for every ceph-osd unit
###############################################################################
function statusOsd() {
    local units=($(_find_osd_units))
    if [[ ${#units[@]} -eq 0 ]]; then
        echo "No active ceph-osd units found on this host."
        exit 0
    fi

    systemctl status "${units[@]}"
}

###############################################################################
# Main
###############################################################################
case "${1:-restart}" in
    restart)
        restartOsd
        ;;
    status)
        statusOsd
        ;;
    *)
        echo "Error: Unsupported command '${1}'. Use 'restart' or 'status'."
        exit 2
        ;;
esac
