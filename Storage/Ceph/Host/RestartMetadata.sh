#!/bin/bash
#
# RestartMetadata.sh
#
# This script restarts all Ceph Metadata Server (ceph-mds) daemons running on
# the local Proxmox/Ceph host.  It discovers any active `ceph-mds@<id>.service`
# units and restarts them safely with systemd.
#
# Usage:
#   RestartMetadata.sh restart     # (default) Restart MDS daemons
#   RestartMetadata.sh status      # Show MDS daemon status only
#
# Function Index:
#   - _find_mds_units
#   - restartMds
#   - statusMds
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
# Helper: discover active MDS units on this host
###############################################################################
function _find_mds_units() {
    systemctl list-units --type=service --state=active \
        | awk '/ceph-mds@/ {print $1}'
}

###############################################################################
# Restart every ceph-mds unit found
###############################################################################
function restartMds() {
    local units
    mapfile -t units < <(_find_mds_units)
    if [[ ${#units[@]} -eq 0 ]]; then
        echo "No active ceph-mds units found on this host."
        exit 0
    fi

    echo "Restarting Ceph Metadata Server daemons..."
    for unit in "${units[@]}"; do
        echo "  -> Restarting $unit"
        systemctl restart "$unit"
    done
    echo "All ceph-mds daemons have been restarted."
}

###############################################################################
# Display status for every ceph-mds unit
###############################################################################
function statusMds() {
    local units
    mapfile -t units < <(_find_mds_units)
    if [[ ${#units[@]} -eq 0 ]]; then
        echo "No active ceph-mds units found on this host."
        exit 0
    fi

    systemctl status "${units[@]}"
}

###############################################################################
# Main
###############################################################################
case "${1:-restart}" in
    restart)
        restartMds
        ;;
    status)
        statusMds
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

