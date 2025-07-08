#!/bin/bash
#
# RestartManager.sh
#
# This script restarts all Ceph Manager (ceph-mgr) daemons running on the
# local Proxmox/Ceph host.  It discovers any active `ceph-mgr@<id>.service`
# units and restarts them safely with systemd.
#
# Usage:
#   ./RestartManager.sh restart     # (default) Restart mgr daemons
#   ./RestartManager.sh status      # Show mgr daemon status only
#
# Function Index:
#   - _find_mgr_units
#   - restartMgr
#   - statusMgr
#

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
source "${UTILITYPATH}/Prompts.sh"

__check_root__
__check_proxmox__

# ---------------------------------------------------------------------------
# Helper: discover active mgr units on this host
# ---------------------------------------------------------------------------
function _find_mgr_units() {
    systemctl list-units --type=service --state=active \
        | awk '/ceph-mgr@/ {print $1}'
}

# ---------------------------------------------------------------------------
# Restart every ceph-mgr unit found
# ---------------------------------------------------------------------------
function restartMgr() {
    local units=($(_find_mgr_units))
    if [[ ${#units[@]} -eq 0 ]]; then
        echo "No active ceph-mgr units found on this host."
        exit 0
    fi

    echo "Restarting Ceph Manager daemons..."
    for unit in "${units[@]}"; do
        echo "  → Restarting $unit"
        systemctl restart "$unit"
    done
    echo "All ceph-mgr daemons have been restarted."
}

# ---------------------------------------------------------------------------
# Display status for every ceph-mgr unit
# ---------------------------------------------------------------------------
function statusMgr() {
    local units=($(_find_mgr_units))
    if [[ ${#units[@]} -eq 0 ]]; then
        echo "No active ceph-mgr units found on this host."
        exit 0
    fi

    systemctl status "${units[@]}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
case "${1:-restart}" in
    restart)
        restartMgr
        ;;
    status)
        statusMgr
        ;;
    *)
        echo "Error: Unsupported command '${1}'. Use 'restart' or 'status'."
        exit 2
        ;;
esac
