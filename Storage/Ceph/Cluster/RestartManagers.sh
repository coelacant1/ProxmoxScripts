#!/bin/bash
#
# RestartManagers.sh
#
# Restarts every Ceph Manager (mgr) on the cluster one at a time.
#
# Usage:
#   ./RestartManagers.sh
#
# This script retrieves the active and standby Ceph mgr daemons from the cluster,
# determines on which node each mgr is running by parsing the manager’s reported address,
# and restarts each mgr service one at a time. Remote restarts are executed via SSH.
#

source "${UTILITYPATH}/Communication.sh"
source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Check prerequisites: root privileges and Proxmox environment
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Ensure required commands are installed
###############################################################################
__install_or_prompt__ "jq"

###############################################################################
# Retrieve Ceph manager information in JSON format
###############################################################################
mgrJSON=$(ceph mgr dump --format json 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$mgrJSON" ]; then
    __err__ "Failed to retrieve Ceph mgr dump. Ensure Ceph is running."
    exit 1
fi

###############################################################################
# Parse manager details and build arrays for manager names and their IPs
###############################################################################
# The JSON is expected to have an active manager and a "standbys" array with objects
# containing "name" and "addr". We extract the IP from the "addr" field (format: IP:port/...)
# and verify the manager name.
mgrNames=()
mgrIPs=()

# Parse the active manager details.
activeMgrName=$(echo "$mgrJSON" | jq -r '.active_name')
activeMgrAddr=$(echo "$mgrJSON" | jq -r '.active_addr')
activeMgrIP="${activeMgrAddr%%:*}"

# If the active manager name is missing or null, try to resolve it by IP.
if [ -z "$activeMgrName" ] || [ "$activeMgrName" = "null" ]; then
    activeMgrName="$(__get_name_from_ip__ "$activeMgrIP")"
fi

mgrNames+=("$activeMgrName")
mgrIPs+=("$activeMgrIP")

# Parse standby manager details.
readarray -t standbyMgrLines < <(echo "$mgrJSON" | jq -r '.standbys[] | "\(.name) \(.addr)"')
for line in "${standbyMgrLines[@]}"; do
    standbyName=$(echo "$line" | awk '{print $1}')
    standbyAddr=$(echo "$line" | awk '{print $2}')
    standbyIP="${standbyAddr%%:*}"

    if [ -z "$standbyName" ] || [ "$standbyName" = "null" ]; then
        standbyName="$(__get_name_from_ip__ "$standbyIP")"
    fi

    mgrNames+=("$standbyName")
    mgrIPs+=("$standbyIP")
done

totalMgrs="${#mgrNames[@]}"
if [ "$totalMgrs" -eq 0 ]; then
    __info__ "No Ceph managers found. Exiting."
    exit 0
fi

__info__ "Found ${totalMgrs} Ceph manager(s). Restarting them one at a time."

###############################################################################
# Function: is_local_ip
# Checks if the provided IP address belongs to the local system.
###############################################################################
is_local_ip(){
    local ipToCheck="$1"
    local localIPs
    local ip
    localIPs=$(hostname -I)
    for ip in $localIPs; do
        if [ "$ip" = "$ipToCheck" ]; then
            return 0
        fi
    done
    return 1
}

###############################################################################
# Function: wait_for_mgr_active
# Waits until the ceph-mgr@<mgrName> service is active on the specified target host
# (local or remote) or until a timeout is reached.
# Timeout is set to 120 seconds.
###############################################################################
wait_for_mgr_active(){
    local targetHost="$1"
    local mgrName="$2"
    local timeout=120
    local elapsed=0
    local status=""
    while true; do
        if [ "$targetHost" = "local" ]; then
            status=$(systemctl is-active "ceph-mgr@${mgrName}")
        else
            status=$(ssh root@"${targetHost}" "systemctl is-active ceph-mgr@${mgrName}" 2>/dev/null)
        fi
        if [ "$status" = "active" ]; then
            break
        fi
        sleep 5
        elapsed=$((elapsed+5))
        if [ $elapsed -ge $timeout ]; then
            __err__ "Mgr ceph-mgr@${mgrName} did not become active after restart on ${targetHost}."
            break
        fi
    done
}

###############################################################################
# Loop through each manager, determine if it is local or remote, restart it,
# and wait until its service is active.
###############################################################################
currentMgr=1
for index in "${!mgrNames[@]}"; do
    mgrName="${mgrNames[$index]}"
    mgrIP="${mgrIPs[$index]}"

    __update__ "Processing manager ${currentMgr} of ${totalMgrs}: ceph-mgr@${mgrName}"

    # Determine the target host using the manager's IP.
    if is_local_ip "$mgrIP"; then
        targetHost="local"
    else
        # For remote managers, resolve the node IP using the manager name from the mapping.
        targetHost="$(__get_ip_from_name__ "$mgrName")"
        if [ -z "$targetHost" ]; then
            __err__ "Failed to resolve IP for manager '$mgrName'. Skipping."
            currentMgr=$((currentMgr+1))
            continue
        fi
    fi

    # Restart the manager service.
    if [ "$targetHost" = "local" ]; then
        systemctl restart "ceph-mgr@${mgrName}"
        if [ $? -eq 0 ]; then
            __ok__ "Successfully restarted ceph-mgr@${mgrName} on local."
        else
            __err__ "Failed to restart ceph-mgr@${mgrName} on local."
        fi
    else
        ssh root@"${targetHost}" "systemctl restart ceph-mgr@${mgrName}"
        if [ $? -eq 0 ]; then
            __ok__ "Successfully restarted ceph-mgr@${mgrName} on ${targetHost}."
        else
            __err__ "Failed to restart ceph-mgr@${mgrName} on ${targetHost}."
        fi
    fi

    # Wait until the manager service is active on the target host.
    wait_for_mgr_active "${targetHost}" "${mgrName}"

    sleep 5
    currentMgr=$((currentMgr+1))
done

__ok__ "All Ceph managers processed."
