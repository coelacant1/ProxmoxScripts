#!/bin/bash
#
# RestartManagers.sh
#
# Restarts every Ceph Manager (mgr) on the cluster one at a time.
#
# Usage:
#   RestartManagers.sh
#
# This script retrieves the active and standby Ceph mgr daemons from the cluster,
# determines on which node each mgr is running by parsing the manager’s reported address,
# and restarts each mgr service one at a time. Remote restarts are executed via SSH.
#
# Function Index:
#   - wait_for_mgr_active
#   - main
#

set -euo pipefail

source "${UTILITYPATH}/Communication.sh"
source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/Cluster.sh"

###############################################################################
# Check prerequisites: root privileges and Proxmox environment
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Ensure required commands are installed
###############################################################################
__install_or_prompt__ "jq"

# --- wait_for_mgr_active -----------------------------------------------------
wait_for_mgr_active(){
    local targetHost="$1"
    local mgrName="$2"
    local timeout=120
    local elapsed=0
    local status=""

    while true; do
        if [[ "$targetHost" == "local" ]]; then
            status=$(systemctl is-active "ceph-mgr@${mgrName}")
        else
            status=$(ssh root@"${targetHost}" "systemctl is-active ceph-mgr@${mgrName}" 2>/dev/null)
        fi

        if [[ "$status" == "active" ]]; then
            break
        fi

        sleep 5
        elapsed=$((elapsed+5))

        if [[ $elapsed -ge $timeout ]]; then
            __err__ "Manager ceph-mgr@${mgrName} did not become active after restart on ${targetHost}"
            break
        fi
    done
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    __install_or_prompt__ "jq"

    # Retrieve Ceph manager information
    local mgrJSON
    mgrJSON=$(ceph mgr dump --format json 2>/dev/null)
    if [[ $? -ne 0 ]] || [[ -z "$mgrJSON" ]]; then
        __err__ "Failed to retrieve Ceph mgr dump"
        exit 1
    fi

    # Parse manager details
    local -a mgrNames=()
    local -a mgrIPs=()

    # Parse active manager
    local activeMgrName activeMgrAddr activeMgrIP
    activeMgrName=$(echo "$mgrJSON" | jq -r '.active_name')
    activeMgrAddr=$(echo "$mgrJSON" | jq -r '.active_addr')
    activeMgrIP="${activeMgrAddr%%:*}"

    if [[ -z "$activeMgrName" ]] || [[ "$activeMgrName" == "null" ]]; then
        activeMgrName="$(__get_name_from_ip__ "$activeMgrIP")"
    fi

    mgrNames+=("$activeMgrName")
    mgrIPs+=("$activeMgrIP")

    # Parse standby managers
    local -a standbyMgrLines
    readarray -t standbyMgrLines < <(echo "$mgrJSON" | jq -r '.standbys[] | "\(.name) \(.addr)"')

    for line in "${standbyMgrLines[@]}"; do
        local standbyName standbyAddr standbyIP
        standbyName=$(echo "$line" | awk '{print $1}')
        standbyAddr=$(echo "$line" | awk '{print $2}')
        standbyIP="${standbyAddr%%:*}"

        if [[ -z "$standbyName" ]] || [[ "$standbyName" == "null" ]]; then
            standbyName="$(__get_name_from_ip__ "$standbyIP")"
        fi

        mgrNames+=("$standbyName")
        mgrIPs+=("$standbyIP")
    done

    local totalMgrs="${#mgrNames[@]}"
    if [[ "$totalMgrs" -eq 0 ]]; then
        __info__ "No Ceph managers found"
        exit 0
    fi

    __info__ "Found ${totalMgrs} Ceph manager(s) - restarting one at a time"

    # Process each manager
    local currentMgr=1
    for index in "${!mgrNames[@]}"; do
        local mgrName="${mgrNames[$index]}"
        local mgrIP="${mgrIPs[$index]}"

        __update__ "Processing manager ${currentMgr}/${totalMgrs}: ceph-mgr@${mgrName}"

        # Determine target host
        local targetHost
        if __is_local_ip__ "$mgrIP"; then
            targetHost="local"
        else
            targetHost="$(__get_ip_from_name__ "$mgrName")"
            if [[ -z "$targetHost" ]]; then
                __err__ "Failed to resolve IP for manager '$mgrName' - skipping"
                ((currentMgr++))
                continue
            fi
        fi

        # Restart manager service
        if [[ "$targetHost" == "local" ]]; then
            if systemctl restart "ceph-mgr@${mgrName}"; then
                __ok__ "Restarted ceph-mgr@${mgrName} on local"
            else
                __err__ "Failed to restart ceph-mgr@${mgrName} on local"
            fi
        else
            if ssh root@"${targetHost}" "systemctl restart ceph-mgr@${mgrName}"; then
                __ok__ "Restarted ceph-mgr@${mgrName} on ${targetHost}"
            else
                __err__ "Failed to restart ceph-mgr@${mgrName} on ${targetHost}"
            fi
        fi

        # Wait for service to become active
        wait_for_mgr_active "${targetHost}" "${mgrName}"

        sleep 5
        ((currentMgr++))
    done

    __ok__ "All Ceph managers processed!"
}

main

# Testing status:
#   - Updated to follow CONTRIBUTING.md guidelines
#   - Pending validation
