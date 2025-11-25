#!/bin/bash
#
# RestartOSDs.sh
#
# This script restarts every Ceph OSD (Object Storage Daemon) running on the
# **local** Proxmox/Ceph host.  It detects active `ceph-osd@<id>.service`
# units with systemd and restarts them safely.
#
# Usage:
#   RestartOSDs.sh restart     # (default) Restart all OSD daemons
#   RestartOSDs.sh status      # Show OSD daemon status only
#
# Function Index:
#   - _find_osd_units
#   - restartOsd
#   - statusOsd
#

set -euo pipefail

###############################################################################
# Prerequisites
###############################################################################
trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

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
    local units
    mapfile -t units < <(_find_osd_units)
    if [[ ${#units[@]} -eq 0 ]]; then
        echo "No active ceph-osd units found on this host."
        exit 0
    fi

    echo "Restarting Ceph OSD daemons..."
    for unit in "${units[@]}"; do
        echo "  -> Restarting $unit"
        systemctl restart "$unit"
    done
    echo "All ceph-osd daemons have been restarted."
}

###############################################################################
# Display status for every ceph-osd unit
###############################################################################
function statusOsd() {
    local units
    mapfile -t units < <(_find_osd_units)
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

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-24
#
# Changes:
# - 2025-11-21: Fixed array assignment to use mapfile (SC2207)
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# - 2025-11-21: Changed array assignment from `units=($(...))` to `mapfile -t units < <(...)`
#
# Known issues:
# -
#

