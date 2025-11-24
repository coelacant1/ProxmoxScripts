#!/bin/bash
#
# RestartOSDs.sh
#
# Restarts every Ceph OSD on the cluster one at a time.
#
# Usage:
#   RestartOSDs.sh
#
# This script iterates over all the Ceph OSDs in the cluster,
# restarting each OSD service sequentially. It handles both local
# and remote OSD restarts via SSH.
#
# Function Index:
#   - wait_for_osd_active
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Discovery.sh
source "${UTILITYPATH}/Discovery.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- wait_for_osd_active -----------------------------------------------------
wait_for_osd_active() {
    local target_host="$1"
    local osd_id="$2"
    local timeout=60
    local elapsed=0
    local status=""

    while true; do
        if [[ "$target_host" == "local" ]]; then
            status=$(systemctl is-active "ceph-osd@${osd_id}")
        else
            status=$(ssh "root@${target_host}" "systemctl is-active ceph-osd@${osd_id}" 2>/dev/null)
        fi

        if [[ "$status" == "active" ]]; then
            break
        fi

        sleep 5
        elapsed=$((elapsed + 5))

        if [[ $elapsed -ge $timeout ]]; then
            __err__ "OSD ceph-osd@${osd_id} did not become active after restart"
            break
        fi
    done
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __install_or_prompt__ "jq"

    # Retrieve list of Ceph OSD IDs
    local osd_ids
    if ! osd_ids=$(ceph osd ls 2>/dev/null); then
        __err__ "Failed to retrieve Ceph OSD list. Ensure Ceph is running."
        exit 1
    fi

    if [[ -z "$osd_ids" ]]; then
        __info__ "No Ceph OSDs found"
        exit 0
    fi

    local -a osd_array
    read -r -a osd_array <<<"$osd_ids"
    local total_osds=${#osd_array[@]}

    __info__ "Found ${total_osds} Ceph OSD(s). Restarting them one at a time."

    local current_osd=1
    local local_host
    local_host=$(hostname)

    for osd_id in "${osd_array[@]}"; do
        __update__ "Processing OSD ${current_osd} of ${total_osds}: ceph-osd@${osd_id}"

        # Retrieve JSON details for the current OSD
        local osd_json
        if ! osd_json=$(ceph osd find "${osd_id}" 2>/dev/null) || [[ -z "$osd_json" ]]; then
            __err__ "Failed to retrieve details for ceph-osd@${osd_id}"
            current_osd=$((current_osd + 1))
            continue
        fi

        # Parse the host name from the JSON data
        local osd_host
        osd_host=$(echo "$osd_json" | jq -r '.crush_location.host')

        if [[ -z "$osd_host" ]] || [[ "$osd_host" == "null" ]]; then
            __err__ "Host information for ceph-osd@${osd_id} not found"
            current_osd=$((current_osd + 1))
            continue
        fi

        # Determine if the OSD is running locally or on a remote host
        local target_host
        if [[ "$osd_host" == "$local_host" ]]; then
            target_host="local"
        else
            target_host=$(__get_ip_from_name__ "$osd_host")
            if [[ -z "$target_host" ]]; then
                __err__ "Failed to resolve IP for host '${osd_host}'"
                current_osd=$((current_osd + 1))
                continue
            fi
        fi

        # Restart the Ceph OSD service on the appropriate host
        if [[ "$target_host" == "local" ]]; then
            if systemctl restart "ceph-osd@${osd_id}"; then
                __ok__ "Successfully restarted ceph-osd@${osd_id} on local"
            else
                __err__ "Failed to restart ceph-osd@${osd_id} on local"
            fi
        else
            if ssh "root@${target_host}" "systemctl restart ceph-osd@${osd_id}"; then
                __ok__ "Successfully restarted ceph-osd@${osd_id} on ${osd_host} (${target_host})"
            else
                __err__ "Failed to restart ceph-osd@${osd_id} on ${osd_host} (${target_host})"
            fi
        fi

        # Wait until the OSD service becomes active
        wait_for_osd_active "${target_host}" "${osd_id}"

        # Pause briefly before processing the next OSD
        sleep 5
        current_osd=$((current_osd + 1))
    done

    __ok__ "All Ceph OSDs processed"
    __prompt_keep_installed_packages__
}

main

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-24
#
# Changes:
# - 2025-11-24: Deep technical validation - confirmed compliant
# - 2025-11-21: Validated against PVE Guide Chapter 8 and Section 22.06
# - 2025-11-21: Fixed arithmetic increment syntax (4 occurrences)
# - 2025-11-20: Updated to use utility functions and modern standards
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# - 2025-11-21: Changed ((var += 1)) to var=$((var + 1)) per CONTRIBUTING.md
#
# Known issues:
# -
#

