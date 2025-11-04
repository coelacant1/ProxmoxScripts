#!/bin/bash
#
# StartStoppedOSDs.sh
#
# Starts all stopped Ceph OSDs in the cluster.
#
# Usage:
#   StartStoppedOSDs.sh
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    local stopped_osds
    stopped_osds="$(ceph osd tree | awk '/down/ {print $4}')"

    if [[ -z "$stopped_osds" ]]; then
        __info__ "No OSDs reported as down"
        exit 0
    fi

    local started=0
    local failed=0

    while IFS= read -r osd_id; do
        [[ -z "$osd_id" ]] && continue

        __update__ "Starting OSD ID: $osd_id"
        if ceph osd start "osd.${osd_id}" &>/dev/null; then
            __ok__ "OSD $osd_id started successfully"
            ((started++))
        else
            __warn__ "Failed to start OSD $osd_id"
            ((failed++))
        fi
    done <<< "$stopped_osds"

    __info__ "Started: $started, Failed: $failed"
    [[ $failed -gt 0 ]] && exit 1
    __ok__ "All stopped OSDs started successfully"
}

main

# Testing status:
#   - Pending validation
