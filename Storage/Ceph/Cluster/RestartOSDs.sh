#!/bin/bash
#
# RestartOSDs.sh
#
# Restarts every Ceph OSD on the cluster one at a time.
#
# Usage:
#   ./RestartOSDs.sh
#
# This script iterates over all the Ceph OSDs in the cluster,
# restarting each OSD service sequentially. It handles both local
# and remote OSD restarts via SSH.
#

source "${UTILITYPATH}/Communication.sh"
source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Check for root privileges and Proxmox environment
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Ensure required packages/commands are available
###############################################################################
__install_or_prompt__ "jq"

###############################################################################
# Retrieve list of Ceph OSD IDs
###############################################################################
OSD_IDS=$(ceph osd ls 2>/dev/null)
if [ $? -ne 0 ]; then
    __err__ "Failed to retrieve Ceph OSD list. Ensure Ceph is running."
    exit 1
fi

if [ -z "$OSD_IDS" ]; then
    __info__ "No Ceph OSDs found. Exiting."
    exit 0
fi

totalOSDs=$(echo "$OSD_IDS" | wc -w)
__info__ "Found ${totalOSDs} Ceph OSD(s). Restarting them one at a time."

###############################################################################
# Function: wait_for_osd_active
# Waits until the specified Ceph OSD service is active or a timeout is reached.
###############################################################################
wait_for_osd_active(){
    local targetHost="$1"
    local osdId="$2"
    local timeout=60
    local elapsed=0
    local status=""
    while true; do
        if [ "$targetHost" = "local" ]; then
            status=$(systemctl is-active "ceph-osd@${osdId}")
        else
            status=$(ssh root@"${targetHost}" "systemctl is-active ceph-osd@${osdId}" 2>/dev/null)
        fi
        if [ "$status" = "active" ]; then
            break
        fi
        sleep 5
        elapsed=$((elapsed+5))
        if [ $elapsed -ge $timeout ]; then
            __err__ "OSD ceph-osd@${osdId} did not become active after restart."
            break
        fi
    done
}

###############################################################################
# Loop through each OSD ID and restart the corresponding service
###############################################################################
currentOSD=1
for osdId in $OSD_IDS; do
    __update__ "Processing OSD ${currentOSD} of ${totalOSDs}: ceph-osd@${osdId}"

    # Retrieve JSON details for the current OSD
    osdJson=$(ceph osd find "${osdId}" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$osdJson" ]; then
         __err__ "Failed to retrieve details for ceph-osd@${osdId}."
         currentOSD=$((currentOSD+1))
         continue
    fi

    # Parse the host name from the JSON data
    osdHost=$(echo "$osdJson" | jq -r '.crush_location.host')
    if [ -z "$osdHost" ] || [ "$osdHost" = "null" ]; then
         __err__ "Host information for ceph-osd@${osdId} not found."
         currentOSD=$((currentOSD+1))
         continue
    fi

    # Determine if the OSD is running locally or on a remote host
    localHost=$(hostname)
    if [ "$osdHost" = "$localHost" ]; then
         targetHost="local"
    else
         targetHost=$(__get_ip_from_name__ "$osdHost")
         if [ -z "$targetHost" ]; then
             __err__ "Failed to resolve IP for host '${osdHost}'."
             currentOSD=$((currentOSD+1))
             continue
         fi
    fi

    # Restart the Ceph OSD service on the appropriate host
    if [ "$targetHost" = "local" ]; then
         systemctl restart "ceph-osd@${osdId}"
         if [ $? -eq 0 ]; then
             __ok__ "Successfully restarted ceph-osd@${osdId} on local."
         else
             __err__ "Failed to restart ceph-osd@${osdId} on local."
         fi
    else
         ssh root@"${targetHost}" "systemctl restart ceph-osd@${osdId}"
         if [ $? -eq 0 ]; then
             __ok__ "Successfully restarted ceph-osd@${osdId} on ${osdHost} (${targetHost})."
         else
             __err__ "Failed to restart ceph-osd@${osdId} on ${osdHost} (${targetHost})."
         fi
    fi

    # Wait until the OSD service becomes active
    wait_for_osd_active "${targetHost}" "${osdId}"

    # Pause briefly before processing the next OSD
    sleep 5
    currentOSD=$((currentOSD+1))
done

__ok__ "All Ceph OSDs processed."
